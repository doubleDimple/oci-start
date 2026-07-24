using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;
using OciStart.Features.Shared;

namespace OciStart.Features.Tenants;

public sealed class GenericDictRow
{
    public string C1 { get; set; } = "";
    public string C2 { get; set; } = "";
    public string C3 { get; set; } = "";
    public string C4 { get; set; } = "";
    public string C5 { get; set; } = "";
}

/// <summary>租户详情 · 区域列表（对齐 Mac TenantDetailView 主信息）.</summary>
public sealed class TenantDetailPage : UserControl
{
    public TenantDetailPage(TenantItem tenant, Action onBack, TenantsService service)
    {
        var scaffold = new PageScaffold
        {
            Title = "租户详情 — " + tenant.DisplayName,
            Subtitle = tenant.TenantId
        };
        scaffold.SetToolbar(FormFieldFactory.Secondary("返回", (_, _) => onBack()));
        var grid = ListPageHelper.CreateGrid();
        grid.Columns.Add(ListPageHelper.Col("区域", nameof(GenericDictRow.C1), 140));
        grid.Columns.Add(ListPageHelper.Col("名称", nameof(GenericDictRow.C2), star: true));
        grid.Columns.Add(ListPageHelper.Col("状态", nameof(GenericDictRow.C3), 100));
        grid.Columns.Add(ListPageHelper.Col("主区域", nameof(GenericDictRow.C4), 80));
        grid.Columns.Add(ListPageHelper.Col("ID", nameof(GenericDictRow.C5), 100));
        scaffold.SetBody(grid);
        Content = scaffold;
        Loaded += async (_, _) =>
        {
            await ListPageHelper.SafeLoad(scaffold, async () =>
            {
                List<Dictionary<string, System.Text.Json.JsonElement>> rows;
                try
                {
                    rows = await service.RegionListJsonAsync(tenant.Id).ConfigureAwait(true);
                }
                catch
                {
                    var regs = await service.ListRegionsAsync(tenant.Id).ConfigureAwait(true);
                    grid.ItemsSource = regs.Select(r => new GenericDictRow
                    {
                        C1 = r.Region,
                        C2 = r.DisplayLabel,
                        C3 = "",
                        C4 = r.IsHomeRegion ? "是" : "否",
                        C5 = r.Id
                    }).ToList();
                    return;
                }
                grid.ItemsSource = rows.Select(m => new GenericDictRow
                {
                    C1 = JsonPage.Pick(m, "region", "regionName", "regionCode"),
                    C2 = JsonPage.Pick(m, "name", "userName", "defName", "tenancyName"),
                    C3 = JsonPage.Pick(m, "status", "state"),
                    C4 = JsonUtil.Bool(m, "isHomeRegion") || JsonUtil.Bool(m, "homeRegion") ? "是" : "否",
                    C5 = JsonPage.Pick(m, "id", "tenantId")
                }).ToList();
            });
        };
    }
}

public sealed class TenantUsersPage : UserControl
{
    public TenantUsersPage(TenantItem tenant, Action onBack, TenantsService service)
    {
        var scaffold = new PageScaffold
        {
            Title = "用户管理 — " + tenant.DisplayName,
            Subtitle = "Oracle IAM 用户"
        };
        scaffold.SetToolbar(FormFieldFactory.Secondary("返回", (_, _) => onBack()));
        var grid = ListPageHelper.CreateGrid();
        grid.Columns.Add(ListPageHelper.Col("用户名", nameof(GenericDictRow.C1), star: true));
        grid.Columns.Add(ListPageHelper.Col("邮箱", nameof(GenericDictRow.C2), 180));
        grid.Columns.Add(ListPageHelper.Col("ID", nameof(GenericDictRow.C3), 200));
        grid.Columns.Add(ListPageHelper.Col("状态", nameof(GenericDictRow.C4), 80));
        scaffold.SetBody(grid);
        Content = scaffold;
        Loaded += async (_, _) =>
        {
            await ListPageHelper.SafeLoad(scaffold, async () =>
            {
                var rows = await service.ListUsersAsync(tenant.Id).ConfigureAwait(true);
                grid.ItemsSource = rows.Select(m => new GenericDictRow
                {
                    C1 = JsonPage.Pick(m, "name", "userName", "username"),
                    C2 = JsonPage.Pick(m, "email", "emailAddress"),
                    C3 = JsonPage.Pick(m, "id", "userId", "ocid"),
                    C4 = JsonPage.Pick(m, "lifecycleState", "status", "state")
                }).ToList();
            });
        };
    }
}

