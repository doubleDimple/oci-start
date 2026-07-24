using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;
using OciStart.Features.Shared;

namespace OciStart.Features.Instances;

/// <summary>实例列表 + 整页 SSH/控制台/网络（对齐 Mac InstancesView）.</summary>
public sealed class InstancesView : UserControl
{
    private readonly InstancesService _service = new();
    private readonly Grid _host = new();

    private readonly PageScaffold _scaffold = new();
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly ComboBox _parentBox = new() { MinWidth = 180, Padding = new Thickness(8, 6, 8, 6) };
    private readonly ComboBox _regionBox = new() { MinWidth = 180, Padding = new Thickness(8, 6, 8, 6) };
    private readonly TextBlock _pageInfo = ListPageHelper.PageInfo();
    private readonly TextBlock _summary = new()
    {
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(12, 0, 0, 0)
    };

    private List<TenantRegionOption> _parents = [];
    private List<TenantRegionOption> _regions = [];
    private string? _filterTenantId;
    private int _page;
    private int _totalPages = 1;
    private const int PageSize = 10;
    private bool _namesHidden = true;
    private List<InstanceItem> _rows = [];

    public InstancesView()
    {
        Content = _host;
        ShowList();
        Loaded += async (_, _) =>
        {
            await LoadParentsAsync();
            await LoadAsync();
        };
    }

    private void ShowList()
    {
        _host.Children.Clear();
        BuildListUi();
        _host.Children.Add(_scaffold);
    }

