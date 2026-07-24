using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Instances;

/// <summary>
/// 控制台整页：/ws/console + 内嵌 noVNC 画布（WebView2，对齐 Mac WKWebView 专用画布，非整页 FTL）.
/// </summary>
public sealed class InstanceConsoleView : UserControl
{
    private readonly InstanceItem _item;
    private readonly Action _onBack;
    private readonly InstancesService _service = new();
    private readonly WsClient _ws = new();
    private readonly PageScaffold _scaffold = new();
    private readonly TextBlock _status = new()
    {
        FontSize = 13,
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush")
    };
    private readonly TextBox _log = new()
    {
        IsReadOnly = true,
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        FontFamily = new FontFamily("Consolas, Cascadia Mono"),
        FontSize = 12,
        Background = Brushes.Black,
        Foreground = new SolidColorBrush(Color.FromRgb(0xC9, 0xD1, 0xD9)),
        BorderThickness = new Thickness(0)
    };
    private readonly Grid _canvasHost = new() { Background = Brushes.Black };
    private readonly TextBlock _canvasPlaceholder = new()
    {
        Text = "点击「创建 VNC 连接」",
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = new SolidColorBrush(Color.FromArgb(0x90, 0xFF, 0xFF, 0xFF)),
        FontSize = 13
    };
    private WebView2? _webView;
    private bool _webViewReady;
    private string? _lastVncKey;
    private string? _vncWsUrl;
    private string _connectionCommand = "";
    private int? _websockifyPort;
    private bool _connected;
    private bool _connecting;
    private bool _needsWebsockify;
    private DispatcherTimer? _heartbeat;
    private readonly List<string> _pendingLogs = [];
    private bool _logFlushScheduled;
    private Button? _installBtn;

    public InstanceConsoleView(InstanceItem item, Action onBack)
    {
        _item = item;
        _onBack = onBack;

        _scaffold.Title = "控制台 — " + (string.IsNullOrEmpty(item.DisplayName) ? "实例" : item.DisplayName);
        _scaffold.Subtitle = "VNC · /ws/console · noVNC";
        _installBtn = FormFieldFactory.Secondary("安装 websockify", async (_, _) => await InstallWebsockifyAsync());
        _installBtn.Visibility = Visibility.Collapsed;
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("返回列表", async (_, _) =>
            {
                await TeardownAsync().ConfigureAwait(true);
                _onBack();
            }),
            FormFieldFactory.Primary("创建 VNC 连接", async (_, _) => await ConnectAsync()),
            FormFieldFactory.Secondary("断开", async (_, _) => await DisconnectAsync()),
            FormFieldFactory.Secondary("重引导", async (_, _) => await RebootAsync()),
            FormFieldFactory.Secondary("复制命令", (_, _) => CopyCommand()),
            FormFieldFactory.Secondary("浏览器打开", (_, _) => OpenBrowser()),
            _installBtn);

        _canvasHost.Children.Add(_canvasPlaceholder);

        var statusBar = new Border
        {
            Padding = new Thickness(12, 8, 12, 8),
            Background = (Brush)Application.Current.FindResource("CardBgBrush"),
            BorderBrush = (Brush)Application.Current.FindResource("AppBorderBrush"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = _status
        };

        var logPanel = new DockPanel { MinHeight = 140, MaxHeight = 220 };
        var logTitle = new TextBlock
        {
            Text = "会话日志",
            FontSize = 12,
            Margin = new Thickness(8, 6, 8, 4),
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
        };
        DockPanel.SetDock(logTitle, Dock.Top);
        logPanel.Children.Add(logTitle);
        logPanel.Children.Add(_log);

        var root = new DockPanel();
        DockPanel.SetDock(statusBar, Dock.Top);
        DockPanel.SetDock(logPanel, Dock.Bottom);
        root.Children.Add(statusBar);
        root.Children.Add(logPanel);
        root.Children.Add(_canvasHost);
        _scaffold.SetBody(root);
        Content = _scaffold;

        _status.Text = "未连接";
        AppendLog("欢迎使用 OCI-Start 控制台");
        AppendLog("对齐 Mac：WebSocket 建隧道后内嵌 noVNC 画布（非业务整页 WebView）");

        _ws.TextReceived += OnWsText;
        _ws.Closed += reason => Dispatcher.Invoke(() =>
        {
            if (_connected || _connecting)
            {
                _connected = false;
                _connecting = false;
                StopHeartbeat();
                _vncWsUrl = null;
                _websockifyPort = null;
                ClearCanvas();
                _status.Text = string.IsNullOrEmpty(reason) ? "已断开" : "已断开：" + reason;
                AppendLog("■ " + _status.Text);
            }
        });

        Unloaded += async (_, _) => await TeardownAsync();
        _ = EnsureWebViewAsync();
    }