public sealed class TenantCostPage : UserControl
{
    public TenantCostPage(TenantItem tenant, Action onBack, TenantsService service)
    {
        var scaffold = new PageScaffold
        {
            Title = "费用统计 — " + tenant.DisplayName,
            Subtitle = "/cost/query"
        };
        scaffold.SetToolbar(FormFieldFactory.Secondary("返回", (_, _) => onBack()));
        var grid = ListPageHelper.CreateGrid();
        grid.Columns.Add(ListPageHelper.Col("项目", nameof(GenericDictRow.C1), star: true));
        grid.Columns.Add(ListPageHelper.Col("金额", nameof(GenericDictRow.C2), 120));
        grid.Columns.Add(ListPageHelper.Col("币种", nameof(GenericDictRow.C3), 80));
        grid.Columns.Add(ListPageHelper.Col("时间", nameof(GenericDictRow.C4), 160));
        scaffold.SetBody(grid);
        Content = scaffold;
        Loaded += async (_, _) =>
        {
            await ListPageHelper.SafeLoad(scaffold, async () =>
            {
                var rows = await service.QueryCostAsync(tenant.Id).ConfigureAwait(true);
                grid.ItemsSource = rows.Select(m => new GenericDictRow
                {
                    C1 = JsonPage.Pick(m, "name", "service", "description", "product"),
                    C2 = JsonPage.Pick(m, "cost", "amount", "value", "total"),
                    C3 = JsonPage.Pick(m, "currency", "currencyCode"),
                    C4 = JsonPage.Pick(m, "time", "date", "period")
                }).ToList();
            });
        };
    }
}

public sealed class TenantQuotaPage : UserControl
{
    public TenantQuotaPage(TenantItem tenant, Action onBack, TenantsService service)
    {
        var scaffold = new PageScaffold
        {
            Title = "账号配额 — " + tenant.DisplayName,
            Subtitle = "compute 配额"
        };
        scaffold.SetToolbar(FormFieldFactory.Secondary("返回", (_, _) => onBack()));
        var grid = ListPageHelper.CreateGrid();
        grid.Columns.Add(ListPageHelper.Col("名称", nameof(GenericDictRow.C1), star: true));
        grid.Columns.Add(ListPageHelper.Col("已用", nameof(GenericDictRow.C2), 100));
        grid.Columns.Add(ListPageHelper.Col("可用", nameof(GenericDictRow.C3), 100));
        grid.Columns.Add(ListPageHelper.Col("限制", nameof(GenericDictRow.C4), 100));
        scaffold.SetBody(grid);
        Content = scaffold;
        Loaded += async (_, _) =>
        {
            await ListPageHelper.SafeLoad(scaffold, async () =>
            {
                var rows = await service.QueryQuotaAsync(tenant.Id).ConfigureAwait(true);
                grid.ItemsSource = rows.Select(m => new GenericDictRow
                {
                    C1 = JsonPage.Pick(m, "name", "quotaName", "service"),
                    C2 = JsonPage.Pick(m, "used", "usage"),
                    C3 = JsonPage.Pick(m, "available", "remaining"),
                    C4 = JsonPage.Pick(m, "limit", "value", "max")
                }).ToList();
            });
        };
    }
}

// ─── 添加 API（multipart） ───────────────────────────────────────────

