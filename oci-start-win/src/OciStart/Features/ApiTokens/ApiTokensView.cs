using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.ApiTokens;

public sealed class ApiTokensView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly TextBox _name = FormFieldFactory.TextField("default");
    private readonly TextBox _days = FormFieldFactory.TextField("30");
    private readonly TextBox _desc = FormFieldFactory.TextField();
    private readonly CheckBox _swagger = new() { Content = "允许 Swagger", Foreground = Brushes.White };
    private readonly TextBlock _status = new()
    {
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
    };
    private readonly TextBox _tokenOut = FormFieldFactory.TextField();

    public ApiTokensView()
    {
        _scaffold.Title = "Token 配置";
        _scaffold.Subtitle = "OpenAPI / 开放接口 Token";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));

        var accent = Color.FromRgb(0x3B, 0x82, 0xF6);
        var card = new ModuleSettingsCard("API Token", "生成 / 撤销访问令牌", "🔑", accent, false, 420);
        _tokenOut.IsReadOnly = true;
        card.SetBody(
            FormFieldFactory.Labeled("名称", _name),
            FormFieldFactory.Labeled("有效天数", _days),
            FormFieldFactory.Labeled("描述", _desc),
            _swagger,
            _status,
            FormFieldFactory.Labeled("最近生成的 Token", _tokenOut));
        card.SetFooter(
            FormFieldFactory.Secondary("撤销", async (_, _) => await RevokeAsync()),
            FormFieldFactory.Primary("生成", async (_, _) => await GenerateAsync()));

        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(16),
            Content = card
        };
        _scaffold.SetBody(scroll);
        Content = _scaffold;
        Loaded += async (_, _) => await LoadAsync();
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/api/system/apiTokenConfigs").ConfigureAwait(true);
            var root = JsonUtil.Obj(raw) ?? new();
            if (root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
                root = JsonUtil.ToDict(data);

            var enabled = JsonUtil.Bool(root, "enabled");
            var hasToken = JsonUtil.Bool(root, "hasToken") || !string.IsNullOrEmpty(JsonUtil.Str(root, "tokenName"));
            var tokenName = JsonUtil.Str(root, "tokenName");
            var expire = JsonPage.Pick(root, "expirationTime", "expireAt", "expiresAt");
            _status.Text = $"状态: {(hasToken || enabled ? "已配置" : "未生成")}" +
                           (string.IsNullOrEmpty(tokenName) ? "" : $" · {tokenName}") +
                           (string.IsNullOrEmpty(expire) ? "" : $" · 过期 {expire}");
            if (!string.IsNullOrEmpty(tokenName)) _name.Text = tokenName;
            if (root.TryGetValue("allowSwaggerAccess", out _))
                _swagger.IsChecked = JsonUtil.Bool(root, "allowSwaggerAccess");
        });

    private async Task GenerateAsync()
    {
        try
        {
            _ = int.TryParse(_days.Text, out var days);
            if (days <= 0) days = 30;
            var raw = await _api.PostJsonAsync("/api/system/generateApiToken", new
            {
                enabled = true,
                tokenName = _name.Text ?? "default",
                expirationDays = days,
                description = _desc.Text ?? "",
                allowSwaggerAccess = _swagger.IsChecked == true
            }).ConfigureAwait(true);
            var root = JsonUtil.Obj(raw) ?? new();
            if (root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                var m = JsonUtil.ToDict(data);
                _tokenOut.Text = JsonPage.Pick(m, "token", "apiToken", "accessToken");
            }
            else
            {
                _tokenOut.Text = JsonPage.Pick(root, "token", "apiToken", "accessToken");
            }
            if (string.IsNullOrEmpty(_tokenOut.Text))
                ApiClient.EnsureApiOk(raw, "生成失败");
            ToastService.Success("Token 已生成（请立即复制保存）");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task RevokeAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/revokeApiToken", new { }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "撤销失败");
            _tokenOut.Text = "";
            ToastService.Success("已撤销");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }
}