    private async Task EnsureWebViewAsync()
    {
        try
        {
            _webView = new WebView2();
            await _webView.EnsureCoreWebView2Async().ConfigureAwait(true);
            _webView.CoreWebView2.Settings.IsStatusBarEnabled = false;
            _webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            _webView.CoreWebView2.WebMessageReceived += (_, e) =>
            {
                var msg = e.TryGetWebMessageAsString() ?? e.WebMessageAsJson;
                Dispatcher.Invoke(() => OnCanvasMessage(msg));
            };
            _webViewReady = true;
            if (!string.IsNullOrEmpty(_vncWsUrl))
                ApplyCanvas(_vncWsUrl!);
        }
        catch (Exception ex)
        {
            AppendLog("⚠️ WebView2 初始化失败：" + ex.Message);
            AppendLog("   可改用「浏览器打开」；或安装 Evergreen WebView2 Runtime");
            _webViewReady = false;
        }
    }

    private async Task ConnectAsync()
    {
        if (string.IsNullOrEmpty(_item.Id))
        {
            ToastService.Error("实例 ID 无效");
            return;
        }
        var tenantId = _item.EffectiveTenantId;
        if (string.IsNullOrEmpty(tenantId) || tenantId == "0")
        {
            ToastService.Error("缺少租户 ID");
            return;
        }

        await DisconnectAsync().ConfigureAwait(true);
        _connecting = true;
        _connected = false;
        _needsWebsockify = false;
        if (_installBtn != null) _installBtn.Visibility = Visibility.Collapsed;
        _status.Text = "正在创建控制台连接…";
        AppendLog("▶ 创建 VNC 控制台连接…");
        try
        {
            var url = WsClient.MakeWsUrl(AppSession.Shared.ServerUrl, "/ws/console");
            await _ws.ConnectAsync(url).ConfigureAwait(true);
            await Task.Delay(200).ConfigureAwait(true);
            await _ws.SendJsonAsync(new
            {
                type = "create_connection",
                data = new
                {
                    instanceId = _item.Id,
                    tenantId,
                    displayName = string.IsNullOrEmpty(_item.PublicIps) ? _item.DisplayName : _item.PublicIps,
                    connectionType = "vnc"
                }
            }).ConfigureAwait(true);
            StartHeartbeat();
        }
        catch (Exception ex)
        {
            _connecting = false;
            _status.Text = "连接失败";
            AppendLog("❌ " + ex.Message);
            ToastService.Error(ex.Message);
        }
    }

    private async Task DisconnectAsync()
    {
        StopHeartbeat();
        try
        {
            if (_ws.IsOpen)
                await _ws.SendJsonAsync(new { type = "disconnect" }).ConfigureAwait(true);
        }
        catch { /* ignore */ }
        await _ws.DisconnectAsync().ConfigureAwait(true);
        _connected = false;
        _connecting = false;
        _vncWsUrl = null;
        _websockifyPort = null;
        ClearCanvas();
        _status.Text = "已断开";
    }

    private async Task TeardownAsync()
    {
        await DisconnectAsync().ConfigureAwait(true);
        try
        {
            if (_webView != null)
            {
                _canvasHost.Children.Remove(_webView);
                _webView.Dispose();
                _webView = null;
            }
        }
        catch { /* ignore */ }
        _webViewReady = false;
    }

