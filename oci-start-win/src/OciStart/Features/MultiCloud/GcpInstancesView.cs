using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;
using OciStart.Features.Shared;

namespace OciStart.Features.MultiCloud;

public sealed class GcpInstanceRow
{
    public string BootId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Tenant { get; set; } = "";
    public string Zone { get; set; } = "";
    public string PublicIp { get; set; } = "";
    public string Status { get; set; } = "";
    public string Spec { get; set; } = "";
    public string Created { get; set; } = "";
}

/// <summary>GCP 实例列表 — /other/instances/list/json + delete/refresh/changeIp.</summary>
public sealed class GcpInstancesView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly TextBlock _pageInfo = ListPageHelper.PageInfo();
    private readonly ComboBox _tenantBox = new() { MinWidth = 200, Padding = new Thickness(8, 6, 8, 6) };
    private List<TenantRegionOption> _tenants = [];
    private int _page;
    private int _totalPages = 1;
    private const int PageSize = 20;

    public GcpInstancesView()
    {
        _scaffold.Title = "GCP 实例";
        _scaffold.Subtitle = "OtherBoot · list/json · 刷新 / 换 IP / 删除";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新列表", async (_, _) => await LoadAsync()),
            FormFieldFactory.Secondary("刷新状态", async (_, _) => await Act("refresh")),
            FormFieldFactory.Secondary("换 IP", async (_, _) => await Act("changeIp")),
            FormFieldFactory.Secondary("删除", async (_, _) => await Act("delete", confirm: true)),
            FormFieldFactory.Primary("创建实例", async (_, _) => await ShowCreateDialogAsync()),
            FormFieldFactory.Secondary("上一页", async (_, _) =>
            {
                if (_page > 0) { _page--; await LoadAsync(); }
            }),
            FormFieldFactory.Secondary("下一页", async (_, _) =>
            {
                if (_page + 1 < _totalPages) { _page++; await LoadAsync(); }
            }),
            _pageInfo);

        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(GcpInstanceRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("租户", nameof(GcpInstanceRow.Tenant), 120));
        _grid.Columns.Add(ListPageHelper.Col("Zone", nameof(GcpInstanceRow.Zone), 140));
        _grid.Columns.Add(ListPageHelper.Col("公网 IP", nameof(GcpInstanceRow.PublicIp), 130));
        _grid.Columns.Add(ListPageHelper.Col("状态", nameof(GcpInstanceRow.Status), 90));
        _grid.Columns.Add(ListPageHelper.Col("规格", nameof(GcpInstanceRow.Spec), 120));
        _grid.Columns.Add(ListPageHelper.Col("创建", nameof(GcpInstanceRow.Created), 150));

        var bar = ListPageHelper.TopBar(
            new TextBlock
            {
                Text = "租户筛选",
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 8, 0),
                Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
            },
            _tenantBox,
            FormFieldFactory.Primary("查询", async (_, _) =>
            {
                _page = 0;
                await LoadAsync();
            }));

        Content = ListPageHelper.Wrap(_scaffold, bar, _grid);
        Loaded += async (_, _) =>
        {
            await LoadTenantsAsync();
            await LoadAsync();
        };
    }

    private long SelectedTenantFilter()
    {
        // index 0 = all
        if (_tenantBox.SelectedIndex <= 0) return 0;
        var i = _tenantBox.SelectedIndex - 1;
        if (i < 0 || i >= _tenants.Count) return 0;
        return long.TryParse(_tenants[i].Id, out var id) ? id : 0;
    }

    private async Task LoadTenantsAsync()
    {
        try
        {
            var raw = await _api.GetJsonAsync("/tenants/list/json", new Dictionary<string, string>
            {
                ["page"] = "0",
                ["size"] = "200",
                ["cloudType"] = "2"
            }).ConfigureAwait(true);
            var (rows, _, _, _) = JsonPage.Parse(raw, ["content", "list", "data", "records"]);
            _tenants = rows.Select(m => new TenantRegionOption
            {
                Id = JsonPage.Pick(m, "id", "tenantId"),
                UserName = JsonPage.Pick(m, "userName", "defName", "tenancyName", "name"),
                TenancyName = JsonPage.Pick(m, "tenancyName", "tenancy")
            }).Where(t => !string.IsNullOrEmpty(t.Id)).ToList();
            var labels = new List<string> { "全部租户" };
            labels.AddRange(_tenants.Select(t => t.DisplayLabel));
            _tenantBox.ItemsSource = labels;
            _tenantBox.SelectedIndex = 0;
        }
        catch
        {
            _tenantBox.ItemsSource = new[] { "全部租户" };
            _tenantBox.SelectedIndex = 0;
        }
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var q = new Dictionary<string, string>
            {
                ["cloudType"] = "2",
                ["page"] = _page.ToString(),
                ["size"] = PageSize.ToString()
            };
            var tid = SelectedTenantFilter();
            if (tid > 0) q["tenantId"] = tid.ToString();

            var raw = await _api.GetJsonAsync("/other/instances/list/json", q).ConfigureAwait(true);
            var root = JsonUtil.Obj(raw);
            if (root != null && root.TryGetValue("success", out var ok) &&
                ok.ValueKind == System.Text.Json.JsonValueKind.False)
            {
                var msg = JsonUtil.Str(root, "message");
                throw ApiError.Server(string.IsNullOrEmpty(msg)
                    ? "加载 GCP 实例失败（请升级服务端以支持 /list/json）"
                    : msg);
            }

            var (rows, page, pages, total) = JsonPage.Parse(raw, ["content", "list", "data", "instances"]);
            _page = page;
            _totalPages = Math.Max(1, pages);
            _grid.ItemsSource = rows.Select(m =>
            {
                var status = JsonUtil.Int(m, "status", -1);
                return new GcpInstanceRow
                {
                    BootId = JsonPage.Pick(m, "bootId", "id"),
                    Name = JsonPage.Pick(m, "instanceName", "name", "bootId"),
                    Tenant = JsonPage.Pick(m, "defName", "tenantId"),
                    Zone = JsonPage.Pick(m, "zone", "region"),
                    PublicIp = JsonPage.Pick(m, "publicIp", "publicIps"),
                    Status = StatusLabel(status, JsonPage.Pick(m, "status")),
                    Spec = $"{JsonPage.Pick(m, "ocpu", "cpu")}C / {JsonPage.Pick(m, "memory")}M / {JsonPage.Pick(m, "disk")}G",
                    Created = JsonPage.Pick(m, "createdAt", "createTime")
                };
            }).ToList();
            _pageInfo.Text = $"第 {_page + 1}/{_totalPages} 页 · 共 {total}";
            _scaffold.Subtitle = $"GCP 实例 · 共 {total} 台";
        });

    private static string StatusLabel(int code, string raw) => code switch
    {
        0 => "未开机",
        1 => "开机中",
        2 => "已开机",
        _ => string.IsNullOrEmpty(raw) ? "—" : raw
    };

    private GcpInstanceRow? Selected() => _grid.SelectedItem as GcpInstanceRow;

    private async Task Act(string action, bool confirm = false)
    {
        var row = Selected();
        if (row == null || string.IsNullOrEmpty(row.BootId))
        {
            ToastService.Info("请先选择实例");
            return;
        }
        if (confirm && MessageBox.Show($"确定删除「{row.Name}」？", "删除 GCP 实例",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            _scaffold.SetLoading(true);
            var path = action switch
            {
                "refresh" => $"/other/instances/{row.BootId}/refresh",
                "changeIp" => $"/other/instances/{row.BootId}/changeIp",
                "delete" => $"/other/instances/{row.BootId}/delete",
                _ => throw new InvalidOperationException(action)
            };
            var raw = await _api.PostJsonAsync(path, new { }).ConfigureAwait(true);
            var root = JsonUtil.Obj(raw);
            var success = root == null || !root.ContainsKey("success") || JsonUtil.Bool(root, "success");
            var msg = root == null ? "完成" : JsonUtil.Str(root, "message");
            if (!success)
                throw ApiError.Server(string.IsNullOrEmpty(msg) ? "操作失败" : msg);
            ToastService.Success(string.IsNullOrEmpty(msg) ? "完成" : msg);
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _scaffold.SetLoading(false);
        }
    }

    private async Task ShowCreateDialogAsync()
    {
        if (_tenants.Count == 0)
        {
            ToastService.Info("请先在「GCP 账户」添加 Service Account");
            return;
        }

        var tenantBox = new ComboBox
        {
            MinWidth = 240,
            ItemsSource = _tenants.Select(t => t.DisplayLabel).ToList(),
            SelectedIndex = 0,
            Padding = new Thickness(8, 6, 8, 6)
        };
        var name = FormFieldFactory.TextField(watermark: "instance-name");
        var region = FormFieldFactory.TextField("us-central1");
        var zone = FormFieldFactory.TextField("us-central1-a");
        var machine = FormFieldFactory.TextField("e2-micro");
        var image = FormFieldFactory.TextField(
            "projects/debian-cloud/global/images/family/debian-12");
        var disk = FormFieldFactory.TextField("20");
        var count = FormFieldFactory.TextField("1");

        var ok = false;
        var win = new Window
        {
            Title = "创建 GCP 实例",
            Width = 480,
            Height = 520,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null)
            win.Owner = Application.Current.MainWindow;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(FormFieldFactory.Labeled("租户", tenantBox));
        panel.Children.Add(FormFieldFactory.Labeled("实例名", name));
        panel.Children.Add(FormFieldFactory.Labeled("Region", region));
        panel.Children.Add(FormFieldFactory.Labeled("Zone", zone));
        panel.Children.Add(FormFieldFactory.Labeled("机器类型", machine));
        panel.Children.Add(FormFieldFactory.Labeled("镜像", image));
        panel.Children.Add(FormFieldFactory.Labeled("磁盘 GB", disk));
        panel.Children.Add(FormFieldFactory.Labeled("数量 1–10", count));
        panel.Children.Add(new TextBlock
        {
            Text = "提交走 POST /other/instances/save（表单）；服务端异步创建。",
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 8, 0, 0)
        });
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary("创建", (_, _) => { ok = true; win.Close(); }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        if (!ok) return;

        var ti = tenantBox.SelectedIndex;
        if (ti < 0 || ti >= _tenants.Count)
        {
            ToastService.Error("请选择租户");
            return;
        }
        var fields = new Dictionary<string, string>
        {
            ["tenantId"] = _tenants[ti].Id,
            ["instanceName"] = (name.Text ?? "").Trim(),
            ["region"] = (region.Text ?? "").Trim(),
            ["zone"] = (zone.Text ?? "").Trim(),
            ["machineType"] = (machine.Text ?? "").Trim(),
            ["sourceImage"] = (image.Text ?? "").Trim(),
            ["diskSize"] = (disk.Text ?? "20").Trim(),
            ["instanceCount"] = (count.Text ?? "1").Trim()
        };
        if (fields.Values.Any(string.IsNullOrEmpty))
        {
            ToastService.Error("请填写完整创建参数");
            return;
        }

        try
        {
            _scaffold.SetLoading(true);
            // form POST — server redirects; 2xx = accepted
            var (data, status) = await _api.PostFormAsync("/other/instances/save", fields)
                .ConfigureAwait(true);
            if ((int)status is < 200 or >= 400)
            {
                var msg = System.Text.Encoding.UTF8.GetString(data);
                throw ApiError.Server(string.IsNullOrWhiteSpace(msg) ? "创建失败" : msg);
            }
            ToastService.Success("创建请求已提交");
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _scaffold.SetLoading(false);
        }
    }
}
