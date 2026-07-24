using System.Windows.Controls;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.EdgeOne;

public sealed class EoRow
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Type { get; set; } = "";
    public string Value { get; set; } = "";
    public string Status { get; set; } = "";
}

public sealed class EdgeOneView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();

    public EdgeOneView()
    {
        _scaffold.Title = "EdgeOne";
        _scaffold.Subtitle = "腾讯云 EdgeOne DNS / 站点";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));
        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(EoRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("类型", nameof(EoRow.Type), 80));
        _grid.Columns.Add(ListPageHelper.Col("值", nameof(EoRow.Value), 180));
        _grid.Columns.Add(ListPageHelper.Col("状态", nameof(EoRow.Status), 80));
        Content = ListPageHelper.Wrap(_scaffold, ListPageHelper.TopBar(), _grid);
        Loaded += async (_, _) => await LoadAsync();
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            byte[] raw;
            try
            {
                raw = await _api.GetJsonAsync("/dns/edgeone/api/zones").ConfigureAwait(true);
            }
            catch
            {
                raw = await _api.GetJsonAsync("/dns/edgeone/api/domains").ConfigureAwait(true);
            }
            var (rows, _, _, _) = JsonPage.Parse(raw, ["content", "list", "data", "records", "zones", "domains"]);
            _grid.ItemsSource = rows.Select(m => new EoRow
            {
                Id = JsonPage.Pick(m, "id", "zoneId", "domainId"),
                Name = JsonPage.Pick(m, "name", "domain", "zoneName"),
                Type = JsonPage.Pick(m, "type", "recordType"),
                Value = JsonPage.Pick(m, "value", "content", "recordValue"),
                Status = JsonPage.Pick(m, "status", "state")
            }).ToList();
        });
}
