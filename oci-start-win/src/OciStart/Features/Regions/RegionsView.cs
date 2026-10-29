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
    public bool IsLinked { get; set; }
    public string Ownership => IsLinked ? "已关联账号" : "未关联账号";
}

/// <summary>OCI 区域与本地账号关联信息。</summary>
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
        _scaffold.Subtitle = "";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()),
            _summary);

        _grid.Columns.Add(ListPageHelper.Col("区域", nameof(RegionRow.Region), 120));
        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(RegionRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("账号关联", nameof(RegionRow.Ownership), 140));

        var bar = ListPageHelper.TopBar(
            _search,
            FormFieldFactory.Primary("筛选", (_, _) => ApplyFilter()),
            FormFieldFactory.Secondary("仅已关联", (_, _) =>
            {
                _grid.ItemsSource = _all.Where(r => r.IsLinked).ToList();
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
            var raw = await _api.GetJsonAsync("/resource/my-regions").ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "账号关联区域加载失败");
            var data = UnwrapData(raw);
            var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (data.TryGetValue("regionMap", out var regionMap) && regionMap.ValueKind == System.Text.Json.JsonValueKind.Object)
                foreach (var entry in regionMap.EnumerateObject()) names[entry.Name] = entry.Value.GetString() ?? entry.Name;
            if (!data.TryGetValue("hasRecords", out var records) || records.ValueKind != System.Text.Json.JsonValueKind.Array)
                throw new InvalidOperationException("账号关联区域数据格式无效");
            var owned = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var record in records.EnumerateArray())
            {
                var code = record.ValueKind == System.Text.Json.JsonValueKind.Object
                    ? JsonUtil.Str(JsonUtil.ToDict(record), "region") : "";
                if (string.IsNullOrWhiteSpace(code)) throw new InvalidOperationException("区域代码无效");
                owned.Add(code.Trim());
            }
            _all = names.Keys.Union(owned, StringComparer.OrdinalIgnoreCase).OrderBy(code => code).Select(code => new RegionRow
            {
                Region = code,
                Name = names.TryGetValue(code, out var name) ? name : code,
                IsLinked = owned.Contains(code)
            }).ToList();
            ApplyFilter();
            _summary.Text = $"共 {_all.Count} · 已关联 {owned.Count} · {DateTime.Now:HH:mm:ss}";
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
