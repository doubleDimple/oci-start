using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace OciStart.Core;

/// <summary>ClientWebSocket helper (align Mac NativeWSClient).</summary>
public sealed class WsClient : IAsyncDisposable
{
    private ClientWebSocket? _ws;
    private CancellationTokenSource? _cts;

    public event Action? Opened;
    public event Action<string?>? Closed;
    public event Action<string>? TextReceived;

    public bool IsOpen => _ws?.State == WebSocketState.Open;

    public static Uri MakeWsUrl(string httpBase, string path)
    {
        var b = AppSession.Normalize(httpBase).TrimEnd('/');
        if (b.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            b = "wss://" + b["https://".Length..];
        else if (b.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
            b = "ws://" + b["http://".Length..];
        if (!path.StartsWith('/')) path = "/" + path;
        return new Uri(b + path);
    }

    public async Task ConnectAsync(Uri url, CancellationToken ct = default)
    {
        await DisconnectAsync().ConfigureAwait(false);
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _ws = new ClientWebSocket();
        // Align Mac: remote/session WS often needs satoken Cookie
        var cookie = ApiClient.Shared.CookieHeaderForServer();
        if (!string.IsNullOrEmpty(cookie))
            _ws.Options.SetRequestHeader("Cookie", cookie);
        await _ws.ConnectAsync(url, _cts.Token).ConfigureAwait(false);
        Opened?.Invoke();
        _ = Task.Run(() => ReceiveLoop(_cts.Token));
    }

    public async Task SendJsonAsync(object payload, CancellationToken ct = default)
    {
        if (_ws is not { State: WebSocketState.Open }) return;
        var json = Encoding.UTF8.GetString(JsonUtil.Serialize(payload));
        var buf = Encoding.UTF8.GetBytes(json);
        await _ws.SendAsync(buf, WebSocketMessageType.Text, true, ct).ConfigureAwait(false);
    }

    public async Task SendTextAsync(string text, CancellationToken ct = default)
    {
        if (_ws is not { State: WebSocketState.Open }) return;
        var buf = Encoding.UTF8.GetBytes(text);
        await _ws.SendAsync(buf, WebSocketMessageType.Text, true, ct).ConfigureAwait(false);
    }

    private async Task ReceiveLoop(CancellationToken ct)
    {
        var buffer = new byte[8192];
        var sb = new StringBuilder();
        try
        {
            while (_ws is { State: WebSocketState.Open } && !ct.IsCancellationRequested)
            {
                sb.Clear();
                WebSocketReceiveResult result;
                do
                {
                    result = await _ws.ReceiveAsync(buffer, ct).ConfigureAwait(false);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        Closed?.Invoke(result.CloseStatusDescription);
                        return;
                    }
                    sb.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
                } while (!result.EndOfMessage);

                if (result.MessageType == WebSocketMessageType.Text)
                    TextReceived?.Invoke(sb.ToString());
            }
        }
        catch (OperationCanceledException)
        {
            Closed?.Invoke(null);
        }
        catch (Exception ex)
        {
            Closed?.Invoke(ex.Message);
        }
    }

    public async Task DisconnectAsync()
    {
        try
        {
            _cts?.Cancel();
            if (_ws is { State: WebSocketState.Open })
                await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None)
                    .ConfigureAwait(false);
        }
        catch { /* ignore */ }
        finally
        {
            _ws?.Dispose();
            _ws = null;
            _cts?.Dispose();
            _cts = null;
        }
    }

    public ValueTask DisposeAsync() => new(DisconnectAsync());
}