/// <summary>添加 API 配置整页（对齐 Mac 添加表单 · POST /tenants/save multipart）.</summary>
public sealed class TenantAddApiPage : UserControl
{
    public TenantAddApiPage(Action onBack, TenantsService service, Action onSaved, int cloudType = 0)
    {
        var ct = cloudType > 0 ? cloudType : Math.Max(1, AppSession.Shared.CloudProvider);
        var isGcp = ct == 2;
        var scaffold = new PageScaffold
        {
            Title = isGcp ? "添加 GCP 账户" : "添加 API 配置",
            Subtitle = isGcp ? "Service Account JSON · cloudType=2" : "multipart · /tenants/save"
        };
        var user = FormFieldFactory.TextField();
        var tenantId = FormFieldFactory.TextField();
        var fingerprint = FormFieldFactory.TextField();
        var tenancy = FormFieldFactory.TextField();
        var region = FormFieldFactory.TextField(isGcp ? "us-central1" : "ap-singapore-1");
        var keyPath = FormFieldFactory.TextField();
        keyPath.IsReadOnly = true;
        string? selectedKey = null;

        var card = new ModuleSettingsCard(
            isGcp ? "GCP 凭据" : "API 凭据",
            isGcp ? "填写项目标识与 Service Account JSON 密钥" : "填写 OCI 用户 / 租户 OCID / 指纹 / 私钥",
            "🔑",
            Color.FromRgb(0x4A, 0x9E, 0xFF),
            showToggle: false,
            minHeight: 420);

        if (isGcp)
        {
            card.SetBody(
                FormFieldFactory.Labeled("显示名称 (userName)", user),
                FormFieldFactory.Labeled("Project / 租户标识 (tenantId)", tenantId),
                FormFieldFactory.Labeled("区域 (region)", region),
                FormFieldFactory.Labeled("Service Account JSON", keyPath));
        }
        else
        {
            card.SetBody(
                FormFieldFactory.Labeled("UserName", user),
                FormFieldFactory.Labeled("User OCID (tenantId)", tenantId),
                FormFieldFactory.Labeled("Fingerprint", fingerprint),
                FormFieldFactory.Labeled("Tenancy OCID", tenancy),
                FormFieldFactory.Labeled("Region", region),
                FormFieldFactory.Labeled("私钥文件 (.pem)", keyPath));
        }

        card.SetFooter(
            FormFieldFactory.Secondary(isGcp ? "选择 JSON" : "选择私钥", (_, _) =>
            {
                var dlg = new OpenFileDialog
                {
                    Title = isGcp ? "选择 GCP Service Account JSON" : "选择 OCI API 私钥",
                    Filter = isGcp
                        ? "JSON|*.json|All|*.*"
                        : "PEM/Key|*.pem;*.key;*.txt|All|*.*"
                };
                if (dlg.ShowDialog() == true)
                {
                    selectedKey = dlg.FileName;
                    keyPath.Text = dlg.FileName;
                }
            }),
            FormFieldFactory.Primary("保存", async (_, _) =>
            {
                var fields = new Dictionary<string, string>
                {
                    ["userName"] = (user.Text ?? "").Trim(),
                    ["tenantId"] = (tenantId.Text ?? "").Trim(),
                    ["region"] = (region.Text ?? "").Trim(),
                    ["cloudType"] = ct.ToString(),
                    ["status"] = "0"
                };
                if (isGcp)
                {
                    fields["fingerprint"] = "gcp";
                    fields["tenancy"] = fields["tenantId"];
                }
                else
                {
                    fields["fingerprint"] = (fingerprint.Text ?? "").Trim();
                    fields["tenancy"] = (tenancy.Text ?? "").Trim();
                }
                if (fields.Values.Any(string.IsNullOrEmpty))
                {
                    ToastService.Error("请填写完整 API 配置");
                    return;
                }
                if (string.IsNullOrEmpty(selectedKey) || !File.Exists(selectedKey))
                {
                    ToastService.Error(isGcp ? "请选择 JSON 密钥文件" : "请选择私钥文件");
                    return;
                }
                try
                {
                    scaffold.SetLoading(true);
                    await service.SaveTenantAsync(fields, selectedKey).ConfigureAwait(true);
                    ToastService.Success("已保存");
                    onSaved();
                }
                catch (Exception ex)
                {
                    ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
                }
                finally { scaffold.SetLoading(false); }
            }));

        scaffold.SetToolbar(FormFieldFactory.Secondary("返回列表", (_, _) => onBack()));
        var scroll = new ScrollViewer
        {
            Content = new StackPanel
            {
                Margin = new Thickness(16),
                Children = { card }
            },
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
        scaffold.SetBody(scroll);
        Content = scaffold;
    }
}

// ─── 审计日志 ───────────────────────────────────────────────────────

public sealed class TenantAuditLogPage : UserControl
{
    private readonly TenantItem _tenant;
    private readonly TenantsService _service;
    private readonly PageScaffold _scaffold = new();
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly TextBox _start = FormFieldFactory.TextField();
    private readonly TextBox _end = FormFieldFactory.TextField();
    private string? _nextToken;
    private readonly List<TenantAuditLogEntry> _items = [];

