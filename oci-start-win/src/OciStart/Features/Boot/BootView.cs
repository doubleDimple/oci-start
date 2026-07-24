using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;
using OciStart.Features.Shared;

namespace OciStart.Features.Boot;

public sealed class BootRow
{
    public long Id { get; set; }
    public string Name { get; set; } = "";
    public string Status { get; set; } = "";
    public string Region { get; set; } = "";
    public string Tenant { get; set; } = "";
    public string Shape { get; set; } = "";
    public string FailCount { get; set; } = "";
}

/// <summary>开机管理（对齐 Mac BootView 主列表操作）.</summary>
public sealed class BootView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly ComboBox _parentBox = new() { MinWidth = 200, Padding = new Thickness(8, 6, 8, 6) };
    private readonly TextBlock _pageInfo = ListPageHelper.PageInfo();
    private readonly TextBlock _stats = new()
    {
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(12, 0, 0, 0)
    };

    private List<TenantRegionOption> _parents = [];
    private string? _filterTenantId;
    private int _page;
    private int _totalPages = 1;

    public BootView()
    {
        _scaffold.Title = "开机管理";
        _scaffold.Subtitle = "抢机任务列表";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()),
            FormFieldFactory.Secondary("批量启动", async (_, _) => await PostOk("/boot/batchStart", "批量启动")),
            FormFieldFactory.Secondary("批量停止", async (_, _) => await PostOk("/boot/batchStop", "批量停止")),
            FormFieldFactory.Secondary("重置失败次数", async (_, _) => await PostOk("/boot/batchInitFailCount", "重置")),
            FormFieldFactory.Secondary("上一页", async (_, _) => { if (_page > 0) { _page--; await LoadAsync(); } }),
            FormFieldFactory.Secondary("下一页", async (_, _) => { if (_page + 1 < _totalPages) { _page++; await LoadAsync(); } }));

        _grid.Columns.Add(ListPageHelper.Col("ID", nameof(BootRow.Id), 70));
        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(BootRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("状态", nameof(BootRow.Status), 100));
        _grid.Columns.Add(ListPageHelper.Col("区域", nameof(BootRow.Region), 140));
        _grid.Columns.Add(ListPageHelper.Col("租户", nameof(BootRow.Tenant), 120));
        _grid.Columns.Add(ListPageHelper.Col("Shape", nameof(BootRow.Shape), 140));
        _grid.Columns.Add(ListPageHelper.Col("失败", nameof(BootRow.FailCount), 60));

        var filter = ListPageHelper.TopBar(
            new TextBlock { Text = "租户", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) },
            _parentBox,
            FormFieldFactory.Primary("筛选", async (_, _) =>
            {
                if (_parentBox.SelectedIndex >= 0 && _parentBox.SelectedIndex < _parents.Count)
                    _filterTenantId = _parents[_parentBox.SelectedIndex].Id;
                else
                    _filterTenantId = null;
                _page = 0;
                await LoadAsync();
            }),
            FormFieldFactory.Secondary("清除筛选", async (_, _) =>
            {
                _parentBox.SelectedIndex = -1;
                _filterTenantId = null;
                _page = 0;
                await LoadAsync();
            }),
            _stats);

        var actions = ListPageHelper.TopBar(
            FormFieldFactory.Primary("启动", async (_, _) => await BootAction("startBoot", "启动")),
            FormFieldFactory.Secondary("停止", async (_, _) => await BootAction("stopBoot", "停止")),
            FormFieldFactory.Secondary("手动抢机", async (_, _) => await BootAction("manualBoot", "手动抢机")),
            FormFieldFactory.Secondary("克隆", async (_, _) => await BootAction("startCloneBoot", "克隆")),
            FormFieldFactory.Secondary("删除", async (_, _) => await BootAction("deleteBoot", "删除", confirm: true)),
            _pageInfo);

        var top = new StackPanel();
        top.Children.Add(filter);
        top.Children.Add(actions);
        Content = ListPageHelper.Wrap(_scaffold, top, _grid);
        Loaded += async (_, _) =>
        {
            await LoadParentsAsync();
            await LoadAsync();
        };
    }

    private async Task LoadParentsAsync()
    {
        try
        {
            var raw = await _api.GetJsonAsync("/tenants/listParentTenants").ConfigureAwait(true);
            _parents = TenantRegionOption.ParseList(raw);
            _parentBox.ItemsSource = _parents.Select(p => p.DisplayLabel).ToList();
        }
        catch { _parents = []; }
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var q = new Dictionary<string, string>
            {
                ["page"] = _page.ToString(),
                ["size"] = "10"
            };
            if (!string.IsNullOrEmpty(_filterTenantId))
                q["tenantId"] = _filterTenantId!;

            var raw = await _api.GetJsonAsync("/boot/fullBootList/json", q).ConfigureAwait(true);
            var (rows, _, pages, total) = JsonPage.Parse(raw);
            _totalPages = Math.Max(1, pages);
            _grid.ItemsSource = rows.Select(m => new BootRow
            {
                Id = JsonUtil.Int64(m, "id"),
                Name = JsonPage.Pick(m, "bootName", "name", "displayName"),
                Status = JsonPage.Pick(m, "status", "state", "bootStatus"),
                Region = JsonPage.Pick(m, "region", "regionName"),
                Tenant = JsonPage.Pick(m, "userName", "tenantName", "tenancyName"),
                Shape = JsonPage.Pick(m, "shape", "instanceShape"),
                FailCount = JsonPage.Pick(m, "failCount", "failedCount", "errorCount")
            }).ToList();
            _pageInfo.Text = $"第 {_page + 1}/{_totalPages} 页 · 共 {total}";

            try
            {
                var off = await CountAsync("/boot/getOfflineCount").ConfigureAwait(true);
                var starting = await CountAsync("/boot/getStartingCount").ConfigureAwait(true);
                _stats.Text = $"离线 {off} · 启动中 {starting}";
            }
            catch { _stats.Text = ""; }
        });

    private async Task<long> CountAsync(string path)
    {
        var raw = await _api.GetJsonAsync(path).ConfigureAwait(true);
        var root = JsonUtil.Obj(raw) ?? new();
        return JsonUtil.Int64(root, "count");
    }

    private async Task BootAction(string action, string label, bool confirm = false)
    {
        if (_grid.SelectedItem is not BootRow row)
        {
            ToastService.Info("请先选择任务");
            return;
        }
        if (confirm && MessageBox.Show($"确认{label}「{row.Name}」？", label,
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;
        try
        {
            var raw = await _api.GetJsonAsync($"/boot/{action}", new Dictionary<string, string>
            {
                ["bootId"] = row.Id.ToString()
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, label + "失败");
            ToastService.Success(label + "成功");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task PostOk(string path, string label)
    {
        try
        {
            var raw = await _api.PostJsonAsync(path, new { }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, label + "失败");
            ToastService.Success(label + "完成");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }
}
