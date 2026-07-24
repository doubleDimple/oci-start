using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Tenants;

/// <summary>租户管理 + 二级整页（对齐 Mac TenantsView 导航模式）.</summary>
public sealed class TenantsView : UserControl
{
    private readonly TenantsService _service = new();
    private readonly Grid _host = new();
    private readonly PageScaffold _scaffold = new();
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly TextBox _search = FormFieldFactory.TextField(watermark: "搜索租户");
    private readonly TextBlock _pageInfo = ListPageHelper.PageInfo();

    private int _page;
    private int _totalPages = 1;
    private const int PageSize = 10;
    private bool _namesHidden = true;
    private List<TenantItem> _rows = [];
    /// <summary>0 = use session cloud; else force (e.g. GCP accounts = 2).</summary>
    private readonly int _forcedCloudType;
    private readonly string _title;
    private readonly string _subtitle;

    public TenantsView() : this(0, null, null) { }

    /// <param name="forcedCloudType">0=session; 1=OCI; 2=GCP; 3=Azure; 4=AWS</param>
    public TenantsView(int forcedCloudType, string? title, string? subtitle)
    {
        _forcedCloudType = forcedCloudType;
        _title = title ?? "租户管理";
        _subtitle = subtitle ?? "OCI API 配置与账号列表";
        Content = _host;
        ShowList();
        Loaded += async (_, _) => await LoadAsync();
    }

    private int EffectiveCloudType =>
        _forcedCloudType > 0 ? _forcedCloudType : Math.Max(1, AppSession.Shared.CloudProvider);

    private void ShowList()
    {
        _host.Children.Clear();
        BuildList();
        _host.Children.Add(_scaffold);
    }