    public TenantAuditLogPage(TenantItem tenant, Action onBack, TenantsService service)
    {
        _tenant = tenant;
        _service = service;
        var today = DateTime.Today.ToString("yyyy-MM-dd");
        _start.Text = today;
        _end.Text = today;
        _start.Width = 140;
        _end.Width = 140;

        _scaffold.Title = "审计日志 — " + tenant.DisplayName;
        _scaffold.Subtitle = (string.IsNullOrEmpty(tenant.Region) ? "—" : tenant.Region) + " · 近 90 天";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("返回列表", (_, _) => onBack()),
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync(false)));

        _grid.Columns.Add(ListPageHelper.Col("用户", nameof(TenantAuditLogEntry.UserName), 120));
        _grid.Columns.Add(ListPageHelper.Col("来源 IP", nameof(TenantAuditLogEntry.IpAddress), 120));
        _grid.Columns.Add(ListPageHelper.Col("事件", nameof(TenantAuditLogEntry.EventType), star: true));
        _grid.Columns.Add(ListPageHelper.Col("客户端", nameof(TenantAuditLogEntry.ClientEnv), 160));
        _grid.Columns.Add(ListPageHelper.Col("时间", nameof(TenantAuditLogEntry.EventTime), 150));
        _grid.Columns.Add(ListPageHelper.Col("状态", nameof(TenantAuditLogEntry.ResponseStatus), 72));

        var filter = ListPageHelper.TopBar(
            new TextBlock { Text = "开始", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) },
            _start,
            new TextBlock { Text = "结束", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 6, 0) },
            _end,
            FormFieldFactory.Primary("查询", async (_, _) => await LoadAsync(false)),
            FormFieldFactory.Secondary("加载更多", async (_, _) => await LoadAsync(true)));

        var root = new DockPanel();
        DockPanel.SetDock(filter, Dock.Top);
        root.Children.Add(filter);
        root.Children.Add(_grid);
        _scaffold.SetBody(root);
        Content = _scaffold;
        Loaded += async (_, _) => await LoadAsync(false);
    }

    private async Task LoadAsync(bool append)
    {
        if (append && string.IsNullOrEmpty(_nextToken))
        {
            ToastService.Info("没有更多了");
            return;
        }
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var page = await _service.AuditLogsAsync(
                _tenant.Id,
                (_start.Text ?? "").Trim(),
                (_end.Text ?? "").Trim(),
                append ? _nextToken : null).ConfigureAwait(true);
            if (!append) _items.Clear();
            _items.AddRange(page.Items);
            _nextToken = page.NextPageToken;
            _grid.ItemsSource = null;
            _grid.ItemsSource = _items.ToList();
            _scaffold.Subtitle = $"{_items.Count} 条" +
                                 (string.IsNullOrEmpty(_nextToken) ? "" : " · 可加载更多");
        });
    }
}

// ─── 流量监控 ───────────────────────────────────────────────────────

public sealed class TenantTrafficPage : UserControl
{
    private readonly TenantItem _tenant;
    private readonly TenantsService _service;
    private readonly PageScaffold _scaffold = new();
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly ComboBox _regionBox = new() { MinWidth = 220, Padding = new Thickness(8, 6, 8, 6) };
    private readonly ComboBox _preset = FormFieldFactory.Combo(new[] { "今天", "本月", "自定义" }, "本月");
    private readonly TextBox _start = FormFieldFactory.TextField();
    private readonly TextBox _end = FormFieldFactory.TextField();
    private readonly TextBlock _stats = new()
    {
        Margin = new Thickness(16, 8, 16, 8),
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
    };
    private List<TenantRegionOption> _regions = [];
    private double _thresholdGb = 10240;

    public TenantTrafficPage(TenantItem tenant, Action onBack, TenantsService service)
    {
        _tenant = tenant;
        _service = service;
        ApplyPreset("本月");
        _start.Width = 120;
        _end.Width = 120;

        _scaffold.Title = "实例流量监控 — " + tenant.DisplayName;
        _scaffold.Subtitle = "POST /monitor/api/instances/traffic";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("返回列表", (_, _) => onBack()));