    private async Task RebootAsync()
    {
        if (MessageBox.Show($"将对「{_item.DisplayName}」执行重引导（heavy restart）？", "重新引导",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
            return;
        try
        {
            var id = string.IsNullOrEmpty(_item.InstanceId) ? _item.Id : _item.InstanceId;
            var msg = await _service.HeavyRestartAsync(id, _item.EffectiveTenantId).ConfigureAwait(true);
            ToastService.Success(msg);
            AppendLog("✅ " + msg);
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
    }

    private async Task InstallWebsockifyAsync()
    {
        if (_installBtn != null) _installBtn.IsEnabled = false;
        AppendLog("▶ 正在通过服务端安装 websockify…");
        try
        {
            var result = await _service.InstallWebsockifyAsync().ConfigureAwait(true);
            foreach (var line in (result.log ?? "").Split('\n'))
            {
                if (!string.IsNullOrWhiteSpace(line)) AppendLog("   " + line.TrimEnd());
            }
            if (result.ok)
            {
                _needsWebsockify = false;
                if (_installBtn != null) _installBtn.Visibility = Visibility.Collapsed;
                var msg = string.IsNullOrEmpty(result.message) ? "websockify 安装成功" : result.message;
                ToastService.Success(msg);
                AppendLog("✅ " + msg + (string.IsNullOrEmpty(result.binary) ? "" : " (" + result.binary + ")"));
                AppendLog("   请重新「创建 VNC 连接」以加载画面");
            }
            else
            {
                _needsWebsockify = true;
                if (_installBtn != null) _installBtn.Visibility = Visibility.Visible;
                var err = string.IsNullOrEmpty(result.message) ? "websockify 安装失败" : result.message;
                ToastService.Error(err);
                AppendLog("❌ " + err);
            }
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
            AppendLog("❌ " + ex.Message);
        }
        finally
        {
            if (_installBtn != null) _installBtn.IsEnabled = true;
        }
    }

    private void CopyCommand()
    {
        var c = (_connectionCommand ?? "").Trim();
        if (string.IsNullOrEmpty(c))
        {
            ToastService.Info("暂无连接命令");
            return;
        }
        try
        {
            Clipboard.SetText(c);
            ToastService.Success("连接命令已复制");
        }
        catch (Exception ex) { ToastService.Error(ex.Message); }
    }

    private void OpenBrowser()
    {
        var url = _vncWsUrl;
        if (string.IsNullOrEmpty(url))
        {
            ToastService.Info("请先创建 VNC 连接");
            return;
        }
        // ws 无法直接浏览器打开；若是 http(s) 或提示用户
        try
        {
            if (url.StartsWith("ws", StringComparison.OrdinalIgnoreCase))
            {
                ToastService.Info("当前为 WebSocket RFB 地址，请使用内嵌画布；无 WebView2 时需服务端 noVNC 页");
                Clipboard.SetText(url);
                ToastService.Success("已复制 VNC WS 地址");
                return;
            }
            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
        }
        catch (Exception ex) { ToastService.Error(ex.Message); }
    }

    private void OnWsText(string text)
    {
        Dispatcher.Invoke(() => HandleWsMessage(text));
    }

    private void HandleWsMessage(string text)
    {
        Dictionary<string, JsonElement>? obj;
        try
        {
            obj = JsonUtil.Obj(System.Text.Encoding.UTF8.GetBytes(text));
        }
        catch
        {
            AppendLog(text);
            return;
        }
        if (obj == null)
        {
            AppendLog(text);
            return;
        }

        var type = JsonUtil.Str(obj, "type");
        switch (type)
        {
            case "heartbeat":
                _ = _ws.SendJsonAsync(new
                {
                    type = "heartbeat_response",
                    timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                });
                break;
            case "heartbeat_response":
            case "pong":
                break;
            case "error":
            {
                var msg = JsonUtil.Str(obj, "message");
                if (string.IsNullOrEmpty(msg)) msg = "控制台错误";
                _connecting = false;
                _connected = false;
                StopHeartbeat();
                _status.Text = "错误";
                AppendLog("❌ " + msg);
                ToastService.Error(msg);
                break;
            }
            case "vnc_ready":
                HandleVncReady(obj);
                break;
            case "output":
            {
                var line = JsonUtil.Str(obj, "data");
                if (!string.IsNullOrEmpty(line))
                {
                    AppendLog(line);
                    var lower = line.ToLowerInvariant();
                    if (lower.Contains("websockify 启动失败")
                        || lower.Contains("未找到 websockify")
                        || lower.Contains("请在服务端安装 websockify"))
                    {
                        _needsWebsockify = true;
                        if (_installBtn != null) _installBtn.Visibility = Visibility.Visible;
                    }
                }
                break;
            }
            default:
                if (string.IsNullOrEmpty(type))
                    AppendLog(text);
                else
                {
                    var msg = JsonUtil.Str(obj, "message");
                    if (string.IsNullOrEmpty(msg)) msg = JsonUtil.Str(obj, "data");
                    if (!string.IsNullOrEmpty(msg)) AppendLog(msg);
                }
                break;
        }
    }

    private void HandleVncReady(Dictionary<string, JsonElement> obj)
    {
        _connecting = false;
        _connected = true;
        var cmd = JsonUtil.Str(obj, "command");
        if (!string.IsNullOrEmpty(cmd)) _connectionCommand = cmd;

        var port = ParsePort(obj, "websockifyPort");
        if (port is null or <= 0)
        {
            var p = ParsePort(obj, "port");
            if (p is > 1024 and not 5900) port = p;
        }
        _websockifyPort = port;

        var serverVncUrl = JsonUtil.Str(obj, "vncUrl");
        var serverMsg = JsonUtil.Str(obj, "message");

        if ((port is null or 0)
            && (string.IsNullOrEmpty(serverVncUrl) || serverVncUrl.StartsWith("vnc://", StringComparison.OrdinalIgnoreCase)))
        {
            _status.Text = "websockify 未就绪";
            _needsWebsockify = true;
            if (_installBtn != null) _installBtn.Visibility = Visibility.Visible;
            AppendLog("⚠️ 控制通道已建立，但 websockify 未启动，无法加载画面");
            if (!string.IsNullOrEmpty(serverMsg)) AppendLog("   " + serverMsg);
            return;
        }

        _needsWebsockify = false;
        if (_installBtn != null) _installBtn.Visibility = Visibility.Collapsed;
        _status.Text = "即将连接画面…";
        AppendLog("✅ VNC 就绪 · websockify " + (port?.ToString() ?? "?"));
        if (!string.IsNullOrEmpty(serverVncUrl))
            AppendLog("   服务端 vncUrl: " + serverVncUrl);

        var portCap = port;
        var urlCap = serverVncUrl;
        _ = Dispatcher.InvokeAsync(async () =>
        {
            await Task.Delay(800).ConfigureAwait(true);
            if (!_connected) return;
            ApplyVncUrl(portCap, urlCap);
        });
    }

    /// <summary>与 Web console_terminal.ftl / Mac applyVncURL 一致.</summary>
    private void ApplyVncUrl(int? port, string serverVncUrl)
    {
        var baseUrl = AppSession.Normalize(AppSession.Shared.ServerUrl).TrimEnd('/');
        var isHttps = baseUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase);

        if (!isHttps && (serverVncUrl.StartsWith("ws://", StringComparison.OrdinalIgnoreCase)
                         || serverVncUrl.StartsWith("wss://", StringComparison.OrdinalIgnoreCase)))
        {
            var url = serverVncUrl.EndsWith('/') ? serverVncUrl : serverVncUrl + "/";
            SetVncUrl(url, "server");
            return;
        }

        if (isHttps)
        {
            if (port is null or <= 0)
            {
                AppendLog("❌ HTTPS 模式需要 websockifyPort，并配置 Nginx /websockify/");
                _status.Text = "无法连接画面";
                return;
            }
            if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var u) || string.IsNullOrEmpty(u.Host))
            {
                AppendLog("❌ 无法解析服务器地址");
                _status.Text = "无法连接画面";
                return;
            }
            var hostPart = u.IsDefaultPort ? u.Host : $"{u.Host}:{u.Port}";
            var wsUrl = $"wss://{hostPart}/websockify/{port}";
            SetVncUrl(wsUrl, null);
            return;
        }

        if (port is > 0)
        {
            var fromServer = HostFromWsUrl(serverVncUrl);
            if (!string.IsNullOrEmpty(fromServer))
            {
                SetVncUrl($"ws://{fromServer}:{port}/", null);
                return;
            }
            string hostOnly;
            if (Uri.TryCreate(baseUrl, UriKind.Absolute, out var bu) && !string.IsNullOrEmpty(bu.Host))
                hostOnly = bu.Host;
            else
            {
                hostOnly = baseUrl
                    .Replace("https://", "", StringComparison.OrdinalIgnoreCase)
                    .Replace("http://", "", StringComparison.OrdinalIgnoreCase)
                    .Split('/')[0]
                    .Split(':')[0];
            }
            if (hostOnly is "127.0.0.1" or "localhost")
            {
                AppendLog("⚠️ 服务端地址是本机，但 websockify 在远端；请使用服务端下发的 vncUrl");
                if (serverVncUrl.StartsWith("ws", StringComparison.OrdinalIgnoreCase))
                {
                    var fb = serverVncUrl.EndsWith('/') ? serverVncUrl : serverVncUrl + "/";
                    SetVncUrl(fb, "server fallback");
                    return;
                }
            }
            SetVncUrl($"ws://{hostOnly}:{port}/", null);
            AppendLog("   若画面连不上：请放行服务端防火墙该端口，或改用 HTTPS + /websockify/ 反代");
            return;
        }

        if (!string.IsNullOrEmpty(serverVncUrl) && serverVncUrl.StartsWith("ws", StringComparison.OrdinalIgnoreCase))
        {
            var url = serverVncUrl.EndsWith('/') ? serverVncUrl : serverVncUrl + "/";
            SetVncUrl(url, "server");
            return;
        }

        AppendLog("❌ 无法构造 VNC WebSocket 地址（websockify 未返回端口）");
        _status.Text = "无法连接画面";
    }

