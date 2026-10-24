using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Linq;
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
    private readonly TextBox _searchBox;
    private List<InstanceItem> _allItems = new();

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

        _searchBox = FormFieldFactory.TextField(watermark: "搜索 IP、名称、区域…");
        _searchBox.Width = 240;
        _searchBox.TextChanged += (_, _) => FilterItems();

        var bar = ListPageHelper.TopBar(
            _searchBox,
            FormFieldFactory.Primary("网络质量", (_, _) => OpenQualityModal()),
            FormFieldFactory.Secondary("手动 Ping", async (_, _) => await ActionAsync("/vps/instances/ping", "Ping 已下发")),
            FormFieldFactory.Secondary("开启自动 Ping", async (_, _) => await ActionAsync("/vps/instances/enablePing", "已开启")),
            FormFieldFactory.Secondary("停止自动 Ping", async (_, _) => await ActionAsync("/vps/instances/disablePing", "已停止")));
        Content = ListPageHelper.Wrap(_scaffold, bar, _grid);
        Loaded += async (_, _) => await LoadAsync();
    }

    private void FilterItems()
    {
        var q = _searchBox.Text.Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(q))
        {
            _grid.ItemsSource = _allItems;
        }
        else
        {
            _grid.ItemsSource = _allItems.Where(it =>
                (it.DisplayName ?? "").ToLowerInvariant().Contains(q) ||
                (it.PublicIps ?? "").ToLowerInvariant().Contains(q) ||
                (it.RegionName ?? "").ToLowerInvariant().Contains(q) ||
                (it.StateLabel ?? "").ToLowerInvariant().Contains(q) ||
                (it.CpuAndMem ?? "").ToLowerInvariant().Contains(q)).ToList();
        }
    }

    private void OpenQualityModal()
    {
        var win = new Window
        {
            Title = "网络质量管理",
            Width = 920,
            Height = 650,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null) win.Owner = Application.Current.MainWindow;
        win.Content = new IpQuality.IpQualityView();
        win.ShowDialog();
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var resp = await _instances.ListAsync(0, 1000).ConfigureAwait(true);
            _allItems = resp.Content.ToList();
            FilterItems();
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