        _grid.Columns.Add(ListPageHelper.Col("实例", nameof(TenantTrafficRow.Title), star: true));
        _grid.Columns.Add(ListPageHelper.Col("区域", nameof(TenantTrafficRow.Region), 100));
        _grid.Columns.Add(ListPageHelper.Col("IP", nameof(TenantTrafficRow.PublicIp), 120));
        _grid.Columns.Add(ListPageHelper.Col("时间点", nameof(TenantTrafficRow.TimePoint), 140));
        _grid.Columns.Add(ListPageHelper.Col("入站", nameof(TenantTrafficRow.IngressGb), 90));
        _grid.Columns.Add(ListPageHelper.Col("出站", nameof(TenantTrafficRow.EgressGb), 90));
        _grid.Columns.Add(ListPageHelper.Col("合计", nameof(TenantTrafficRow.TotalGb), 90));

        _preset.SelectionChanged += (_, _) =>
        {
            if (_preset.SelectedItem is string s) ApplyPreset(s);
        };

        var filter = ListPageHelper.TopBar(
            new TextBlock { Text = "区域", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) },
            _regionBox,
            new TextBlock { Text = "范围", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 6, 0) },
            _preset,
            _start,
            new TextBlock { Text = "至", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 6, 0) },
            _end,
            FormFieldFactory.Primary("查询", async (_, _) => await QueryAsync()));

        var top = new StackPanel();
        top.Children.Add(filter);
        top.Children.Add(_stats);

        var root = new DockPanel();
        DockPanel.SetDock(top, Dock.Top);
        root.Children.Add(top);
        root.Children.Add(_grid);
        _scaffold.SetBody(root);
        Content = _scaffold;
        Loaded += async (_, _) =>
        {
            await LoadRegionsAsync();
            await QueryAsync();
        };
    }

    private void ApplyPreset(string preset)
    {
        var today = DateTime.Today;
        _end.Text = today.ToString("yyyy-MM-dd");
        if (preset == "今天")
            _start.Text = today.ToString("yyyy-MM-dd");
        else if (preset == "本月")
            _start.Text = new DateTime(today.Year, today.Month, 1).ToString("yyyy-MM-dd");
        // 自定义：保留用户输入
    }

    private async Task LoadRegionsAsync()
    {
        try
        {
            _regions = await _service.ListRegionsAsync(_tenant.Id).ConfigureAwait(true);
            var labels = _regions.Select(r =>
            {
                var s = string.IsNullOrEmpty(r.Region) ? r.DisplayLabel : r.Region;
                if (r.IsHomeRegion) s += " · 主";
                return s;
            }).ToList();
            if (labels.Count == 0)
                labels = new List<string> { _tenant.DisplayName + "（当前）" };
            _regionBox.ItemsSource = labels;
            _regionBox.SelectedIndex = 0;
            _thresholdGb = await _service.MonitorTrafficThresholdAsync(_tenant.Id).ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            ToastService.Error(ex.Message);
            _regions = [];
            _regionBox.ItemsSource = new[] { _tenant.DisplayName };
            _regionBox.SelectedIndex = 0;
        }
    }

    private async Task QueryAsync()
    {
        var start = (_start.Text ?? "").Trim();
        var end = (_end.Text ?? "").Trim();
        if (string.IsNullOrEmpty(start) || string.IsNullOrEmpty(end))
        {
            ToastService.Error("请选择时间范围");
            return;
        }
        string tid;
        if (_regionBox.SelectedIndex >= 0 && _regionBox.SelectedIndex < _regions.Count)
            tid = _regions[_regionBox.SelectedIndex].Id;
        else
            tid = _tenant.Id.ToString();

        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var rows = await _service.InstanceTrafficAsync(new[] { tid }, start, end).ConfigureAwait(true);
            _grid.ItemsSource = rows;
            var ingress = rows.Sum(r => r.IngressBytes);
            var egress = rows.Sum(r => r.EgressBytes);
            var total = ingress + egress;
            _stats.Text =
                $"样本 {rows.Count} · 入站 {ingress / 1_073_741_824.0:F2} GB · 出站 {egress / 1_073_741_824.0:F2} GB · 合计 {total / 1_073_741_824.0:F2} GB · 阈值 {_thresholdGb:F0} GB";
        });
    }
}

// ─── 区域订阅 ───────────────────────────────────────────────────────