    private void SetVncUrl(string url, string? tag)
    {
        _vncWsUrl = url;
        _status.Text = "正在连接画面…";
        AppendLog(tag == null ? $"🔗 VNC WS: {url}" : $"🔗 VNC WS ({tag}): {url}");
        ApplyCanvas(url);
    }

    private void ApplyCanvas(string wsUrl)
    {
        if (!_webViewReady || _webView?.CoreWebView2 == null)
        {
            AppendLog("⚠️ 画布未就绪，可稍后重试或复制 WS 地址");
            return;
        }
        if (wsUrl == _lastVncKey) return;
        _lastVncKey = wsUrl;

        _canvasHost.Children.Clear();
        if (!_canvasHost.Children.Contains(_webView))
            _canvasHost.Children.Add(_webView);

        var html = NoVncHtml.Page(wsUrl);
        _webView.NavigateToString(html);
    }

    private void ClearCanvas()
    {
        _lastVncKey = null;
        try
        {
            if (_webView?.CoreWebView2 != null)
            {
                _webView.NavigateToString(
                    """
                    <html><body style="margin:0;background:#0d1117;color:#8b949e;font:13px sans-serif;
                    display:flex;align-items:center;justify-content:center;height:100%">
                    等待 VNC 就绪…</body></html>
                    """);
            }
        }
        catch { /* ignore */ }
        if (_webView == null || !_canvasHost.Children.Contains(_webView))
        {
            _canvasHost.Children.Clear();
            _canvasHost.Children.Add(_canvasPlaceholder);
            _canvasPlaceholder.Text = _needsWebsockify
                ? "websockify 未就绪 — 可点「安装 websockify」"
                : "点击「创建 VNC 连接」";
        }
    }

