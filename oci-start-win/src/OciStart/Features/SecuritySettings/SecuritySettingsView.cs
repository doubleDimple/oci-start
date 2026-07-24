using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.SecuritySettings;

/// <summary>安全管理 — 对齐 Mac：账号 / Logo / MFA / OAuth / Turnstile / 频道通知.</summary>
public sealed class SecuritySettingsView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;

    private readonly PasswordBox _curPass = FormFieldFactory.PasswordField();
    private readonly TextBox _newUser = FormFieldFactory.TextField();
    private readonly PasswordBox _newPass = FormFieldFactory.PasswordField();
    private readonly TextBox _logo = FormFieldFactory.TextField();
    private readonly TextBox _mfaIssuer = FormFieldFactory.TextField("OCI-Start Verify");

    private readonly TextBox _ghUser = FormFieldFactory.TextField();
    private readonly TextBox _ghId = FormFieldFactory.TextField();
    private readonly TextBox _ghClientId = FormFieldFactory.TextField();
    private readonly TextBox _ghSecret = FormFieldFactory.TextField();
    private readonly TextBox _ghRedirect = FormFieldFactory.TextField();

    private readonly TextBox _ggEmail = FormFieldFactory.TextField();
    private readonly TextBox _ggClientId = FormFieldFactory.TextField();
    private readonly TextBox _ggSecret = FormFieldFactory.TextField();
    private readonly TextBox _ggRedirect = FormFieldFactory.TextField();

    private readonly TextBox _tsSite = FormFieldFactory.TextField(watermark: "公开 Site Key");
    private readonly TextBox _tsSecret = FormFieldFactory.TextField(watermark: "服务端 Secret Key");

    private ModuleSettingsCard _accountCard = null!, _logoCard = null!, _mfaCard = null!;
    private ModuleSettingsCard _ghCard = null!, _ggCard = null!;
    private ModuleSettingsCard _tsCard = null!, _channelCard = null!;

    public SecuritySettingsView()
    {
        _scaffold.Title = "安全管理";
        _scaffold.Subtitle = "账号安全 · OAuth · MFA · Turnstile · 频道通知";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));

        var accent = Color.FromRgb(0x3B, 0x82, 0xF6);
        var mfaAccent = Color.FromRgb(0x1A, 0xBC, 0x9C);
        var ghAccent = Color.FromRgb(0x24, 0x29, 0x2E);
        var ggAccent = Color.FromRgb(0x42, 0x85, 0xF4);
        var tsAccent = Color.FromRgb(0xF0, 0x88, 0x1A);
        var chAccent = Color.FromRgb(0x9B, 0x59, 0xB6);

        _accountCard = new ModuleSettingsCard("账号设置", "修改用户名 / 密码", "👤", accent, false);
        _accountCard.SetBody(
            FormFieldFactory.Labeled("当前密码", _curPass),
            FormFieldFactory.Labeled("新用户名（可选）", _newUser),
            FormFieldFactory.Labeled("新密码（可选）", _newPass));
        _accountCard.SetFooter(FormFieldFactory.Primary("保存账号", async (_, _) => await SaveAccountAsync()));

        _logoCard = new ModuleSettingsCard("站点 Logo", "显示名称", "🏷", accent, false);
        _logoCard.SetBody(FormFieldFactory.Labeled("Logo / 站点名", _logo));
        _logoCard.SetFooter(FormFieldFactory.Primary("保存 Logo", async (_, _) => await SaveLogoAsync()));

        _mfaCard = new ModuleSettingsCard("MFA", "双因素认证", "🔒", mfaAccent, true);
        _mfaCard.SetBody(FormFieldFactory.Labeled("Issuer", _mfaIssuer));
        _mfaCard.SetFooter(
            FormFieldFactory.Secondary("重新生成密钥", async (_, _) => await RegenMfaAsync()),
            FormFieldFactory.Primary("保存 MFA", async (_, _) => await SaveMfaAsync()));

        _ghCard = new ModuleSettingsCard("GitHub OAuth", "第三方登录", "GH", ghAccent, true, 420);
        _ghCard.SetBody(
            FormFieldFactory.Labeled("用户名", _ghUser),
            FormFieldFactory.Labeled("GitHub ID", _ghId),
            FormFieldFactory.Labeled("Client ID", _ghClientId),
            FormFieldFactory.Labeled("Client Secret", _ghSecret),
            FormFieldFactory.Labeled("Redirect URI", _ghRedirect));
        _ghCard.SetFooter(FormFieldFactory.Primary("保存 GitHub", async (_, _) => await SaveGithubAsync()));

        _ggCard = new ModuleSettingsCard("Google OAuth", "第三方登录", "G", ggAccent, true, 420);
        _ggCard.SetBody(
            FormFieldFactory.Labeled("Email", _ggEmail),
            FormFieldFactory.Labeled("Client ID", _ggClientId),
            FormFieldFactory.Labeled("Client Secret", _ggSecret),
            FormFieldFactory.Labeled("Redirect URI", _ggRedirect));
        _ggCard.SetFooter(FormFieldFactory.Primary("保存 Google", async (_, _) => await SaveGoogleAsync()));

        _tsCard = new ModuleSettingsCard("Cloudflare Turnstile", "登录人机验证", "🛡", tsAccent, true, 420);
        _tsCard.SetBody(
            FormFieldFactory.Labeled("Site Key", _tsSite),
            FormFieldFactory.Labeled("Secret Key", _tsSecret),
            new TextBlock
            {
                Text = "开启后登录页将展示 Turnstile 校验。",
                TextWrapping = TextWrapping.Wrap,
                FontSize = 11,
                Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
                Margin = new Thickness(0, 4, 0, 0)
            });
        _tsCard.SetFooter(FormFieldFactory.Primary("保存 Turnstile", async (_, _) => await SaveTurnstileAsync()));

        _channelCard = new ModuleSettingsCard("开机频道通知", "匿名上报机型与区域", "📡", chAccent, true, 420);
        _channelCard.SetBody(new TextBlock
        {
            Text = "开启后，抢机成功会向公共频道上报实例类型与区域，不含账号与 IP 等隐私信息。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
        });
        _channelCard.SetFooter(FormFieldFactory.Primary("保存频道通知", async (_, _) => await SaveChannelAsync()));

        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(16),
            Content = new StackPanel
            {
                Children =
                {
                    new EqualHeightCardRow(_accountCard, _logoCard),
                    new EqualHeightCardRow(_mfaCard, _ghCard, 420),
                    new EqualHeightCardRow(_ggCard, _tsCard, 420),
                    new EqualHeightCardRow(_channelCard, new Border(), 420)
                }
            }
        };

        _scaffold.SetBody(scroll);
        Content = _scaffold;
        Loaded += async (_, _) => await LoadAsync();
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/api/system/securitySettingsConfigs").ConfigureAwait(true);
            var root = JsonUtil.Obj(raw) ?? new();
            if (root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
                root = JsonUtil.ToDict(data);

            _logo.Text = FirstNonEmpty(
                JsonUtil.Str(root, "siteLogoName"),
                JsonUtil.Str(root, "logoName"));
            if (string.IsNullOrEmpty(_logo.Text) && root.TryGetValue("logo", out var logoEl)
                && logoEl.ValueKind == System.Text.Json.JsonValueKind.Object)
                _logo.Text = JsonUtil.Str(JsonUtil.ToDict(logoEl), "logoName");

            ApplyObj(root, "mfa", m =>
            {
                _mfaCard.IsEnabledToggle = JsonUtil.Bool(m, "enabled");
                var issuer = JsonUtil.Str(m, "issuer");
                if (!string.IsNullOrEmpty(issuer)) _mfaIssuer.Text = issuer;
            });
            ApplyObj(root, "github", m =>
            {
                _ghCard.IsEnabledToggle = JsonUtil.Bool(m, "enabled");
                _ghUser.Text = JsonPage.Pick(m, "userName", "username");
                _ghId.Text = JsonUtil.Str(m, "githubId");
                _ghClientId.Text = JsonUtil.Str(m, "clientId");
                _ghSecret.Text = JsonUtil.Str(m, "clientSecret");
                _ghRedirect.Text = JsonUtil.Str(m, "redirectUri");
            });
            ApplyObj(root, "google", m =>
            {
                _ggCard.IsEnabledToggle = JsonUtil.Bool(m, "enabled");
                _ggEmail.Text = JsonUtil.Str(m, "email");
                _ggClientId.Text = JsonUtil.Str(m, "clientId");
                _ggSecret.Text = JsonUtil.Str(m, "clientSecret");
                _ggRedirect.Text = JsonUtil.Str(m, "redirectUri");
            });
            ApplyObj(root, "turnstile", m =>
            {
                _tsCard.IsEnabledToggle = JsonUtil.Bool(m, "enabled");
                _tsSite.Text = JsonUtil.Str(m, "siteKey");
                _tsSecret.Text = JsonUtil.Str(m, "secretKey");
            });

            // channel notify is a top-level bool on snapshot
            _channelCard.IsEnabledToggle = JsonUtil.Bool(root, "channelNotifyEnabled")
                || (root.TryGetValue("channelNotify", out var ch)
                    && ch.ValueKind == System.Text.Json.JsonValueKind.Object
                    && JsonUtil.Bool(JsonUtil.ToDict(ch), "enabled"));
        });

    private static void ApplyObj(
        Dictionary<string, System.Text.Json.JsonElement> root,
        string key,
        Action<Dictionary<string, System.Text.Json.JsonElement>> fill)
    {
        if (!root.TryGetValue(key, out var el) || el.ValueKind != System.Text.Json.JsonValueKind.Object) return;
        fill(JsonUtil.ToDict(el));
    }

    private static string FirstNonEmpty(params string[] values)
    {
        foreach (var v in values)
            if (!string.IsNullOrEmpty(v)) return v;
        return "";
    }

    private async Task SaveAccountAsync()
    {
        try
        {
            var body = new Dictionary<string, object?> { ["currentPassword"] = _curPass.Password ?? "" };
            if (!string.IsNullOrWhiteSpace(_newUser.Text)) body["newUsername"] = _newUser.Text.Trim();
            if (!string.IsNullOrEmpty(_newPass.Password)) body["newPassword"] = _newPass.Password;
            var raw = await _api.PostJsonAsync("/api/system/updatePassword", body).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "账号更新失败");
            ToastService.Success("账号已更新");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveLogoAsync()
    {
        try
        {
            var (data, status) = await _api.PostFormAsync("/api/system/settings/logo",
                new Dictionary<string, string> { ["logoName"] = _logo.Text ?? "" }).ConfigureAwait(true);
            if ((int)status is < 200 or >= 300) throw ApiError.Server("保存 Logo 失败");
            ApiClient.EnsureApiOk(data, "保存 Logo 失败");
            ToastService.Success("Logo 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveMfaAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateMfaConfig", new
            {
                enabled = _mfaCard.IsEnabledToggle == true,
                issuer = string.IsNullOrWhiteSpace(_mfaIssuer.Text) ? "OCI-Start Verify" : _mfaIssuer.Text.Trim()
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "MFA 配置失败");
            ToastService.Success("MFA 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task RegenMfaAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/regenerateMfaSecret", new { }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "重新生成失败");
            ToastService.Success("MFA 密钥已重新生成");
            await LoadAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveGithubAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateGithubConfig", new
            {
                enabled = _ghCard.IsEnabledToggle == true,
                userName = _ghUser.Text ?? "",
                username = _ghUser.Text ?? "",
                githubId = _ghId.Text ?? "",
                clientId = _ghClientId.Text ?? "",
                clientSecret = _ghSecret.Text ?? "",
                redirectUri = _ghRedirect.Text ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "GitHub 配置失败");
            ToastService.Success("GitHub 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveGoogleAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateGoogleConfig", new
            {
                enabled = _ggCard.IsEnabledToggle == true,
                email = _ggEmail.Text ?? "",
                clientId = _ggClientId.Text ?? "",
                clientSecret = _ggSecret.Text ?? "",
                redirectUri = _ggRedirect.Text ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "Google 配置失败");
            ToastService.Success("Google 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveTurnstileAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateTurnstileConfig", new
            {
                enabled = _tsCard.IsEnabledToggle == true,
                siteKey = _tsSite.Text ?? "",
                secretKey = _tsSecret.Text ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "Turnstile 配置更新失败");
            ToastService.Success("Turnstile 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveChannelAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateChannelNotifyConfig", new
            {
                enabled = _channelCard.IsEnabledToggle == true
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "频道通知配置更新失败");
            ToastService.Success("频道通知已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }
}
