using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.OpenLogs;

/// <summary>开机日志 — 历史 JSON + SSE（isBootLog=true，对齐 Mac OpenLogs）.</summary>
public sealed class OpenLogsView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly TextBox _log = CreateLogBox();
    private readonly TextBlock _status = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(8, 0, 0, 0),
        Text = "未连接"
    };
    private CancellationTokenSource? _sseCts;
    private bool _follow = true;

    public OpenLogsView()
    {
        _scaffold.Title = "开机日志";
        _scaffold.Subtitle = "抢机任务运行日志 · 历史 + 实时";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新历史", async (_, _) => await LoadHistoryAsync()),
            FormFieldFactory.Primary("连接实时", async (_, _) => await StartSseAsync()),
            FormFieldFactory.Secondary("断开", (_, _) => StopSse()),
            FormFieldFactory.Secondary("清空", (_, _) => _log.Clear()),
            _status);

        _scaffold.SetBody(_log);
        Content = _scaffold;
        Loaded += async (_, _) => await LoadHistoryAsync();
        Unloaded += (_, _) => StopSse();
    }

    private static TextBox CreateLogBox() => new()
    {
        IsReadOnly = true,
        AcceptsReturn = true,
        TextWrapping = TextWrapping.NoWrap,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
        FontFamily = new FontFamily("Consolas, Cascadia Mono"),
        FontSize = 12,
        Background = Brushes.Black,
        Foreground = new SolidColorBrush(Color.FromRgb(0xC8, 0xC8, 0xC8)),
        Margin = new Thickness(16)
    };

    private async Task LoadHistoryAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/system/openLogs/json", new Dictionary<string, string>
            {
                ["lines"] = "400"
            }).ConfigureAwait(true);
            var text = string.Join(Environment.NewLine, Parse(raw));
            _log.Text = text + Environment.NewLine;
            if (_follow) { _log.CaretIndex = _log.Text.Length; _log.ScrollToEnd(); }
            _status.Text = "历史已加载";
        });

    private async Task StartSseAsync()
    {
        StopSse();
        _sseCts = new CancellationTokenSource();
        _status.Text = "实时连接中…";
        var token = _sseCts.Token;
        try
        {
            await foreach (var line in _api.StreamSseAsync("/system/streamLogs",
                               new Dictionary<string, string> { ["isBootLog"] = "true" }, token)
                           .ConfigureAwait(true))
            {
                Append(line);
                _status.Text = "实时 · " + DateTime.Now.ToString("HH:mm:ss");
            }
        }
        catch (OperationCanceledException)
        {
            _status.Text = "已断开";
        }
        catch (Exception ex)
        {
            _status.Text = "SSE 失败: " + ex.Message;
            Append("[SSE] " + ex.Message);
        }
    }

    private void StopSse()
    {
        try { _sseCts?.Cancel(); } catch { /* ignore */ }
        _sseCts?.Dispose();
        _sseCts = null;
        if (_status.Text.StartsWith("实时"))
            _status.Text = "已断开";
    }

    private void Append(string s)
    {
        _log.AppendText(s + Environment.NewLine);
        if (_follow)
        {
            _log.CaretIndex = _log.Text.Length;
            _log.ScrollToEnd();
        }
    }

    private static IEnumerable<string> Parse(byte[] raw)
    {
        using var doc = JsonDocument.Parse(raw);
        var root = doc.RootElement;
        if (root.ValueKind == JsonValueKind.Array)
        {
            foreach (var el in root.EnumerateArray())
                if (el.ValueKind == JsonValueKind.String) yield return el.GetString() ?? "";
            yield break;
        }
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("lines", out var lines)
            && lines.ValueKind == JsonValueKind.Array)
        {
            foreach (var el in lines.EnumerateArray())
                if (el.ValueKind == JsonValueKind.String) yield return el.GetString() ?? "";
            yield break;
        }
        yield return Encoding.UTF8.GetString(raw);
    }
}
