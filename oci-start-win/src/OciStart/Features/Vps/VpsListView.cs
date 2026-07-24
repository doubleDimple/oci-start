using System.Windows.Controls;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;
using OciStart.Features.Instances;

namespace OciStart.Features.Vps;

public sealed class VpsListView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly InstancesService _instances = new();
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();

    public VpsListView()
    {
        _scaffold.Title = "监控看板";
        _scaffold.Subtitle = "VPS / 实例监控与 Ping";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));

        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(InstanceItem.DisplayName), star: true));
        _grid.Columns.Add(ListPageHelper.Col("状态", nameof(InstanceItem.StateLabel), 80));
        _grid.Columns.Add(ListPageHelper.Col("公网 IP", nameof(InstanceItem.PublicIps), 130));
        _grid.Columns.Add(ListPageHelper.Col("规格", nameof(InstanceItem.CpuAndMem), 80));
        _grid.Columns.Add(ListPageHelper.Col("区域", nameof(InstanceItem.RegionName), 120));

        var bar = ListPageHelper.TopBar(
            FormFieldFactory.Primary("手动 Ping", async (_, _) => await ActionAsync("/vps/instances/ping", "Ping 已下发")),
            FormFieldFactory.Secondary("开启自动 Ping", async (_, _) => await ActionAsync("/vps/instances/enablePing", "已开启")),
            FormFieldFactory.Secondary("停止自动 Ping", async (_, _) => await ActionAsync("/vps/instances/disablePing", "已停止")));
        Content = ListPageHelper.Wrap(_scaffold, bar, _grid);
        Loaded += async (_, _) => await LoadAsync();
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var resp = await _instances.ListAsync(0, 1000).ConfigureAwait(true);
            _grid.ItemsSource = resp.Content;
        });

    private async Task ActionAsync(string path, string okMsg)
    {
        try
        {
            var raw = await _api.PostJsonAsync(path, new { }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, okMsg);
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
    }
}
