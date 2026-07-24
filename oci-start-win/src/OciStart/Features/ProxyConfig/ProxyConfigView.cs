using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.ProxyConfig;

public sealed class ProxyRow
{
    public long Id { get; set; }
    public string Name { get; set; } = "";
    public string Type { get; set; } = "";
    public string Host { get; set; } = "";
    public string Port { get; set; } = "";
    public string Status { get; set; } = "";
    public string Force { get; set; } = "";
}

/// <summary>代理配置 — 列表 + 新建/保存（对齐 Mac ProxyConfig）.</summary>
public sealed class ProxyConfigView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly TextBlock _pageInfo = ListPageHelper.PageInfo();
    private int _page = 1;

    // form
    private readonly TextBox _name = FormFieldFactory.TextField(watermark: "自定义名");
    private readonly ComboBox _type = FormFieldFactory.Combo(new[] { "HTTP", "SOCKS5", "HTTPS" }, "HTTP");
    private readonly TextBox _host = FormFieldFactory.TextField(watermark: "主机");
    private readonly TextBox _port = FormFieldFactory.TextField("1080");
    private readonly TextBox _user = FormFieldFactory.TextField(watermark: "用户名可选");
    private readonly PasswordBox _pass = FormFieldFactory.PasswordField();
    private readonly CheckBox _force = new() { Content = "强制代理", Foreground = Brushes.White };
    private long? _editId;

    public ProxyConfigView()
    {
        _scaffold.Title = "代理配置";
        _scaffold.Subtitle = "VPN / HTTP 代理与租户绑定";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()),
            FormFieldFactory.Secondary("测试全部", async (_, _) => await TestAllAsync()),
            FormFieldFactory.Secondary("上一页", async (_, _) => { if (_page > 1) { _page--; await LoadAsync(); } }),
            FormFieldFactory.Secondary("下一页", async (_, _) => { _page++; await LoadAsync(); }));

        _grid.Columns.Add(ListPageHelper.Col("名称", nameof(ProxyRow.Name), star: true));
        _grid.Columns.Add(ListPageHelper.Col("类型", nameof(ProxyRow.Type), 80));
        _grid.Columns.Add(ListPageHelper.Col("地址", nameof(ProxyRow.Host), 140));
        _grid.Columns.Add(ListPageHelper.Col("端口", nameof(ProxyRow.Port), 70));
        _grid.Columns.Add(ListPageHelper.Col("状态", nameof(ProxyRow.Status), 80));
        _grid.Columns.Add(ListPageHelper.Col("强制", nameof(ProxyRow.Force), 60));
        _grid.SelectionChanged += (_, _) =>
        {
            if (_grid.SelectedItem is ProxyRow r) FillForm(r);
        };

        var form = new WrapPanel { Margin = new Thickness(16, 8, 16, 0) };
        void Add(string label, UIElement el, double w = 140)
        {
            var sp = new StackPanel { Margin = new Thickness(0, 0, 12, 8) };
            sp.Children.Add(new TextBlock
            {
                Text = label,
                FontSize = 11,
                Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
            });
            if (el is FrameworkElement fe) fe.Width = w;
            sp.Children.Add(el);
            form.Children.Add(sp);
        }
        Add("名称", _name, 120);
        Add("类型", _type, 100);
        Add("主机", _host, 140);
        Add("端口", _port, 70);
        Add("用户名", _user, 100);
        Add("密码", _pass, 100);
        form.Children.Add(_force);

        var actions = ListPageHelper.TopBar(
            FormFieldFactory.Primary("保存", async (_, _) => await SaveAsync()),
            FormFieldFactory.Secondary("新建清空", (_, _) => ClearForm()),
            FormFieldFactory.Secondary("删除选中", async (_, _) => await DeleteSelectedAsync()),
            FormFieldFactory.Secondary("测试选中", async (_, _) => await TestSelectedAsync()),
            _pageInfo);

        var top = new StackPanel();
        top.Children.Add(form);
        top.Children.Add(actions);
        Content = ListPageHelper.Wrap(_scaffold, top, _grid);
        Loaded += async (_, _) => await LoadAsync();
    }

    private void ClearForm()
    {
        _editId = null;
        _name.Text = "";
        _type.SelectedItem = "HTTP";
        _host.Text = "";
        _port.Text = "1080";
        _user.Text = "";
        _pass.Password = "";
        _force.IsChecked = false;
        _grid.SelectedItem = null;
    }

    private void FillForm(ProxyRow r)
    {
        _editId = r.Id;
        _name.Text = r.Name;
        _type.SelectedItem = string.IsNullOrEmpty(r.Type) ? "HTTP" : r.Type.ToUpperInvariant();
        _host.Text = r.Host;
        _port.Text = r.Port;
        _force.IsChecked = r.Force is "1" or "true" or "是";
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.PostJsonAsync("/vpnProxy/pageList", new
            {
                pageNum = _page,
                pageSize = 10
            }).ConfigureAwait(true);
            var (rows, page, pages, total) = JsonPage.Parse(raw);
            if (page > 0) _page = page;
            _grid.ItemsSource = rows.Select(m => new ProxyRow
            {
                Id = JsonUtil.Int64(m, "id"),
                Name = JsonPage.Pick(m, "customName", "name"),
                Type = JsonPage.Pick(m, "proxyType", "type"),
                Host = JsonPage.Pick(m, "proxyHost", "host"),
                Port = JsonPage.Pick(m, "proxyPort", "port"),
                Status = JsonPage.Pick(m, "availableStatus", "status"),
                Force = JsonPage.Pick(m, "forceProxy")
            }).ToList();
            _pageInfo.Text = $"第 {_page}/{Math.Max(1, pages)} 页 · 共 {total}";
        });

    private async Task SaveAsync()
    {
        var host = (_host.Text ?? "").Trim();
        var type = (_type.SelectedItem as string) ?? "HTTP";
        if (string.IsNullOrEmpty(host))
        {
            ToastService.Error("请填写代理类型与地址");
            return;
        }
        if (!int.TryParse(_port.Text, out var port) || port is < 1 or > 65535)
        {
            ToastService.Error("端口范围应为 1–65535");
            return;
        }
        try
        {
            var body = new Dictionary<string, object?>
            {
                ["proxyType"] = type,
                ["proxyHost"] = host,
                ["proxyPort"] = port,
                ["availableStatus"] = 1,
                ["forceProxy"] = _force.IsChecked == true ? 1 : 0,
                ["customName"] = (_name.Text ?? "").Trim(),
                ["proxyUsername"] = (_user.Text ?? "").Trim(),
                ["tenantIds"] = Array.Empty<long>()
            };
            if (_editId is > 0) body["id"] = _editId.Value;
            if (!string.IsNullOrEmpty(_pass.Password))
                body["proxyPassword"] = _pass.Password;

            var raw = await _api.PostJsonAsync("/vpnProxy/saveOrUpdate", body).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存代理失败");
            ToastService.Success("已保存");
            ClearForm();
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task DeleteSelectedAsync()
    {
        if (_grid.SelectedItem is not ProxyRow row) { ToastService.Info("请先选择"); return; }
        try
        {
            var raw = await _api.PostJsonAsync("/vpnProxy/delete", new { id = row.Id }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "删除失败");
            ToastService.Success("已删除");
            ClearForm();
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task TestSelectedAsync()
    {
        if (_grid.SelectedItem is not ProxyRow row) { ToastService.Info("请先选择"); return; }
        try
        {
            var raw = await _api.PostJsonAsync("/vpnProxy/testConnection", new { id = row.Id }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "测试完成");
            ToastService.Info(r.message);
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task TestAllAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/vpnProxy/testAll", new { }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "测试已完成");
            ToastService.Info(r.message);
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }
}
