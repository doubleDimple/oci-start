using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Email;

public sealed class EmailRow
{
    public string Id { get; set; } = "";
    public string TenantId { get; set; } = "";
    public string Col1 { get; set; } = "";
    public string Col2 { get; set; } = "";
    public string Col3 { get; set; } = "";
    public string Col4 { get; set; } = "";
}

/// <summary>邮件管理 — 对齐 Mac：租户服务 / 收件人 / 发送记录 + 写操作.</summary>
public sealed class EmailView : UserControl
{
    private enum Section { Tenants, Contacts, Records }
    private enum TenantTab { Enabled, Disabled }

    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly TextBlock _pageInfo = ListPageHelper.PageInfo();
    private readonly TextBox _search = FormFieldFactory.TextField(watermark: "关键词");
    private readonly StackPanel _actionBar = new() { Orientation = Orientation.Horizontal };
    private Section _section = Section.Tenants;
    private TenantTab _tenantTab = TenantTab.Enabled;
    private int _page = 1;

    public EmailView()
    {
        _scaffold.Title = "邮件管理";
        _scaffold.Subtitle = "OCI Email Delivery · 租户服务 / 收件人 / 发送记录";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()),
            FormFieldFactory.Secondary("上一页", async (_, _) =>
            {
                if (_page > 1) { _page--; await LoadAsync(); }
            }),
            FormFieldFactory.Secondary("下一页", async (_, _) => { _page++; await LoadAsync(); }));

        var tabs = ListPageHelper.TopBar(
            TabBtn("租户服务", Section.Tenants),
            TabBtn("收件人", Section.Contacts),
            TabBtn("发送记录", Section.Records),
            _search,
            FormFieldFactory.Primary("查询", async (_, _) => { _page = 1; await LoadAsync(); }),
            _pageInfo);

        var body = new DockPanel();
        DockPanel.SetDock(_actionBar, Dock.Top);
        _actionBar.Margin = new Thickness(16, 0, 16, 8);
        body.Children.Add(_actionBar);
        body.Children.Add(_grid);

        Content = ListPageHelper.Wrap(_scaffold, tabs, body);
        RebuildActionBar();
        Loaded += async (_, _) => await LoadAsync();
    }

    private Button TabBtn(string title, Section sec)
    {
        return FormFieldFactory.Secondary(title, async (_, _) =>
        {
            _section = sec;
            _page = 1;
            RebuildActionBar();
            await LoadAsync();
        });
    }

    private void RebuildActionBar()
    {
        _actionBar.Children.Clear();
        switch (_section)
        {
            case Section.Tenants:
                _actionBar.Children.Add(FormFieldFactory.Secondary(
                    _tenantTab == TenantTab.Enabled ? "已启用 ✓" : "已启用",
                    async (_, _) =>
                    {
                        _tenantTab = TenantTab.Enabled;
                        _page = 1;
                        RebuildActionBar();
                        await LoadAsync();
                    }));
                _actionBar.Children.Add(FormFieldFactory.Secondary(
                    _tenantTab == TenantTab.Disabled ? "未启用 ✓" : "未启用",
                    async (_, _) =>
                    {
                        _tenantTab = TenantTab.Disabled;
                        _page = 1;
                        RebuildActionBar();
                        await LoadAsync();
                    }));
                if (_tenantTab == TenantTab.Enabled)
                {
                    _actionBar.Children.Add(FormFieldFactory.Secondary("禁用选中", async (_, _) => await DisableSelectedAsync()));
                }
                else
                {
                    _actionBar.Children.Add(FormFieldFactory.Primary("开启选中", async (_, _) => await EnableSelectedAsync()));
                }
                break;
            case Section.Contacts:
                _actionBar.Children.Add(FormFieldFactory.Primary("添加收件人", async (_, _) => await AddContactAsync()));
                _actionBar.Children.Add(FormFieldFactory.Secondary("删除选中", async (_, _) => await DeleteContactAsync()));
                break;
            default:
                _actionBar.Children.Add(FormFieldFactory.Primary("写信发送", async (_, _) => await ComposeSendAsync()));
                _actionBar.Children.Add(FormFieldFactory.Secondary("删除选中", async (_, _) => await DeleteRecordAsync()));
                _actionBar.Children.Add(FormFieldFactory.Secondary("清空全部", async (_, _) => await BatchDeleteRecordsAsync()));
                break;
        }
    }

    private void ConfigureColumns()
    {
        _grid.Columns.Clear();
        switch (_section)
        {
            case Section.Tenants:
                if (_tenantTab == TenantTab.Enabled)
                {
                    _grid.Columns.Add(ListPageHelper.Col("租户", nameof(EmailRow.Col1), star: true));
                    _grid.Columns.Add(ListPageHelper.Col("发件/域名", nameof(EmailRow.Col2), 200));
                    _grid.Columns.Add(ListPageHelper.Col("今日/限额", nameof(EmailRow.Col3), 100));
                    _grid.Columns.Add(ListPageHelper.Col("配置ID", nameof(EmailRow.Col4), 80));
                }
                else
                {
                    _grid.Columns.Add(ListPageHelper.Col("租户", nameof(EmailRow.Col1), star: true));
                    _grid.Columns.Add(ListPageHelper.Col("区域", nameof(EmailRow.Col2), 160));
                    _grid.Columns.Add(ListPageHelper.Col("租户ID", nameof(EmailRow.Col3), 100));
                    _grid.Columns.Add(ListPageHelper.Col("状态", nameof(EmailRow.Col4), 80));
                }
                break;
            case Section.Contacts:
                _grid.Columns.Add(ListPageHelper.Col("姓名", nameof(EmailRow.Col1), 140));
                _grid.Columns.Add(ListPageHelper.Col("邮箱", nameof(EmailRow.Col2), star: true));
                _grid.Columns.Add(ListPageHelper.Col("备注/时间", nameof(EmailRow.Col3), 160));
                _grid.Columns.Add(ListPageHelper.Col("ID", nameof(EmailRow.Col4), 80));
                break;
            default:
                _grid.Columns.Add(ListPageHelper.Col("主题", nameof(EmailRow.Col1), star: true));
                _grid.Columns.Add(ListPageHelper.Col("发件/租户", nameof(EmailRow.Col2), 160));
                _grid.Columns.Add(ListPageHelper.Col("收件统计", nameof(EmailRow.Col3), 100));
                _grid.Columns.Add(ListPageHelper.Col("时间", nameof(EmailRow.Col4), 150));
                break;
        }
    }

    private async Task LoadAsync()
    {
        ConfigureColumns();
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            switch (_section)
            {
                case Section.Tenants:
                    if (_tenantTab == TenantTab.Enabled)
                        await LoadEnabledTenantsAsync();
                    else
                        await LoadDisabledTenantsAsync();
                    break;
                case Section.Contacts:
                    await LoadContactsAsync();
                    break;
                default:
                    await LoadRecordsAsync();
                    break;
            }
        });
    }

    private async Task LoadEnabledTenantsAsync()
    {
        var raw = await _api.PostJsonAsync("/email/tenant/list", new
        {
            pageNum = _page,
            pageSize = 10,
            sort = "createdTime",
            order = "desc"
        }).ConfigureAwait(true);
        var (rows, page, pages, total) = JsonPage.Parse(raw);
        if (page > 0) _page = Math.Max(1, page);
        var kw = (_search.Text ?? "").Trim();
        var list = rows.Select(m => new EmailRow
        {
            Id = JsonPage.Pick(m, "id"),
            TenantId = JsonPage.Pick(m, "tenantId", "id"),
            Col1 = JsonPage.Pick(m, "tenantName", "userName", "defName", "tenancyName"),
            Col2 = FirstNonEmpty(
                JsonPage.Pick(m, "senderEmail"),
                JsonPage.Pick(m, "domainName", "emailDomain", "domain", "email")),
            Col3 = FormatUsage(m),
            Col4 = JsonPage.Pick(m, "id")
        }).ToList();
        if (!string.IsNullOrEmpty(kw))
        {
            list = list.Where(r =>
                r.Col1.Contains(kw, StringComparison.OrdinalIgnoreCase)
                || r.Col2.Contains(kw, StringComparison.OrdinalIgnoreCase)).ToList();
        }
        _grid.ItemsSource = list;
        _pageInfo.Text = $"已启用 · 第 {_page}/{Math.Max(1, pages)} · 共 {total}";
    }

    private async Task LoadDisabledTenantsAsync()
    {
        var q = new Dictionary<string, string>
        {
            ["page"] = Math.Max(0, _page - 1).ToString(),
            ["size"] = "10",
            ["cloudType"] = "1",
            ["emailEnable"] = "0"
        };
        var kw = (_search.Text ?? "").Trim();
        if (!string.IsNullOrEmpty(kw)) q["keyword"] = kw;
        var raw = await _api.GetJsonAsync("/tenants/list/json", q).ConfigureAwait(true);
        var (rows, _, pages, total) = JsonPage.Parse(raw);
        // 0-based API page; keep UI _page as 1-based

        _grid.ItemsSource = rows.Select(m => new EmailRow
        {
            Id = JsonPage.Pick(m, "id", "tenantId"),
            TenantId = JsonPage.Pick(m, "id", "tenantId"),
            Col1 = JsonPage.Pick(m, "userName", "tenantName", "defName", "tenancyName", "name"),
            Col2 = JsonPage.Pick(m, "region", "homeRegion", "regionName"),
            Col3 = JsonPage.Pick(m, "id", "tenantId"),
            Col4 = "未开启"
        }).ToList();
        _pageInfo.Text = $"未启用 · 第 {_page}/{Math.Max(1, pages)} · 共 {total}";
    }

    private async Task LoadContactsAsync()
    {
        var raw = await _api.PostJsonAsync("/email/receive/list", new
        {
            pageNum = _page,
            pageSize = 10,
            sort = "createTime",
            order = "desc",
            keyword = _search.Text ?? ""
        }).ConfigureAwait(true);
        var (rows, page, pages, total) = JsonPage.Parse(raw);
        if (page > 0) _page = Math.Max(1, page);
        _grid.ItemsSource = rows.Select(m => new EmailRow
        {
            Id = JsonPage.Pick(m, "id"),
            Col1 = JsonPage.Pick(m, "name", "remark", "note"),
            Col2 = JsonPage.Pick(m, "email", "address", "mail"),
            Col3 = JsonPage.Pick(m, "createTime", "createdTime", "remark", "note"),
            Col4 = JsonPage.Pick(m, "id")
        }).ToList();
        _pageInfo.Text = $"收件人 · 第 {_page}/{Math.Max(1, pages)} · 共 {total}";
    }

    private async Task LoadRecordsAsync()
    {
        var raw = await _api.PostJsonAsync("/email/body/list", new
        {
            pageNum = _page,
            pageSize = 10,
            sort = "createTime",
            order = "desc"
        }).ConfigureAwait(true);
        var (rows, page, pages, total) = JsonPage.Parse(raw);
        if (page > 0) _page = Math.Max(1, page);
        _grid.ItemsSource = rows.Select(m =>
        {
            var ok = JsonPage.Pick(m, "receiveSuccessTotal", "successTotal", "success");
            var fail = JsonPage.Pick(m, "receiveFailTotal", "failTotal", "fail");
            var totalRecv = JsonPage.Pick(m, "receiveTotal", "total");
            var stat = string.IsNullOrEmpty(ok) && string.IsNullOrEmpty(fail)
                ? totalRecv
                : $"✓{ok} ✗{fail}";
            return new EmailRow
            {
                Id = JsonPage.Pick(m, "id"),
                Col1 = FirstNonEmpty(JsonPage.Pick(m, "title", "subject"), "（无主题）"),
                Col2 = FirstNonEmpty(
                    JsonPage.Pick(m, "senderEmail"),
                    JsonPage.Pick(m, "tenantName", "userName")),
                Col3 = string.IsNullOrEmpty(stat) ? "—" : stat,
                Col4 = JsonPage.Pick(m, "createTime", "createdTime", "sendTime", "time")
            };
        }).ToList();
        _pageInfo.Text = $"发送 · 第 {_page}/{Math.Max(1, pages)} · 共 {total}";
    }

    // ── Write ops ──────────────────────────────────────────────

    private async Task EnableSelectedAsync()
    {
        if (_grid.SelectedItem is not EmailRow row)
        {
            ToastService.Info("请先选择未启用的租户");
            return;
        }
        if (!long.TryParse(row.TenantId, out var tenantId) || tenantId <= 0)
        {
            ToastService.Error("租户 ID 无效");
            return;
        }

        var domain = PromptDomain(row.Col1);
        if (domain == null) return;
        domain = domain.Trim();
        if (string.IsNullOrEmpty(domain))
        {
            ToastService.Error("请输入邮箱域名");
            return;
        }
        if (!Regex.IsMatch(domain,
                @"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(\.[a-zA-Z]{2,})$"))
        {
            ToastService.Error("域名格式错误，如 example.com");
            return;
        }

        try
        {
            _scaffold.SetLoading(true);
            var raw = await _api.PostJsonAsync("/tenants/email/enable", new
            {
                tenantId,
                emailDomain = domain
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "已开启邮件服务");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
            _tenantTab = TenantTab.Enabled;
            _page = 1;
            RebuildActionBar();
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

    private async Task DisableSelectedAsync()
    {
        if (_grid.SelectedItem is not EmailRow row)
        {
            ToastService.Info("请先选择已启用配置");
            return;
        }
        if (!long.TryParse(row.Id, out var configId) || configId <= 0)
        {
            ToastService.Error("配置 ID 无效");
            return;
        }
        if (MessageBox.Show(
                $"确定禁用「{row.Col1}」的邮件服务？相关配置将被清理。",
                "禁用邮件服务",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            _scaffold.SetLoading(true);
            var raw = await _api.PostJsonAsync("/email/disable", new { id = configId }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "已禁用");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
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

    private async Task AddContactAsync()
    {
        var result = PromptAddContact();
        if (result == null) return;
        var (name, email) = result.Value;
        if (string.IsNullOrEmpty(name) || string.IsNullOrEmpty(email))
        {
            ToastService.Error("请填写姓名与邮箱");
            return;
        }
        if (!email.Contains('@') || !email.Contains('.'))
        {
            ToastService.Error("邮箱格式不正确");
            return;
        }

        try
        {
            _scaffold.SetLoading(true);
            var raw = await _api.PostJsonAsync("/email/receive/add", new { name, email }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "已添加");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
            _page = 1;
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

    private async Task DeleteContactAsync()
    {
        if (_grid.SelectedItem is not EmailRow row)
        {
            ToastService.Info("请先选择收件人");
            return;
        }
        if (!long.TryParse(row.Id, out var id) || id <= 0)
        {
            ToastService.Error("收件人 ID 无效");
            return;
        }
        var label = string.IsNullOrEmpty(row.Col1) ? row.Col2 : $"{row.Col1}（{row.Col2}）";
        if (MessageBox.Show($"确定删除收件人 {label}？", "删除收件人",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            _scaffold.SetLoading(true);
            // Mac: POST `/email/receive/delete?id=`
            var raw = await _api.PostJsonAsync(
                $"/email/receive/delete?id={Uri.EscapeDataString(id.ToString())}",
                new { }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "已删除");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
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

    private async Task ComposeSendAsync()
    {
        // Load configs + contacts for compose dialog
        List<(string Id, string Label)> configs;
        List<(string Id, string Name, string Email)> contacts;
        try
        {
            _scaffold.SetLoading(true);
            var cfgRaw = await _api.PostJsonAsync("/email/tenant/list", new
            {
                pageNum = 1,
                pageSize = 100,
                sort = "createdTime",
                order = "desc"
            }).ConfigureAwait(true);
            var (cfgRows, _, _, _) = JsonPage.Parse(cfgRaw);
            configs = cfgRows.Select(m =>
            {
                var id = JsonPage.Pick(m, "id");
                var label = FirstNonEmpty(
                    JsonPage.Pick(m, "senderEmail"),
                    JsonPage.Pick(m, "domainName", "emailDomain"),
                    JsonPage.Pick(m, "tenantName", "userName"),
                    id);
                return (id, label);
            }).Where(x => !string.IsNullOrEmpty(x.id)).ToList();

            var cRaw = await _api.PostJsonAsync("/email/receive/list", new
            {
                pageNum = 1,
                pageSize = 100,
                sort = "createTime",
                order = "desc"
            }).ConfigureAwait(true);
            var (cRows, _, _, _) = JsonPage.Parse(cRaw);
            contacts = cRows.Select(m => (
                JsonPage.Pick(m, "id"),
                JsonPage.Pick(m, "name", "remark"),
                JsonPage.Pick(m, "email", "address", "mail")
            )).Where(x => !string.IsNullOrEmpty(x.Item1)).ToList();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
            return;
        }
        finally
        {
            _scaffold.SetLoading(false);
        }

        if (configs.Count == 0)
        {
            ToastService.Info("请先开启至少一个租户的邮件服务");
            return;
        }
        if (contacts.Count == 0)
        {
            ToastService.Info("请先添加收件人");
            return;
        }

        var form = PromptCompose(configs, contacts);
        if (form == null) return;

        try
        {
            _scaffold.SetLoading(true);
            if (!long.TryParse(form.Value.ConfigId, out var configId) || configId <= 0)
                throw ApiError.Server("发件配置无效");
            var receiveIds = form.Value.ReceiveIds
                .Select(s => long.TryParse(s, out var n) ? n : 0)
                .Where(n => n > 0)
                .ToArray();
            if (receiveIds.Length == 0) throw ApiError.Server("请至少选择一位收件人");

            var raw = await _api.PostJsonAsync("/email/send", new
            {
                title = form.Value.Title,
                content = form.Value.Content,
                tenantEmailConfigId = configId,
                emailReceiveIds = receiveIds
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "发送成功");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
            _section = Section.Records;
            _page = 1;
            RebuildActionBar();
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

    private async Task DeleteRecordAsync()
    {
        if (_grid.SelectedItem is not EmailRow row)
        {
            ToastService.Info("请先选择发送记录");
            return;
        }
        if (!long.TryParse(row.Id, out var id) || id <= 0)
        {
            ToastService.Error("记录 ID 无效");
            return;
        }
        if (MessageBox.Show($"确定删除「{row.Col1}」及其收件明细？", "删除发送记录",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            _scaffold.SetLoading(true);
            var raw = await _api.PostJsonAsync("/email/body/delete", new { id }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "已删除");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
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

    private async Task BatchDeleteRecordsAsync()
    {
        if (MessageBox.Show("确定删除全部邮件发送记录？此操作不可恢复。", "清空全部记录",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            _scaffold.SetLoading(true);
            var raw = await _api.PostJsonAsync("/email/body/batchDelete", new { }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "已清空");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
            _page = 1;
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

    // ── Dialogs ────────────────────────────────────────────────

    private static string? PromptDomain(string tenantName)
    {
        var win = NewDialog("开启邮件服务", 460, 200);
        var box = FormFieldFactory.TextField(watermark: "example.com");
        var ok = false;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = $"为「{tenantName}」配置发件域名",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 0, 0, 12)
        });
        panel.Children.Add(FormFieldFactory.Labeled("邮箱域名", box));
        panel.Children.Add(DialogButtons(win, () => ok = true));
        win.Content = panel;
        win.ShowDialog();
        return ok ? box.Text?.Trim() : null;
    }

    private static (string Name, string Email)? PromptAddContact()
    {
        var win = NewDialog("添加收件人", 420, 220);
        var nameBox = FormFieldFactory.TextField(watermark: "收件人姓名");
        var emailBox = FormFieldFactory.TextField(watermark: "name@example.com");
        var ok = false;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(FormFieldFactory.Labeled("姓名", nameBox));
        panel.Children.Add(FormFieldFactory.Labeled("邮箱地址", emailBox));
        panel.Children.Add(DialogButtons(win, () => ok = true));
        win.Content = panel;
        win.ShowDialog();
        if (!ok) return null;
        return (nameBox.Text?.Trim() ?? "", emailBox.Text?.Trim() ?? "");
    }

    private static (string Title, string Content, string ConfigId, List<string> ReceiveIds)? PromptCompose(
        List<(string Id, string Label)> configs,
        List<(string Id, string Name, string Email)> contacts)
    {
        var win = NewDialog("编写邮件", 560, 560);
        win.ResizeMode = ResizeMode.CanResize;
        var titleBox = FormFieldFactory.TextField(watermark: "邮件主题");
        var contentBox = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MinHeight = 100,
            MaxHeight = 140,
            Style = (Style)Application.Current.FindResource("AppTextBox")
        };
        var configBox = new ComboBox
        {
            MinWidth = 280,
            Padding = new Thickness(8, 6, 8, 6),
            ItemsSource = configs.Select(c => c.Label).ToList(),
            SelectedIndex = 0
        };

        var list = new ListBox
        {
            Height = 160,
            SelectionMode = SelectionMode.Multiple,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(1),
            BorderBrush = (Brush)Application.Current.FindResource("AppBorderBrush")
        };
        foreach (var c in contacts)
        {
            var label = string.IsNullOrEmpty(c.Name) ? c.Email : $"{c.Name}  <{c.Email}>";
            list.Items.Add(new ListBoxItem
            {
                Content = label,
                Tag = c.Id,
                Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush")
            });
        }

        var ok = false;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(FormFieldFactory.Labeled("主题", titleBox));
        panel.Children.Add(FormFieldFactory.Labeled("内容", contentBox));
        panel.Children.Add(FormFieldFactory.Labeled("发件租户", configBox));

        var recipHeader = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
        recipHeader.Children.Add(new TextBlock
        {
            Text = "收件人",
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
        });
        var btns = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        DockPanel.SetDock(btns, Dock.Right);
        btns.Children.Add(FormFieldFactory.Secondary("全选", (_, _) =>
        {
            list.SelectAll();
        }));
        btns.Children.Add(FormFieldFactory.Secondary("清空", (_, _) => list.UnselectAll()));
        recipHeader.Children.Add(btns);
        panel.Children.Add(recipHeader);
        panel.Children.Add(list);
        panel.Children.Add(DialogButtons(win, () => ok = true, "发送"));

        win.Content = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = panel
        };
        win.ShowDialog();
        if (!ok) return null;

        var title = titleBox.Text?.Trim() ?? "";
        var content = contentBox.Text?.Trim() ?? "";
        if (string.IsNullOrEmpty(title) || string.IsNullOrEmpty(content))
        {
            ToastService.Error("请填写主题与内容");
            return null;
        }
        var cfgIdx = configBox.SelectedIndex;
        if (cfgIdx < 0 || cfgIdx >= configs.Count)
        {
            ToastService.Error("请选择发件租户");
            return null;
        }
        var ids = new List<string>();
        foreach (var item in list.SelectedItems)
        {
            if (item is ListBoxItem li && li.Tag is string id)
                ids.Add(id);
        }
        if (ids.Count == 0)
        {
            ToastService.Error("请至少选择一位收件人");
            return null;
        }
        return (title, content, configs[cfgIdx].Id, ids);
    }

    private static Window NewDialog(string title, double w, double h)
    {
        var win = new Window
        {
            Title = title,
            Width = w,
            Height = h,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null)
            win.Owner = Application.Current.MainWindow;
        return win;
    }

    private static UIElement DialogButtons(Window win, Action onOk, string okText = "确定")
    {
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary(okText, (_, _) =>
        {
            onOk();
            win.Close();
        }));
        return buttons;
    }

    private static string FormatUsage(Dictionary<string, System.Text.Json.JsonElement> m)
    {
        var sent = JsonPage.Pick(m, "todaySentCount", "sentCount", "todaySent");
        var limit = JsonPage.Pick(m, "dailyEmailLimit", "dailyLimit", "limit");
        if (string.IsNullOrEmpty(sent) && string.IsNullOrEmpty(limit)) return "—";
        if (string.IsNullOrEmpty(limit)) return sent;
        if (string.IsNullOrEmpty(sent)) sent = "0";
        return $"{sent}/{limit}";
    }

    private static string FirstNonEmpty(params string[] values)
    {
        foreach (var v in values)
            if (!string.IsNullOrEmpty(v)) return v;
        return "";
    }
}