    private void OnCanvasMessage(string msg)
    {
        AppendLog("🖥 " + msg);
        if (msg.Contains("已连接")) _status.Text = "画面已连接";
        else if (msg.Contains("断开") || msg.Contains("失败")) _status.Text = msg;
    }

    private void StartHeartbeat()
    {
        StopHeartbeat();
        _heartbeat = new DispatcherTimer { Interval = TimeSpan.FromSeconds(25) };
        _heartbeat.Tick += async (_, _) =>
        {
            try
            {
                if (_ws.IsOpen)
                    await _ws.SendJsonAsync(new
                    {
                        type = "ping",
                        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                    }).ConfigureAwait(true);
            }
            catch { /* ignore */ }
        };
        _heartbeat.Start();
    }

    private void StopHeartbeat()
    {
        if (_heartbeat == null) return;
        _heartbeat.Stop();
        _heartbeat = null;
    }

    private void AppendLog(string s)
    {
        var line = (s ?? "").TrimEnd('\r', '\n');
        if (string.IsNullOrEmpty(line)) return;
        _pendingLogs.Add(line);
        if (_logFlushScheduled) return;
        _logFlushScheduled = true;
        Dispatcher.BeginInvoke(() =>
        {
            _logFlushScheduled = false;
            if (_pendingLogs.Count == 0) return;
            foreach (var l in _pendingLogs)
                _log.AppendText(l + "\r\n");
            _pendingLogs.Clear();
            // keep ~400 lines roughly by truncating text if huge
            if (_log.Text.Length > 80_000)
                _log.Text = _log.Text[^40_000..];
            _log.ScrollToEnd();
        }, DispatcherPriority.Background);
    }

