using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Threading;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Dashboard;

/// <summary>系统监控 — 对齐 Mac DashboardView（统计 5 卡 + 主机资源）.</summary>
public sealed class DashboardView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DispatcherTimer _metricsTimer = new() { Interval = TimeSpan.FromSeconds(20) };
    private readonly DispatcherTimer _statsTimer = new() { Interval = TimeSpan.FromSeconds(60) };

    private readonly TextBlock _apiCalls = BigVal();
    private readonly TextBlock _boots = BigVal();
    private readonly TextBlock _attempts = BigVal();
    private readonly TextBlock _success = BigVal();
    private readonly TextBlock _fails = BigVal();
    private readonly TextBlock _successRate = BigVal();

    private readonly TextBlock _cpu = BigVal();
    private readonly TextBlock _mem = BigVal();
    private readonly TextBlock _disk = BigVal();
    private readonly TextBlock _net = BigVal();
    private readonly TextBlock _host = BigVal();
    private readonly TextBlock _uptime = BigVal();
    private readonly TextBlock _updated = new()
    {
        FontSize = 12,
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
    };

    public DashboardView()
    {
        _scaffold.Title = "系统监控";
        _scaffold.Subtitle = "仪表板统计 · 主机资源";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新", async (_, _) => await RefreshAllAsync()),
            _updated);

        var stats = new UniformGrid { Columns = 6, Margin = new Thickness(0, 0, 0, 8) };
        stats.Children.Add(Card("总 API 数", _apiCalls, "#3b82f6"));
        stats.Children.Add(Card("Boot 实例", _boots, "#22c55e"));
        stats.Children.Add(Card("抢机次数", _attempts, "#f97316"));
        stats.Children.Add(Card("抢机成功", _success, "#06b6d4"));
        stats.Children.Add(Card("抢机失败", _fails, "#ef4444"));
        stats.Children.Add(Card("成功率", _successRate, "#a855f7"));

        var mon = new UniformGrid { Columns = 3 };
        mon.Children.Add(Card("CPU", _cpu, "#3b82f6"));
        mon.Children.Add(Card("内存", _mem, "#22c55e"));
        mon.Children.Add(Card("磁盘", _disk, "#f59e0b"));
        mon.Children.Add(Card("网络", _net, "#06b6d4"));
        mon.Children.Add(Card("主机", _host, "#8b5cf6"));
        mon.Children.Add(Card("运行时间", _uptime, "#64748b"));

        var stack = new StackPanel { Margin = new Thickness(16) };
        stack.Children.Add(SectionTitle("业务统计"));
        stack.Children.Add(stats);
        stack.Children.Add(SectionTitle("主机监控"));
        stack.Children.Add(mon);

        _scaffold.SetBody(new ScrollViewer
        {
            Content = stack,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        });
        Content = _scaffold;

        _metricsTimer.Tick += async (_, _) => await RefreshMetricsAsync();
        _statsTimer.Tick += async (_, _) => await RefreshStatsAsync();
        Loaded += async (_, _) =>
        {
            await RefreshAllAsync();
            _metricsTimer.Start();
            _statsTimer.Start();
        };
        Unloaded += (_, _) =>
        {
            _metricsTimer.Stop();
            _statsTimer.Stop();
        };
    }

    private static TextBlock BigVal() => new()
    {
        FontSize = 20,
        FontWeight = FontWeights.SemiBold,
        Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush"),
        Text = "—",
        TextWrapping = TextWrapping.Wrap
    };

    private static TextBlock SectionTitle(string t) => new()
    {
        Text = t,
        FontSize = 13,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, 8, 0, 10),
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
    };

    private static Border Card(string title, TextBlock value, string accentHex)
    {
        var color = (Color)ColorConverter.ConvertFromString(accentHex)!;
        var sp = new StackPanel { Margin = new Thickness(14) };
        sp.Children.Add(new Border
        {
            Width = 8,
            Height = 8,
            CornerRadius = new CornerRadius(4),
            Background = new SolidColorBrush(color),
            Margin = new Thickness(0, 0, 0, 8),
            HorizontalAlignment = HorizontalAlignment.Left
        });
        sp.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 11,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
        });
        sp.Children.Add(value);
        return new Border
        {
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush"),
            BorderBrush = (Brush)Application.Current.FindResource("AppBorderBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14),
            Margin = new Thickness(0, 0, 12, 12),
            MinHeight = 110,
            Child = sp
        };
    }

    private async Task RefreshAllAsync()
    {
        _scaffold.SetLoading(true);
        _scaffold.SetError(null);
        await Task.WhenAll(RefreshStatsAsync(), RefreshMetricsAsync()).ConfigureAwait(true);
        _scaffold.SetLoading(false);
    }

    private async Task RefreshStatsAsync()
    {
        try
        {
            var raw = await _api.GetJsonAsync("/boot/dashboard-stats").ConfigureAwait(true);
            var s = DashboardFormat.ExtractData<DashboardStats>(raw);
            _apiCalls.Text = s.TotalApiCalls.ToString("N0");
            _boots.Text = s.TotalBootInstances.ToString("N0");
            _attempts.Text = s.TotalAttempts.ToString("N0");
            _success.Text = s.SuccessfulAttempts.ToString("N0");
            _fails.Text = s.FailCounts.ToString("N0");
            _successRate.Text = s.SuccessRate + "%";
        }
        catch (Exception ex)
        {
            _scaffold.SetError(ex is ApiError ae ? ae.Message : ex.Message);
        }
    }

    private async Task RefreshMetricsAsync()
    {
        try
        {
            byte[] raw;
            try { raw = await _api.GetJsonAsync("/monitor/stats").ConfigureAwait(true); }
            catch { raw = await _api.GetJsonAsync("/boot/stats").ConfigureAwait(true); }

            var m = DashboardFormat.ExtractData<SystemMetrics>(raw);
            _cpu.Text = $"{m.CpuUsage:0.0}%\n{m.CpuModel}";
            _mem.Text = $"{m.MemoryUsage:0.0}%\n{DashboardFormat.MemoryMb(m.UsedMemory)} / {DashboardFormat.MemoryMb(m.TotalMemory)}";
            _disk.Text = $"{m.DiskUsage:0.0}%";
            _net.Text = $"↑ {DashboardFormat.Speed(m.UploadSpeed)}\n↓ {DashboardFormat.Speed(m.DownloadSpeed)}";
            _host.Text = string.IsNullOrEmpty(m.Hostname) ? m.OsName : $"{m.Hostname}\n{m.OsName}";
            _uptime.Text = DashboardFormat.Uptime(m.SystemUptime);
            _updated.Text = "更新 " + (string.IsNullOrEmpty(m.Timestamp)
                ? DateTime.Now.ToString("HH:mm:ss")
                : m.Timestamp);
            _scaffold.SetError(null);
        }
        catch (Exception ex)
        {
            _scaffold.SetError(ex is ApiError ae ? ae.Message : ex.Message);
        }
    }
}