public sealed class TenantRegionSubPage : UserControl
{
    private readonly TenantItem _tenant;
    private readonly TenantsService _service;
    private readonly PageScaffold _scaffold = new();
    private readonly TextBlock _summary = new()
    {
        Margin = new Thickness(16, 10, 16, 10),
        FontSize = 13,
        Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush")
    };
    private readonly DataGrid _subGrid = ListPageHelper.CreateGrid();
    private readonly DataGrid _unsubGrid = ListPageHelper.CreateGrid();
    private readonly TabControl _tabs = new();
    private List<TenantUnsubscribedRegion> _unsub = [];

    public TenantRegionSubPage(TenantItem tenant, Action onBack, TenantsService service)
    {
        _tenant = tenant;
        _service = service;
        _scaffold.Title = "区域订阅 — " + tenant.DisplayName;
        _scaffold.Subtitle = tenant.Region;
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("返回列表", (_, _) => onBack()),
            FormFieldFactory.Secondary("刷新", async (_, _) => await ReloadAsync()),
            FormFieldFactory.Secondary("全选未订阅", (_, _) =>
            {
                foreach (var r in _unsub) r.IsSelected = true;
                _unsubGrid.ItemsSource = null;
                _unsubGrid.ItemsSource = _unsub;
            }),
            FormFieldFactory.Primary("订阅所选", async (_, _) => await SubscribeAsync()));

        _subGrid.Columns.Add(ListPageHelper.Col("区域", nameof(TenantSubscribedRegion.Display), star: true));
        _subGrid.Columns.Add(ListPageHelper.Col("Key", nameof(TenantSubscribedRegion.RegionKey), 160));
        _subGrid.Columns.Add(ListPageHelper.Col("状态", nameof(TenantSubscribedRegion.Status), 100));
        _subGrid.Columns.Add(new DataGridTextColumn
        {
            Header = "主区域",
            Binding = new System.Windows.Data.Binding(nameof(TenantSubscribedRegion.IsHomeRegion)),
            Width = 80
        });

        _unsubGrid.Columns.Add(new DataGridCheckBoxColumn
        {
            Header = "选",
            Binding = new System.Windows.Data.Binding(nameof(TenantUnsubscribedRegion.IsSelected)),
            Width = 50
        });
        _unsubGrid.Columns.Add(ListPageHelper.Col("区域", nameof(TenantUnsubscribedRegion.Display), star: true));
        _unsubGrid.Columns.Add(ListPageHelper.Col("Key", nameof(TenantUnsubscribedRegion.Key), 160));
        _unsubGrid.IsReadOnly = false;

        _tabs.Items.Add(new TabItem { Header = "已订阅", Content = _subGrid });
        _tabs.Items.Add(new TabItem { Header = "未订阅", Content = _unsubGrid });

        var root = new DockPanel();
        DockPanel.SetDock(_summary, Dock.Top);
        root.Children.Add(_summary);
        root.Children.Add(_tabs);
        _scaffold.SetBody(root);
        Content = _scaffold;
        Loaded += async (_, _) => await ReloadAsync();
    }

    private async Task ReloadAsync()
    {
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var (total, subN, unsubN) = await _service.RegionSummaryAsync(_tenant.Id).ConfigureAwait(true);
            var sub = await _service.SubscribedRegionsAsync(_tenant.Id).ConfigureAwait(true);
            _unsub = await _service.UnsubscribedRegionsAsync(_tenant.Id).ConfigureAwait(true);
            if (subN == 0 && sub.Count > 0) subN = sub.Count;
            if (unsubN == 0 && _unsub.Count > 0) unsubN = _unsub.Count;
            if (total == 0) total = subN + unsubN;
            _summary.Text = $"全部区域 {total} · 已订阅 {subN} · 未订阅 {unsubN}";
            _subGrid.ItemsSource = sub;
            _unsubGrid.ItemsSource = _unsub;
            if (_tabs.Items[0] is TabItem t0) t0.Header = $"已订阅 ({sub.Count})";
            if (_tabs.Items[1] is TabItem t1) t1.Header = $"未订阅 ({_unsub.Count})";
        });
    }

    private async Task SubscribeAsync()
    {
        var keys = _unsub.Where(r => r.IsSelected).Select(r => r.Key).Where(k => !string.IsNullOrEmpty(k)).ToList();
        if (keys.Count == 0)
        {
            ToastService.Info("请先勾选要订阅的区域");
            return;
        }
        try
        {
            _scaffold.SetLoading(true);
            var msg = await _service.SubscribeRegionsAsync(_tenant.Id, keys).ConfigureAwait(true);
            ToastService.Success(msg);
            await ReloadAsync();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
            _scaffold.SetLoading(false);
        }
    }
}

