using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Regions;

public sealed class RegionRow
{
    public string Region { get; set; } = "";
    public string Name { get; set; } = "";
    public string Open { get; set; } = "";
    public string OpenCount { get; set; } = "";
    public string Monthly { get; set; } = "";
    public string Arch { get; set; } = "";
    public string OpenTime { get; set; } = "";
    public string LastNotify { get; set; } = "";
}

/// <summary>区域订阅 — 对齐 Mac：/resource/arm-data + /resource/my-regions.</summary>
public sealed class RegionsView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly TextBox _search = FormFieldFactory.TextField(watermark: "搜索区域代码/名称");
    private readonly TextBlock _summary = new()
    {
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(12, 0, 0, 0)
    };
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMinutes(5) };
    private List<RegionRow> _all = [];

    public RegionsView()
    {
        _scaffold.Title = "区域订阅";
        _scaffold.Subtitle = "ARM 区域开放记录";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()),
            _summary);

        _grid.Columns.Add(ListPageHelper.Col("区域", nameof(RegionRow.Region), 120));
        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(RegionRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("开放", nameof(RegionRow.Open), 60));
        _grid.Columns.Add(ListPageHelper.Col("次数", nameof(RegionRow.OpenCount), 70));
        _grid.Columns.Add(ListPageHelper.Col("本月", nameof(RegionRow.Monthly), 70));
        _grid.Columns.Add(ListPageHelper.Col("架构", nameof(RegionRow.Arch), 80));
        _grid.Columns.Add(ListPageHelper.Col("开放时间", nameof(RegionRow.OpenTime), 150));
        _grid.Columns.Add(ListPageHelper.Col("最近通知", nameof(RegionRow.LastNotify), 150));

        var bar = ListPageHelper.TopBar(
            _search,
            FormFieldFactory.Primary("筛选", (_, _) => ApplyFilter()),
            FormFieldFactory.Secondary("仅已开放", (_, _) =>
            {
                _grid.ItemsSource = _all.Where(r => r.Open == "是").ToList();
            }));
        Content = ListPageHelper.Wrap(_scaffold, bar, _grid);

        _timer.Tick += async (_, _) => await LoadAsync();
        Loaded += async (_, _) =>
        {
            await LoadAsync();
            _timer.Start();
        };
        Unloaded += (_, _) => _timer.Stop();
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            Dictionary<string, string> map = new(StringComparer.OrdinalIgnoreCase);
            var openRows = new List<RegionRow>();

            try
            {
                var armRaw = await _api.GetJsonAsync("/resource/arm-data").ConfigureAwait(true);
                var arm = UnwrapData(armRaw);
                if (arm.TryGetValue("regionMap", out var rm) && rm.ValueKind == System.Text.Json.JsonValueKind.Object)
                {
                    foreach (var p in rm.EnumerateObject())
                        map[p.Name] = p.Value.GetString() ?? p.Name;
                }
                if (arm.TryGetValue("armRecords", out var arr) && arr.ValueKind == System.Text.Json.JsonValueKind.Array)
                {
                    foreach (var el in arr.EnumerateArray())
                    {
                        if (el.ValueKind != System.Text.Json.JsonValueKind.Object) continue;
                        var m = JsonUtil.ToDict(el);
                        var code = JsonUtil.Str(m, "region");
                        var count = JsonUtil.Int(m, "openCount");
                        openRows.Add(new RegionRow
                        {
                            Region = code,
                            Name = map.TryGetValue(code, out var n) ? n : code,
                            Open = count > 0 ? "是" : "否",
                            OpenCount = count.ToString(),
                            Monthly = JsonUtil.Int(m, "monthlyOpenCount").ToString(),
                            Arch = string.IsNullOrEmpty(JsonUtil.Str(m, "architectureType"))
                                ? "--"
                                : JsonUtil.Str(m, "architectureType"),
                            OpenTime = JsonUtil.Str(m, "openTime"),
                            LastNotify = JsonUtil.Str(m, "lastNotifyTime")
                        });
                    }
                }
            }
            catch
            {
                // fallback
                try
                {
                    var raw = await _api.GetJsonAsync("/resource/list/json").ConfigureAwait(true);
                    var (rows, _, _, _) = JsonPage.Parse(raw);
                    openRows = rows.Select(m => new RegionRow
                    {
                        Region = JsonPage.Pick(m, "region", "regionCode", "code"),
                        Name = JsonPage.Pick(m, "regionName", "name"),
                        Open = "—",
                        OpenCount = JsonPage.Pick(m, "openCount", "count"),
                        OpenTime = JsonPage.Pick(m, "openTime", "updateTime")
                    }).ToList();
                }
                catch { /* ignore */ }
            }

            // merge my-regions marker
            try
            {
                var myRaw = await _api.GetJsonAsync("/resource/my-regions").ConfigureAwait(true);
                var my = UnwrapData(myRaw);
                if (my.TryGetValue("hasRecords", out var has) && has.ValueKind == System.Text.Json.JsonValueKind.Array)
                {
                    var mine = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    foreach (var el in has.EnumerateArray())
                    {
                        if (el.ValueKind == System.Text.Json.JsonValueKind.Object)
                        {
                            var m = JsonUtil.ToDict(el);
                            var c = JsonUtil.Str(m, "region");
                            if (!string.IsNullOrEmpty(c)) mine.Add(c);
                        }
                        else if (el.ValueKind == System.Text.Json.JsonValueKind.String)
                        {
                            mine.Add(el.GetString() ?? "");
                        }
                    }
                    foreach (var r in openRows)
                    {
                        if (mine.Contains(r.Region) && !r.Name.Contains("·我的"))
                            r.Name += " ·我的";
                    }
                }
            }
            catch { /* optional */ }

            _all = openRows.OrderByDescending(r => r.Open == "是").ThenBy(r => r.Region).ToList();
            ApplyFilter();
            var openN = _all.Count(r => r.Open == "是");
            _summary.Text = $"共 {_all.Count} · 已开放 {openN} · {DateTime.Now:HH:mm:ss}";
        });

    private void ApplyFilter()
    {
        var q = (_search.Text ?? "").Trim();
        IEnumerable<RegionRow> list = _all;
        if (q.Length > 0)
            list = list.Where(r =>
                r.Region.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                r.Name.Contains(q, StringComparison.OrdinalIgnoreCase));
        _grid.ItemsSource = list.ToList();
    }

    private static Dictionary<string, System.Text.Json.JsonElement> UnwrapData(byte[] raw)
    {
        var root = JsonUtil.Obj(raw) ?? new();
        if (root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
            return JsonUtil.ToDict(data);
        return root;
    }
}
