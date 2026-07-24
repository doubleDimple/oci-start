using System.Windows;
using System.Windows.Controls;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Instances;

public sealed class VnicRow
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string PrivateIp { get; set; } = "";
    public string PublicIp { get; set; } = "";
    public string Subnet { get; set; } = "";
    public string Primary { get; set; } = "";
}

/// <summary>网络管理整页（对齐 Mac InstanceVnicView）.</summary>
public sealed class InstanceVnicView : UserControl
{
    private readonly InstanceItem _item;
    private readonly Action _onBack;
    private readonly InstancesService _service = new();
    private readonly PageScaffold _scaffold = new();
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();

    public InstanceVnicView(InstanceItem item, Action onBack)
    {
        _item = item;
        _onBack = onBack;
        _scaffold.Title = "网络管理 — " + (string.IsNullOrEmpty(item.DisplayName) ? "实例" : item.DisplayName);
        _scaffold.Subtitle = "VNIC 列表";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("返回列表", (_, _) => _onBack()),
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));

        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(VnicRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("私网 IP", nameof(VnicRow.PrivateIp), 130));
        _grid.Columns.Add(ListPageHelper.Col("公网 IP", nameof(VnicRow.PublicIp), 130));
        _grid.Columns.Add(ListPageHelper.Col("子网", nameof(VnicRow.Subnet), 160));
        _grid.Columns.Add(ListPageHelper.Col("主网卡", nameof(VnicRow.Primary), 70));

        var bar = ListPageHelper.TopBar(
            FormFieldFactory.Secondary("切换公网 IP", async (_, _) => await ChangeIpAsync()),
            FormFieldFactory.Secondary("启用 IPv6", async (_, _) => await EnableIpv6Async()));
        Content = ListPageHelper.Wrap(_scaffold, bar, _grid);
        Loaded += async (_, _) => await LoadAsync();
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var rows = await _service.ListVnicsAsync(_item.Id).ConfigureAwait(true);
            if (rows.Count == 0)
            {
                // fallback display from instance itself
                _grid.ItemsSource = new List<VnicRow>
                {
                    new()
                    {
                        Name = "primary",
                        PrivateIp = _item.PrivateIps,
                        PublicIp = _item.PublicIps,
                        Primary = "是"
                    }
                };
                return;
            }
            _grid.ItemsSource = rows.Select(m => new VnicRow
            {
                Id = JsonPage.Pick(m, "id", "vnicId"),
                Name = JsonPage.Pick(m, "displayName", "name"),
                PrivateIp = JsonPage.Pick(m, "privateIp", "privateIps"),
                PublicIp = JsonPage.Pick(m, "publicIp", "publicIps"),
                Subnet = JsonPage.Pick(m, "subnetId", "subnet"),
                Primary = JsonUtil.Bool(m, "isPrimary") || JsonPage.Pick(m, "isPrimary") == "true" ? "是" : "否"
            }).ToList();
        });

    private async Task ChangeIpAsync()
    {
        var ranges = InstancesView.PromptCidrRanges(_item);
        if (ranges == null) return;
        try
        {
            var msg = await _service.ChangeSpecIpAsync(_item.Id, ranges).ConfigureAwait(true);
            ToastService.Success(msg);
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task EnableIpv6Async()
    {
        try
        {
            var msg = await _service.EnableIpv6Async(_item.Id).ConfigureAwait(true);
            ToastService.Success(msg);
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }
}
