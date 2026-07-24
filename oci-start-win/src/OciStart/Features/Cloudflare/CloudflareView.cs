using System.Windows.Controls;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Cloudflare;

public sealed class CfRecordRow
{
    public string Id { get; set; } = "";
    public string Type { get; set; } = "";
    public string Name { get; set; } = "";
    public string Content { get; set; } = "";
    public string Ttl { get; set; } = "";
    public string Proxied { get; set; } = "";
}

public sealed class CloudflareView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly ComboBox _zoneBox = new() { MinWidth = 260, Padding = new System.Windows.Thickness(8, 6, 8, 6) };
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private List<(string id, string name)> _zones = [];
    private int _page = 1;

    public CloudflareView()
    {
        _scaffold.Title = "Cloudflare";
        _scaffold.Subtitle = "DNS 记录管理";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新 Zone", async (_, _) => await LoadZonesAsync()),
            FormFieldFactory.Secondary("上一页", async (_, _) => { if (_page > 1) { _page--; await LoadRecordsAsync(); } }),
            FormFieldFactory.Secondary("下一页", async (_, _) => { _page++; await LoadRecordsAsync(); }));

        _grid.Columns.Add(ListPageHelper.Col("类型", nameof(CfRecordRow.Type), 70));
        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(CfRecordRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("内容", nameof(CfRecordRow.Content), 180));
        _grid.Columns.Add(ListPageHelper.Col("TTL", nameof(CfRecordRow.Ttl), 70));
        _grid.Columns.Add(ListPageHelper.Col("代理", nameof(CfRecordRow.Proxied), 60));

        var bar = ListPageHelper.TopBar(
            new TextBlock { Text = "Zone", VerticalAlignment = System.Windows.VerticalAlignment.Center, Margin = new System.Windows.Thickness(0, 0, 8, 0) },
            _zoneBox,
            FormFieldFactory.Primary("加载记录", async (_, _) => { _page = 1; await LoadRecordsAsync(); }));
        Content = ListPageHelper.Wrap(_scaffold, bar, _grid);
        Loaded += async (_, _) => await LoadZonesAsync();
    }

    private async Task LoadZonesAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/dns/cloudflare/api/zones").ConfigureAwait(true);
            var (rows, _, _, _) = JsonPage.Parse(raw, ["content", "list", "result", "zones", "data"]);
            _zones = rows.Select(m => (
                JsonPage.Pick(m, "id", "zoneId"),
                JsonPage.Pick(m, "name", "zoneName")
            )).Where(z => !string.IsNullOrEmpty(z.Item1)).ToList();
            _zoneBox.ItemsSource = _zones.Select(z => string.IsNullOrEmpty(z.name) ? z.id : $"{z.name}").ToList();
            if (_zoneBox.Items.Count > 0)
            {
                _zoneBox.SelectedIndex = 0;
                await LoadRecordsAsync();
            }
        });

    private async Task LoadRecordsAsync()
    {
        if (_zoneBox.SelectedIndex < 0 || _zoneBox.SelectedIndex >= _zones.Count)
        {
            ToastService.Info("请选择 Zone");
            return;
        }
        var zid = _zones[_zoneBox.SelectedIndex].id;
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync($"/dns/cloudflare/api/zones/{zid}/records", new Dictionary<string, string>
            {
                ["page"] = Math.Max(1, _page).ToString(),
                ["size"] = "20"
            }).ConfigureAwait(true);
            var (rows, _, _, _) = JsonPage.Parse(raw, ["content", "list", "result", "records", "data"]);
            _grid.ItemsSource = rows.Select(m => new CfRecordRow
            {
                Id = JsonPage.Pick(m, "id"),
                Type = JsonPage.Pick(m, "type"),
                Name = JsonPage.Pick(m, "name"),
                Content = JsonPage.Pick(m, "content"),
                Ttl = JsonPage.Pick(m, "ttl"),
                Proxied = JsonPage.Pick(m, "proxied")
            }).ToList();
        });
    }
}