    private void BuildList()
    {
        _scaffold.Title = _title;
        _scaffold.Subtitle = _subtitle;
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary(_namesHidden ? "显示名称" : "隐藏名称", async (_, _) =>
            {
                _namesHidden = !_namesHidden;
                await LoadAsync();
            }),
            FormFieldFactory.Primary("添加 API", (_, _) =>
            {
                _host.Children.Clear();
                _host.Children.Add(new TenantAddApiPage(ShowList, _service, () =>
                {
                    ShowList();
                    _ = LoadAsync();
                }, EffectiveCloudType));
            }),
            FormFieldFactory.Secondary("导入 JSON", async (_, _) => await ImportJsonAsync()),
            FormFieldFactory.Secondary("导出", async (_, _) => await ExportAsync()),
            FormFieldFactory.Secondary("账号检测", async (_, _) =>
            {
                try
                {
                    await _service.StartAccountCheckAsync().ConfigureAwait(true);
                    ToastService.Success("账号检测已触发");
                }
                catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
            }),
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()),
            FormFieldFactory.Secondary("上一页", async (_, _) => { if (_page > 0) { _page--; await LoadAsync(); } }),
            FormFieldFactory.Secondary("下一页", async (_, _) => { if (_page + 1 < _totalPages) { _page++; await LoadAsync(); } }));

        if (_grid.Columns.Count == 0)
        {
            _grid.Columns.Add(ListPageHelper.Col("名称", nameof(TenantItem.DisplayName), star: true));
            _grid.Columns.Add(ListPageHelper.Col("用户", nameof(TenantItem.UserName), 120));
            _grid.Columns.Add(ListPageHelper.Col("区域", nameof(TenantItem.Region), 140));
            _grid.Columns.Add(ListPageHelper.Col("类型", nameof(TenantItem.AccountTypeName), 100));
            _grid.Columns.Add(ListPageHelper.Col("费用", nameof(TenantItem.AccountCost), 80));
            _grid.Columns.Add(ListPageHelper.Col("同步", nameof(TenantItem.ApiSynced), 60));
            _grid.Columns.Add(ListPageHelper.Col("代理", nameof(TenantItem.ProxyBound), 60));
        }

        var bar = ListPageHelper.TopBar(
            _search,
            FormFieldFactory.Primary("搜索", async (_, _) => { _page = 0; await LoadAsync(); }),
            FormFieldFactory.Primary("同步", async (_, _) => await SyncSelectedAsync()),
            FormFieldFactory.Secondary("删除", async (_, _) => await DeleteSelectedAsync()),
            FormFieldFactory.Secondary("自定义名", async (_, _) => await EditNameAsync()),
            FormFieldFactory.Secondary("改费用", async (_, _) => await EditCostAsync()),
            FormFieldFactory.Secondary("详情", (_, _) => Open(t => new TenantDetailPage(t, ShowList, _service))),
            FormFieldFactory.Secondary("用户", (_, _) => Open(t => new TenantUsersPage(t, ShowList, _service))),
            FormFieldFactory.Secondary("费用页", (_, _) => Open(t => new TenantCostPage(t, ShowList, _service))),
            FormFieldFactory.Secondary("配额", (_, _) => Open(t => new TenantQuotaPage(t, ShowList, _service))),
            FormFieldFactory.Secondary("审计", (_, _) => Open(t => new TenantAuditLogPage(t, ShowList, _service))),
            FormFieldFactory.Secondary("流量", (_, _) => Open(t => new TenantTrafficPage(t, ShowList, _service))),
            FormFieldFactory.Secondary("区域订阅", (_, _) => Open(t => new TenantRegionSubPage(t, ShowList, _service))),
            FormFieldFactory.Secondary("开机创建", (_, _) => Open(t => new TenantBootCreatePage(t, ShowList, _service))),
            _pageInfo);
        _search.Width = 200;

        var root = new DockPanel();
        DockPanel.SetDock(bar, Dock.Top);
        root.Children.Add(bar);
        root.Children.Add(_grid);
        _scaffold.SetBody(root);
    }

    private void Open(Func<TenantItem, UserControl> factory)
    {
        var t = Selected();
        if (t == null) { ToastService.Info("请先选择租户"); return; }
        _host.Children.Clear();
        _host.Children.Add(factory(t));
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var cloud = EffectiveCloudType;
            var resp = await _service.ListAsync(_page, PageSize, _search.Text, cloud).ConfigureAwait(true);
            _rows = resp.Content;
            if (_namesHidden)
            {
                foreach (var r in _rows)
                {
                    if (!string.IsNullOrEmpty(r.UserName) && r.UserName.Length > 2)
                        r.UserName = $"{r.UserName[0]}***{r.UserName[^1]}";
                    if (!string.IsNullOrEmpty(r.TenancyName) && r.TenancyName.Length > 2)
                        r.TenancyName = $"{r.TenancyName[0]}***{r.TenancyName[^1]}";
                }
            }
            _totalPages = Math.Max(1, resp.TotalPages);
            _grid.ItemsSource = null;
            _grid.ItemsSource = _rows;
            _pageInfo.Text = $"第 {_page + 1}/{_totalPages} 页 · 共 {resp.TotalElements}";
        });

    private TenantItem? Selected() => _grid.SelectedItem as TenantItem;

    private async Task SyncSelectedAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择租户"); return; }
        try
        {
            _scaffold.SetLoading(true);
            await _service.SyncOciAsync(item.Id).ConfigureAwait(true);
            ToastService.Success("同步完成");
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
            _scaffold.SetLoading(false);
        }
    }

    private async Task DeleteSelectedAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择租户"); return; }
        if (MessageBox.Show($"确认删除租户「{item.DisplayName}」？", "删除",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;
        try
        {
            await _service.DeleteAsync(item.Id).ConfigureAwait(true);
            ToastService.Success("已删除");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task EditNameAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择租户"); return; }
        var name = Prompt("自定义名称", item.DefName);
        if (name == null) return;
        try
        {
            await _service.UpdateCustomNameAsync(item.Id, name).ConfigureAwait(true);
            ToastService.Success("已更新");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task EditCostAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择租户"); return; }
        var cost = Prompt("账户费用", item.AccountCost);
        if (cost == null) return;
        try
        {
            await _service.UpdateAccountCostAsync(item.Id, cost).ConfigureAwait(true);
            ToastService.Success("已更新");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task ExportAsync()
    {
        try
        {
            var (data, name) = await _service.ExportAsync().ConfigureAwait(true);
            var dlg = new SaveFileDialog { FileName = name ?? "tenants.json", Filter = "All|*.*" };
            if (dlg.ShowDialog() == true)
            {
                await File.WriteAllBytesAsync(dlg.FileName, data).ConfigureAwait(true);
                ToastService.Success("已导出");
            }
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task ImportJsonAsync()
    {
        var dlg = new OpenFileDialog
        {
            Title = "导入租户 JSON（对象数组）",
            Filter = "JSON|*.json|All|*.*"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var bytes = await File.ReadAllBytesAsync(dlg.FileName).ConfigureAwait(true);
            await _service.ImportJsonAsync(bytes).ConfigureAwait(true);
            ToastService.Success("导入完成");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private static string? Prompt(string title, string initial)
    {
        var win = new Window
        {
            Title = title,
            Width = 360,
            Height = 150,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null) win.Owner = Application.Current.MainWindow;
        var box = FormFieldFactory.TextField(initial);
        var ok = false;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(box);
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary("确定", (_, _) => { ok = true; win.Close(); }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        return ok ? box.Text?.Trim() : null;
    }
}