    private void BuildListUi()
    {
        _scaffold.Title = "实例列表";
        _scaffold.Subtitle = "OCI 实例管理";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary(_namesHidden ? "显示名称" : "隐藏名称", async (_, _) =>
            {
                _namesHidden = !_namesHidden;
                await LoadAsync();
            }),
            FormFieldFactory.Secondary("导出", async (_, _) => await ExportAsync()),
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()),
            FormFieldFactory.Secondary("上一页", async (_, _) => { if (_page > 0) { _page--; await LoadAsync(); } }),
            FormFieldFactory.Secondary("下一页", async (_, _) => { if (_page + 1 < _totalPages) { _page++; await LoadAsync(); } }));

        if (_grid.Columns.Count == 0)
        {
            _grid.Columns.Add(ListPageHelper.Col("名称", nameof(InstanceItem.DisplayName), star: true));
            _grid.Columns.Add(ListPageHelper.Col("状态", nameof(InstanceItem.StateLabel), 80));
            _grid.Columns.Add(ListPageHelper.Col("公网 IP", nameof(InstanceItem.PublicIps), 120));
            _grid.Columns.Add(ListPageHelper.Col("规格", nameof(InstanceItem.CpuAndMem), 80));
            _grid.Columns.Add(ListPageHelper.Col("Shape", nameof(InstanceItem.Shape), 140));
            _grid.Columns.Add(ListPageHelper.Col("区域", nameof(InstanceItem.RegionName), 120));
            _grid.Columns.Add(ListPageHelper.Col("租户", nameof(InstanceItem.TenancyDisplay), 100));
            _grid.Columns.Add(ListPageHelper.Col("备注", nameof(InstanceItem.Remark), 120));
        }

        _parentBox.SelectionChanged -= OnParentChanged;
        _parentBox.SelectionChanged += OnParentChanged;

        var filter = ListPageHelper.TopBar(
            new TextBlock { Text = "租户", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) },
            _parentBox,
            new TextBlock { Text = "区域", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 6, 0) },
            _regionBox,
            FormFieldFactory.Primary("查询", async (_, _) => await ApplyFilterAsync()),
            FormFieldFactory.Secondary("重置", async (_, _) =>
            {
                _parentBox.SelectedIndex = -1;
                _regionBox.ItemsSource = null;
                _regions = [];
                _filterTenantId = null;
                _page = 0;
                await LoadAsync();
            }),
            _summary);

        // 扁平操作条（对齐 Mac：不拆电源/配置分组）
        var actions = ListPageHelper.TopBar(
            FormFieldFactory.Primary("启动", async (_, _) => await Act(i => _service.StartAsync(i.Id))),
            FormFieldFactory.Secondary("停止", async (_, _) => await Act(i => _service.StopAsync(i.Id), confirm: true)),
            FormFieldFactory.Secondary("SSH", (_, _) => OpenSub(i => new InstanceSSHView(i, ShowList))),
            FormFieldFactory.Secondary("控制台", (_, _) => OpenSub(i => new InstanceConsoleView(i, ShowList))),
            FormFieldFactory.Secondary("网络", (_, _) => OpenSub(i => new InstanceVnicView(i, ShowList))),
            FormFieldFactory.Secondary("改名", async (_, _) => await RenameAsync()),
            FormFieldFactory.Secondary("备注", async (_, _) => await RemarkAsync()),
            FormFieldFactory.Secondary("改配置", async (_, _) => await UpdateConfigAsync()),
            FormFieldFactory.Secondary("引导卷", async (_, _) => await UpdateBootAsync()),
            FormFieldFactory.Secondary("VPU", async (_, _) => await UpdateVpuAsync()),
            FormFieldFactory.Secondary("重装系统", async (_, _) => await OsResetAsync()),
            FormFieldFactory.Secondary("换 IP", async (_, _) => await ChangeIpAsync()),
            FormFieldFactory.Secondary("IPv6", async (_, _) => await Act(i => _service.EnableIpv6Async(i.Id))),
            FormFieldFactory.Secondary("终止…", async (_, _) => await TerminateAsync()),
            FormFieldFactory.Secondary("删本地", async (_, _) => await Act(i => _service.DeleteLocalRecordAsync(i.Id), confirm: true)),
            _pageInfo);

        var top = new StackPanel();
        top.Children.Add(filter);
        top.Children.Add(actions);

        var root = new DockPanel();
        DockPanel.SetDock(top, Dock.Top);
        root.Children.Add(top);
        root.Children.Add(_grid);
        _scaffold.SetBody(root);
    }

    private void OnParentChanged(object sender, SelectionChangedEventArgs e) => _ = LoadRegionsAsync();

    private async Task LoadParentsAsync()
    {
        try
        {
            _parents = (await _service.ListParentTenantsAsync().ConfigureAwait(true))
                .OrderBy(p => p.UserName, StringComparer.OrdinalIgnoreCase).ToList();
            _parentBox.ItemsSource = _parents.Select(p => p.DisplayLabel).ToList();
        }
        catch { _parents = []; }
    }

    private async Task LoadRegionsAsync()
    {
        _regions = [];
        _regionBox.ItemsSource = null;
        if (_parentBox.SelectedIndex < 0 || _parentBox.SelectedIndex >= _parents.Count) return;
        try
        {
            var pid = _parents[_parentBox.SelectedIndex].Id;
            _regions = (await _service.ListRegionsAsync(pid).ConfigureAwait(true))
                .OrderBy(r => r.Region, StringComparer.OrdinalIgnoreCase).ToList();
            _regionBox.ItemsSource = _regions.Select(r =>
            {
                var s = string.IsNullOrEmpty(r.Region) ? r.DisplayLabel : r.Region;
                if (r.IsHomeRegion) s += " · 主";
                return s;
            }).ToList();
            if (_regions.Count == 1) _regionBox.SelectedIndex = 0;
        }
        catch (Exception ex) { ToastService.Error(ex.Message); }
    }

    private async Task ApplyFilterAsync()
    {
        if (_regionBox.SelectedIndex < 0 || _regionBox.SelectedIndex >= _regions.Count)
        {
            ToastService.Error("请选择区域后再查询");
            return;
        }
        _filterTenantId = _regions[_regionBox.SelectedIndex].Id;
        _page = 0;
        await LoadAsync();
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var resp = await _service.ListAsync(_page, PageSize, _filterTenantId).ConfigureAwait(true);
            _rows = resp.Content;
            foreach (var r in _rows)
            {
                var tn = r.TenancyName;
                if (_namesHidden && !string.IsNullOrEmpty(tn) && tn.Length > 2)
                    r.TenancyDisplay = $"{tn[0]}***{tn[^1]}";
                else
                    r.TenancyDisplay = string.IsNullOrEmpty(tn) ? "—" : tn;
            }
            _totalPages = Math.Max(1, resp.TotalPages);
            _grid.ItemsSource = null;
            _grid.ItemsSource = _rows;
            _pageInfo.Text = $"第 {_page + 1}/{_totalPages} 页 · 共 {resp.TotalElements}";
            var run = _rows.Count(r => r.IsRunning);
            var stop = _rows.Count(r => r.IsStopped);
            _summary.Text = $"本页 {_rows.Count} · 运行 {run} · 停止 {stop}";
            _scaffold.Subtitle = _filterTenantId != null
                ? $"已筛选 · 共 {resp.TotalElements} 台"
                : $"OCI 实例管理 · 共 {resp.TotalElements} 台";
        });

    private InstanceItem? Selected() => _grid.SelectedItem as InstanceItem;

    private void OpenSub(Func<InstanceItem, UserControl> factory)
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        _host.Children.Clear();
        _host.Children.Add(factory(item));
    }

    private async Task Act(Func<InstanceItem, Task<string>> action, bool confirm = false)
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        if (confirm && MessageBox.Show($"确认对「{item.DisplayName}」执行操作？", "确认",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
            return;
        try
        {
            var msg = await action(item).ConfigureAwait(true);
            ToastService.Success(msg);
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task RenameAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        var name = Prompt("修改名称", item.DisplayName);
        if (name == null) return;
        await Act(_ => _service.UpdateNameAsync(item.Id, name));
    }

    private async Task RemarkAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        var remark = Prompt("修改备注", item.Remark);
        if (remark == null) return;
        await Act(_ => _service.UpdateRemarkAsync(item.Id, remark));
    }

    private async Task TerminateAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        try
        {
            await _service.SendTerminateCodeAsync(item.Id).ConfigureAwait(true);
            var code = Prompt("终止实例", "验证码已发送，请输入验证码", "");
            if (string.IsNullOrWhiteSpace(code)) return;
            var msg = await _service.TerminateAsync(item.Id, code!).ConfigureAwait(true);
            ToastService.Success(msg);
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task UpdateConfigAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        var cpuDef = item.Ocpus > 0 ? item.Ocpus.ToString() : "1";
        var memDef = item.MemoryInGBs > 0 ? item.MemoryInGBs.ToString() : "6";
        var fields = PromptFields("修改配置",
            ("OCPU (1–24)", cpuDef),
            ("内存 GB (1–256)", memDef));
        if (fields == null) return;
        if (!int.TryParse(fields[0], out var cpu) || cpu is < 1 or > 24)
        {
            ToastService.Error("CPU 须为 1–24");
            return;
        }
        if (!int.TryParse(fields[1], out var mem) || mem is < 1 or > 256)
        {
            ToastService.Error("内存须为 1–256 GB");
            return;
        }
        await Act(_ => _service.UpdateConfigAsync(item.Id, cpu, mem));
    }

    private async Task UpdateBootAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        var def = Math.Max(item.BootVolumeSizeInGBs, 50).ToString();
        var sizeStr = Prompt("扩容引导卷",
            $"当前 {item.BootVolumeSizeInGBs} GB · 仅支持扩容（≥47）", def);
        if (sizeStr == null) return;
        if (!long.TryParse(sizeStr, out var size) || size < 47)
        {
            ToastService.Error("引导卷不能小于 47GB");
            return;
        }
        if (size < item.BootVolumeSizeInGBs)
        {
            ToastService.Error("暂不支持缩小引导卷");
            return;
        }
        await Act(_ => _service.UpdateBootVolumeAsync(item.Id, size));
    }

    private async Task UpdateVpuAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        if (string.IsNullOrEmpty(item.BootVolumeId))
        {
            ToastService.Error("引导卷 ID 为空，无法更新 VPU");
            return;
        }
        _ = int.TryParse(item.VpusPerGb, out var cur);
        var snapped = (int)(Math.Round(cur / 10.0) * 10);
        if (snapped < 0) snapped = 0;
        if (snapped > 120) snapped = 120;
        var vpuStr = Prompt("修改 VPU", "VPU per GB（0–120，步长 10）", snapped.ToString());
        if (vpuStr == null) return;
        if (!int.TryParse(vpuStr, out var vpu) || vpu is < 0 or > 120 || vpu % 10 != 0)
        {
            ToastService.Error("VPU 须为 0–120 且为 10 的倍数");
            return;
        }
        await Act(_ => _service.UpdateVpuAsync(
            item.BootVolumeId, item.EffectiveTenantId, item.Id, vpu));
    }

    private async Task OsResetAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }

        var osBox = FormFieldFactory.Combo(
            InstanceDdOsOptions.All.Select(x => x.Title),
            "Debian 12");
        // select default debian|12
        for (var i = 0; i < InstanceDdOsOptions.All.Length; i++)
        {
            if (InstanceDdOsOptions.All[i].Id == "debian|12")
            {
                osBox.SelectedIndex = i;
                break;
            }
        }
        var pwdBox = FormFieldFactory.PasswordField();
        var ok = false;
        var win = new Window
        {
            Title = "系统重装 (QuickDD)",
            Width = 440,
            Height = 260,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null) win.Owner = Application.Current.MainWindow;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = $"实例：{item.DisplayName}\n将覆盖磁盘数据且不可恢复",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 0, 0, 12)
        });
        panel.Children.Add(FormFieldFactory.Labeled("目标系统", osBox));
        panel.Children.Add(new Border { Height = 8 });
        panel.Children.Add(FormFieldFactory.Labeled("新 root 密码", pwdBox));
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary("开始重装", (_, _) => { ok = true; win.Close(); }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        if (!ok) return;

        var pwd = pwdBox.Password ?? "";
        if (string.IsNullOrWhiteSpace(pwd))
        {
            ToastService.Error("请输入新 root 密码");
            return;
        }
        var idx = osBox.SelectedIndex;
        if (idx < 0 || idx >= InstanceDdOsOptions.All.Length)
        {
            ToastService.Error("请选择目标系统");
            return;
        }
        var osId = InstanceDdOsOptions.All[idx].Id;
        var parts = osId.Split('|', 2);
        var osType = parts[0];
        var osVersion = parts.Length > 1 ? parts[1] : "";

        if (MessageBox.Show(
                $"将重装 {item.DisplayName} 为 {osType} {osVersion}，磁盘数据会被覆盖，且不可恢复。是否继续？",
                "确认系统重装", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        // SSE 日志窗
        var logBox = new TextBox
        {
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            FontFamily = new FontFamily("Consolas, Cascadia Mono"),
            FontSize = 12,
            Background = Brushes.Black,
            Foreground = new SolidColorBrush(Color.FromRgb(0xC9, 0xD1, 0xD9)),
            Height = 320
        };
        logBox.AppendText($"开始系统重装…\r\n实例：{item.DisplayName}\r\n系统：{osType} {osVersion}\r\n");
        var logPanel = new DockPanel { Margin = new Thickness(12) };
        logPanel.Children.Add(logBox);
        var logWin = new Window
        {
            Title = "重装日志 — " + item.DisplayName,
            Width = 560,
            Height = 420,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush"),
            Content = logPanel
        };
        if (Application.Current.MainWindow != null) logWin.Owner = Application.Current.MainWindow;
        logWin.Show();

        try
        {
            await foreach (var (ev, data) in _service.StreamQuickDdAsync(item.Id, osType, osVersion, pwd)
                               .ConfigureAwait(true))
            {
                var line = ev switch
                {
                    "log" or "message" => data,
                    "success" => "✅ " + data,
                    "complete" => "—— " + data + " ——",
                    "error" => "❌ " + data,
                    _ => $"[{ev}] {data}"
                };
                if (string.IsNullOrEmpty(line)) continue;
                logBox.AppendText(line + "\r\n");
                logBox.ScrollToEnd();
            }
            logBox.AppendText("流已结束\r\n");
            ToastService.Success("重装任务流已结束");
        }
        catch (Exception ex)
        {
            var msg = ex is ApiError ae ? ae.Message : ex.Message;
            logBox.AppendText("❌ " + msg + "\r\n");
            ToastService.Error(msg);
        }
    }

    private async Task ExportAsync()
    {
        if (MessageBox.Show("将导出全部实例（可能含敏感信息），是否继续？", "导出",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;
        try
        {
            var (data, name) = await _service.ExportAsync().ConfigureAwait(true);
            var dlg = new SaveFileDialog
            {
                FileName = name ?? "instances.xlsx",
                Filter = "All|*.*"
            };
            if (dlg.ShowDialog() == true)
            {
                await File.WriteAllBytesAsync(dlg.FileName, data).ConfigureAwait(true);
                ToastService.Success("已导出");
            }
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task ChangeIpAsync()
    {
        var item = Selected();
        if (item == null) { ToastService.Info("请先选择实例"); return; }
        var ranges = PromptCidrRanges(item);
        if (ranges == null) return;
        try
        {
            var msg = await _service.ChangeSpecIpAsync(item.Id, ranges).ConfigureAwait(true);
            ToastService.Success(msg);
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    /// <summary>可选 CIDR 多行输入（对齐 Mac changeIp sheet）；取消返回 null，确定返回列表（可空=随机）.</summary>
    internal static List<string>? PromptCidrRanges(InstanceItem item)
    {
        var cidrBox = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MinHeight = 88,
            MaxHeight = 140,
            Style = (Style)Application.Current.FindResource("AppTextBox"),
            ToolTip = "例如 10.0.0.0/24，多段用换行或逗号分隔"
        };
        var ok = false;
        var win = new Window
        {
            Title = "更换公网 IP",
            Width = 440,
            Height = 300,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null) win.Owner = Application.Current.MainWindow;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = $"实例：{item.DisplayName}\n当前 IPv4：{(string.IsNullOrEmpty(item.PublicIps) ? "—" : item.PublicIps)}",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 0, 0, 12)
        });
        panel.Children.Add(FormFieldFactory.Labeled("目标 CIDR（可选，留空随机）", cidrBox));
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary("更换", (_, _) => { ok = true; win.Close(); }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        if (!ok) return null;
        return ParseCidrLines(cidrBox.Text);
    }

    internal static List<string> ParseCidrLines(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return [];
        return text
            .Split(new[] { '\r', '\n', ',', ';' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(s => s.Trim())
            .Where(s => s.Length > 0)
            .ToList();
    }

    private static string? Prompt(string title, string initial) => Prompt(title, "内容", initial);

    private static string? Prompt(string title, string label, string initial)
    {
        var fields = PromptFields(title, (label, initial));
        return fields?[0];
    }

    private static List<string>? PromptFields(string title, params (string Label, string Initial)[] fields)
    {
        var win = new Window
        {
            Title = title,
            Width = 400,
            Height = 120 + fields.Length * 56,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null) win.Owner = Application.Current.MainWindow;
        var boxes = new List<TextBox>();
        var ok = false;
        var panel = new StackPanel { Margin = new Thickness(16) };
        foreach (var (label, initial) in fields)
        {
            var box = FormFieldFactory.TextField(initial);
            boxes.Add(box);
            panel.Children.Add(new TextBlock
            {
                Text = label,
                Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
                Margin = new Thickness(0, 0, 0, 6)
            });
            panel.Children.Add(box);
            panel.Children.Add(new Border { Height = 8 });
        }
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 8, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary("确定", (_, _) => { ok = true; win.Close(); }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        if (!ok) return null;
        return boxes.Select(b => (b.Text ?? "").Trim()).ToList();
    }
}
