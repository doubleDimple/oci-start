using System.Diagnostics;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.SpeedTest;

public sealed class SpeedRow
{
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string Latency { get; set; } = "—";
    public string Endpoint { get; set; } = "";
}

public sealed class SpeedTestView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly TextBlock _ipText = new()
    {
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(0, 0, 12, 0)
    };
    private List<SpeedRow> _rows = [];

    public SpeedTestView()
    {
        _scaffold.Title = "延迟测试";
        _scaffold.Subtitle = "客户端到各区域端点延迟";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("重新测试", async (_, _) => await RunAsync()));

        _grid.Columns.Add(ListPageHelper.Col("代码", nameof(SpeedRow.Code), 100));
        _grid.Columns.Add(ListPageHelper.Col("区域", nameof(SpeedRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("延迟", nameof(SpeedRow.Latency), 100));
        _grid.Columns.Add(ListPageHelper.Col("端点", nameof(SpeedRow.Endpoint), 220));

        var bar = ListPageHelper.TopBar(_ipText);
        Content = ListPageHelper.Wrap(_scaffold, bar, _grid);
        Loaded += async (_, _) => await RunAsync();
    }

    private async Task RunAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            try
            {
                var ip = await _api.GetStringAsync("/api/getCurrentIp").ConfigureAwait(true);
                _ipText.Text = "本机 IP：" + ip.Trim();
            }
            catch
            {
                _ipText.Text = "本机 IP：未知";
            }

            byte[] raw;
            try
            {
                raw = await _api.GetJsonAsync("/api/regions").ConfigureAwait(true);
            }
            catch
            {
                raw = await _api.GetJsonAsync("/delayTest/regions").ConfigureAwait(true);
            }

            var (dicts, _, _, _) = JsonPage.Parse(raw);
            _rows = dicts.Select(m => new SpeedRow
            {
                Code = JsonPage.Pick(m, "code", "region", "regionCode"),
                Name = JsonPage.Pick(m, "name", "regionName", "label"),
                Endpoint = JsonPage.Pick(m, "url", "endpoint", "testUrl", "host")
            }).Where(r => !string.IsNullOrEmpty(r.Endpoint) || !string.IsNullOrEmpty(r.Code)).ToList();

            _grid.ItemsSource = null;
            _grid.ItemsSource = _rows;

            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var tasks = _rows.Select(async row =>
            {
                var url = row.Endpoint;
                if (string.IsNullOrWhiteSpace(url))
                {
                    row.Latency = "无端点";
                    return;
                }
                if (!url.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                    url = "https://" + url.TrimStart('/');
                var sw = Stopwatch.StartNew();
                try
                {
                    using var req = new HttpRequestMessage(HttpMethod.Head, url);
                    using var resp = await http.SendAsync(req).ConfigureAwait(false);
                    sw.Stop();
                    row.Latency = sw.ElapsedMilliseconds + " ms";
                }
                catch
                {
                    sw.Stop();
                    row.Latency = "超时";
                }
            });
            await Task.WhenAll(tasks).ConfigureAwait(true);
            _grid.ItemsSource = null;
            _grid.ItemsSource = _rows.OrderBy(r =>
            {
                if (r.Latency.EndsWith(" ms") && int.TryParse(r.Latency.Replace(" ms", ""), out var ms))
                    return ms;
                return int.MaxValue;
            }).ToList();
        });
}