// ─── 开机创建 ─────────────────────────────────────────────────────────

public sealed class TenantBootCreatePage : UserControl
{
    private readonly TenantItem _tenant;
    private readonly Action _onBack;
    private readonly TenantsService _service;
    private readonly PageScaffold _scaffold = new();
    private readonly ComboBox _regionBox = new() { MinWidth = 220, Padding = new Thickness(8, 6, 8, 6) };
    private readonly ComboBox _archBox = FormFieldFactory.Combo(new[] { "ARM", "AMD", "X86" }, "ARM");
    private readonly TextBox _ocpu = FormFieldFactory.TextField("1");
    private readonly TextBox _memory = FormFieldFactory.TextField("6");
    private readonly TextBox _disk = FormFieldFactory.TextField("50");
    private readonly TextBox _count = FormFieldFactory.TextField("1");
    private readonly TextBox _loop = FormFieldFactory.TextField("60");
    private readonly TextBox _password = FormFieldFactory.TextField(RandomPassword());
    private readonly ComboBox _osBox = new() { MinWidth = 180, Padding = new Thickness(8, 6, 8, 6) };
    private readonly ComboBox _verBox = new() { MinWidth = 180, Padding = new Thickness(8, 6, 8, 6) };
    private List<TenantRegionOption> _regions = [];
    private List<TenantImageInfo> _images = [];
    private string _imageId = "";

    public TenantBootCreatePage(TenantItem tenant, Action onBack, TenantsService service)
    {
        _tenant = tenant;
        _onBack = onBack;
        _service = service;

        _scaffold.Title = "开机创建 — " + tenant.DisplayName;
        _scaffold.Subtitle = "POST /tenants/boot/save";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("返回列表", (_, _) => _onBack()),
            FormFieldFactory.Primary("创建任务", async (_, _) => await SubmitAsync()));

        var archCard = new ModuleSettingsCard(
            "架构与区域", "选择 CPU 架构与部署区域", "⚙",
            Color.FromRgb(0x4A, 0x9E, 0xFF), false, 280);
        archCard.SetBody(
            FormFieldFactory.Labeled("架构", _archBox),
            FormFieldFactory.Labeled("部署区域", _regionBox));

        var cfgCard = new ModuleSettingsCard(
            "规格配置", "OCPU / 内存 / 磁盘 / 数量", "📦",
            Color.FromRgb(0x9B, 0x59, 0xB6), false, 280);
        cfgCard.SetBody(
            FormFieldFactory.Labeled("OCPU", _ocpu),
            FormFieldFactory.Labeled("内存 GB", _memory),
            FormFieldFactory.Labeled("磁盘 GB", _disk),
            FormFieldFactory.Labeled("实例数量", _count),
            FormFieldFactory.Labeled("循环间隔(秒)", _loop));

        var imgCard = new ModuleSettingsCard(
            "系统镜像", "操作系统与 root 密码", "💿",
            Color.FromRgb(0x1A, 0xBC, 0x9C), false, 280);
        imgCard.SetBody(
            FormFieldFactory.Labeled("操作系统", _osBox),
            FormFieldFactory.Labeled("版本", _verBox),
            FormFieldFactory.Labeled("Root 密码", _password));
        imgCard.SetFooter(FormFieldFactory.Secondary("刷新镜像", async (_, _) => await LoadImagesAsync()));

        _archBox.SelectionChanged += async (_, _) => await LoadImagesAsync();
        _regionBox.SelectionChanged += async (_, _) => await LoadImagesAsync();
        _osBox.SelectionChanged += (_, _) => ApplyOs();
        _verBox.SelectionChanged += (_, _) => ApplyVersion();

        var row1 = new EqualHeightCardRow(archCard, cfgCard, minHeight: 280);
        var stack = new StackPanel { Margin = new Thickness(16) };
        stack.Children.Add(row1);
        stack.Children.Add(imgCard);
        var scroll = new ScrollViewer
        {
            Content = stack,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
        _scaffold.SetBody(scroll);
        Content = _scaffold;
        Loaded += async (_, _) =>
        {
            await LoadRegionsAsync();
            await LoadImagesAsync();
        };
    }