    private static int? ParsePort(Dictionary<string, JsonElement> obj, string key)
    {
        if (!obj.TryGetValue(key, out var el)) return null;
        var n = JsonUtil.Int(el, -1);
        return n > 0 ? n : null;
    }

    private static string? HostFromWsUrl(string s)
    {
        if (string.IsNullOrEmpty(s)) return null;
        if (!Uri.TryCreate(s, UriKind.Absolute, out var u) || string.IsNullOrEmpty(u.Host)) return null;
        return u.Host;
    }
}

/// <summary>noVNC inline HTML — 仅协议画布（对齐 Mac InstanceNoVNCHTML）.</summary>
internal static class NoVncHtml
{
    public static string Page(string wsUrl)
    {
        var encoded = JsonSerializer.Serialize(wsUrl);
        return $$"""
            <!DOCTYPE html>
            <html><head>
            <meta charset="utf-8"/>
            <meta name="viewport" content="width=device-width, initial-scale=1"/>
            <style>
              html,body{margin:0;height:100%;background:#000;color:#c9d1d9;font-family:sans-serif;overflow:hidden}
              #screen{position:absolute;inset:0;background:#000}
              #status{position:absolute;left:12px;bottom:10px;font-size:12px;opacity:.85;z-index:2;
                background:rgba(0,0,0,.55);padding:4px 8px;border-radius:6px;pointer-events:none}
            </style>
            </head>
            <body>
              <div id="screen"></div>
              <div id="status">正在加载 noVNC…</div>
              <script type="module">
                const wsUrl = {{encoded}};
                const el = document.getElementById('screen');
                const st = document.getElementById('status');
                function post(msg) {
                  try {
                    if (window.chrome && window.chrome.webview)
                      window.chrome.webview.postMessage(String(msg));
                  } catch (e) {}
                  st.textContent = msg;
                }
                try {
                  const mod = await import('https://cdn.jsdelivr.net/npm/@novnc/novnc@1.4.0/lib/rfb.js');
                  const RFB = mod.default;
                  post('正在连接 VNC…');
                  const rfb = new RFB(el, wsUrl, {
                    shared: true,
                    wsProtocols: ['binary']
                  });
                  rfb.scaleViewport = true;
                  rfb.resizeSession = false;
                  rfb.qualityLevel = 9;
                  rfb.compressionLevel = 0;
                  rfb.addEventListener('connect', () => post('VNC 画面已连接'));
                  rfb.addEventListener('disconnect', (e) => {
                    post(e.detail && e.detail.clean ? 'VNC 已断开' : 'VNC 异常断开');
                  });
                  rfb.addEventListener('securityfailure', (e) => {
                    post('VNC 安全校验失败: ' + (e.detail && e.detail.status || ''));
                  });
                  rfb.addEventListener('credentialsrequired', () => {
                    post('需要 VNC 密码');
                    const p = prompt('VNC 密码');
                    if (p != null) rfb.sendCredentials({ password: p });
                  });
                  window.__rfb = rfb;
                } catch (e) {
                  post('noVNC 加载失败: ' + e);
                }
              </script>
            </body></html>
            """;
    }
}
