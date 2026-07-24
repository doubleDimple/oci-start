using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.SystemLogs;

/// <summary>系统日志 — 历史 + SSE isBootLog=false（对齐 Mac）.</summary>
public sealed class SystemLogsView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly TextBox _log = new()
    {
        IsReadOnly = true,
        AcceptsReturn = true,
        TextWrapping = TextWrapping.NoWrap,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
        FontFamily = new FontFamily("Consolas, Cascadia Mono"),
        FontSize = 12,
        Background = (Brush)Application.Current.FindResource("CardBgBrush"),
        Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush"),
        Margin = new Thickness(16)
    };
    private readonly TextBlock _status = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Text = "历史"
    };
    private CancellationTokenSource? _sseCts;

    public SystemLogsView()
    {
        _scaffold.Title = "系统日志";
        _scaffold.Subtitle = "应用运行日志 · 历史 + 实时";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新历史", async (_, _) => await LoadHistoryAsync()),
            FormFieldFactory.Primary("实时流", async (_, _) => await StartSseAsync()),
            FormFieldFactory.Secondary("断开", (_, _) => StopSse()),
            FormFieldFactory.Secondary("清空", async (_, _) =>
            {
                if (MessageBox.Show("确认清空界面日志？", "清空", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
                    _log.Clear();
            }),
            _status);
        _scaffold.SetBody(_log);
        Content = _scaffold;
        Loaded += async (_, _) => await LoadHistoryAsync();
        Unloaded += (_, _) => StopSse();
    }

    private async Task LoadHistoryAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/system/logs/json", new Dictionary<string, string>
            {
                ["lines"] = "300"
            }).ConfigureAwait(true);
            _log.Text = string.Join(Environment.NewLine, Parse(raw)) + Environment.NewLine;
            _log.CaretIndex = _log.Text.Length;
            _log.ScrollToEnd();
            _status.Text = "历史 · " + DateTime.Now.ToString("HH:mm:ss");
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
                               new Dictionary<string, string> { ["isBootLog"] = "false" }, token)
                           .ConfigureAwait(true))
            {
                _log.AppendText(line + Environment.NewLine);
                _log.ScrollToEnd();
                _status.Text = "实时 · " + DateTime.Now.ToString("HH:mm:ss");
            }
        }
        catch (OperationCanceledException) { _status.Text = "已断开"; }
        catch (Exception ex)
        {
            _status.Text = "SSE 失败";
            ToastService.Error(ex.Message);
        }
    }

    private void StopSse()
    {
        try { _sseCts?.Cancel(); } catch { /* ignore */ }
        _sseCts?.Dispose();
        _sseCts = null;
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