    private async Task LoadRegionsAsync()
    {
        try
        {
            _regions = await _service.ListRegionsAsync(_tenant.Id).ConfigureAwait(true);
            if (_regions.Count == 0)
            {
                _regions =
                [
                    new TenantRegionOption
                    {
                        Id = _tenant.Id.ToString(),
                        Region = _tenant.Region,
                        UserName = _tenant.DisplayName
                    }
                ];
            }
            _regionBox.ItemsSource = _regions.Select(r =>
                string.IsNullOrEmpty(r.Region) ? r.DisplayLabel : r.Region + " · " + r.DisplayLabel).ToList();
            _regionBox.SelectedIndex = 0;
        }
        catch (Exception ex) { ToastService.Error(ex.Message); }
    }

    private long SelectedTenantId()
    {
        if (_regionBox.SelectedIndex >= 0 && _regionBox.SelectedIndex < _regions.Count
            && long.TryParse(_regions[_regionBox.SelectedIndex].Id, out var id))
            return id;
        return _tenant.Id;
    }

    private async Task LoadImagesAsync()
    {
        var arch = _archBox.SelectedItem as string ?? "ARM";
        try
        {
            _scaffold.SetLoading(true);
            _images = await _service.QuerySystemImagesAsync(SelectedTenantId(), arch).ConfigureAwait(true);
            var oss = _images.Select(i => i.OperatingSystem).Where(s => !string.IsNullOrEmpty(s))
                .Distinct().OrderBy(s => s).ToList();
            _osBox.ItemsSource = oss;
            if (oss.Count > 0)
            {
                _osBox.SelectedIndex = 0;
                ApplyOs();
            }
            else
            {
                _verBox.ItemsSource = null;
                _imageId = "";
            }
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
            _images = [];
        }
        finally { _scaffold.SetLoading(false); }
    }

    private void ApplyOs()
    {
        var os = _osBox.SelectedItem as string ?? "";
        var vers = _images.Where(i => i.OperatingSystem == os).ToList();
        _verBox.ItemsSource = vers.Select(v => v.OperatingSystemVersion).ToList();
        if (vers.Count > 0)
        {
            _verBox.SelectedIndex = 0;
            _imageId = vers[0].ImageId;
        }
        else
        {
            _imageId = "";
        }
    }

    private void ApplyVersion()
    {
        var os = _osBox.SelectedItem as string ?? "";
        var ver = _verBox.SelectedItem as string ?? "";
        var hit = _images.FirstOrDefault(i => i.OperatingSystem == os && i.OperatingSystemVersion == ver);
        _imageId = hit?.ImageId ?? "";
    }

    private async Task SubmitAsync()
    {
        if (string.IsNullOrEmpty(_imageId))
        {
            ToastService.Error("请选择系统镜像");
            return;
        }
        var fields = new Dictionary<string, string>
        {
            ["tenantId"] = SelectedTenantId().ToString(),
            ["ocpu"] = (_ocpu.Text ?? "1").Trim(),
            ["memory"] = (_memory.Text ?? "6").Trim(),
            ["disk"] = (_disk.Text ?? "50").Trim(),
            ["architecture"] = _archBox.SelectedItem as string ?? "ARM",
            ["loopTime"] = (_loop.Text ?? "60").Trim(),
            ["instanceCount"] = (_count.Text ?? "1").Trim(),
            ["rootPassword"] = string.IsNullOrWhiteSpace(_password.Text) ? RandomPassword() : _password.Text.Trim(),
            ["imageId"] = _imageId,
            ["operatingSystem"] = _osBox.SelectedItem as string ?? "",
            ["operatingSystemVersion"] = _verBox.SelectedItem as string ?? "",
            ["dayGap"] = "",
            ["notifyFlag"] = "NO",
            ["cloudType"] = "1"
        };
        try
        {
            _scaffold.SetLoading(true);
            await _service.SaveBootInstanceAsync(fields).ConfigureAwait(true);
            ToastService.Success("开机任务已创建");
            _onBack();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally { _scaffold.SetLoading(false); }
    }

    private static string RandomPassword()
    {
        const string chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#";
        var rnd = Random.Shared;
        return new string(Enumerable.Range(0, 14).Select(_ => chars[rnd.Next(chars.Length)]).ToArray());
    }
}

