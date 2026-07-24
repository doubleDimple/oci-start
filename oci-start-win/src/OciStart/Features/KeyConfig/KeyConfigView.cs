using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.KeyConfig;

/// <summary>密钥配置 — 模块卡片（对齐 Mac KeyConfig / IpQuality 标准）.</summary>
public sealed class KeyConfigView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;

    private readonly ModuleSettingsCard _cfCard;
    private readonly ModuleSettingsCard _eoCard;
    private TextBox _cfToken = null!, _cfEmail = null!, _cfZone = null!;
    private TextBox _eoSid = null!, _eoSkey = null!, _eoRegion = null!;

    public KeyConfigView()
    {
        _scaffold.Title = "密钥配置";
        _scaffold.Subtitle = "Cloudflare / EdgeOne API 密钥";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));

        var accent = Color.FromRgb(0x3B, 0x82, 0xF6);
        _cfCard = new ModuleSettingsCard("Cloudflare", "API Token / Zone", "CF", accent, true);
        _eoCard = new ModuleSettingsCard("EdgeOne", "腾讯云 EdgeOne 密钥", "EO", accent, true);
        BuildCf();
        BuildEo();

        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(16),
            Content = new StackPanel
            {
                Children =
                {
                    new EqualHeightCardRow(_cfCard, _eoCard)
                }
            }
        };
        _scaffold.SetBody(scroll);
        Content = _scaffold;
        Loaded += async (_, _) => await LoadAsync();
    }

    private void BuildCf()
    {
        _cfToken = FormFieldFactory.TextField(watermark: "API Token");
        _cfEmail = FormFieldFactory.TextField(watermark: "Email（可选）");
        _cfZone = FormFieldFactory.TextField(watermark: "Zone ID");
        _cfCard.SetBody(
            FormFieldFactory.Labeled("API Token", _cfToken),
            FormFieldFactory.Labeled("Email", _cfEmail),
            FormFieldFactory.Labeled("Zone ID", _cfZone));
        _cfCard.SetFooter(
            FormFieldFactory.Secondary("测试", async (_, _) => await TestCfAsync()),
            FormFieldFactory.Primary("保存", async (_, _) => await SaveCfAsync()));
    }

    private void BuildEo()
    {
        _eoSid = FormFieldFactory.TextField(watermark: "SecretId");
        _eoSkey = FormFieldFactory.TextField(watermark: "SecretKey");
        _eoRegion = FormFieldFactory.TextField("ap-guangzhou");
        _eoCard.SetBody(
            FormFieldFactory.Labeled("SecretId", _eoSid),
            FormFieldFactory.Labeled("SecretKey", _eoSkey),
            FormFieldFactory.Labeled("Region", _eoRegion));
        _eoCard.SetFooter(
            FormFieldFactory.Secondary("测试", async (_, _) => await TestEoAsync()),
            FormFieldFactory.Primary("保存", async (_, _) => await SaveEoAsync()));
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/api/system/domainProviderConfigs").ConfigureAwait(true);
            var root = JsonUtil.Obj(raw) ?? new();
            if (root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
                root = JsonUtil.ToDict(data);

            if (root.TryGetValue("cloudflare", out var cf) && cf.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                var m = JsonUtil.ToDict(cf);
                _cfCard.IsEnabledToggle = JsonUtil.Bool(m, "enabled");
                _cfToken.Text = JsonUtil.Str(m, "apiToken");
                _cfEmail.Text = JsonUtil.Str(m, "email");
                _cfZone.Text = JsonUtil.Str(m, "zoneId");
            }
            if (root.TryGetValue("edgeOne", out var eo) && eo.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                var m = JsonUtil.ToDict(eo);
                _eoCard.IsEnabledToggle = JsonUtil.Bool(m, "enabled");
                _eoSid.Text = JsonUtil.Str(m, "secretId");
                _eoSkey.Text = JsonUtil.Str(m, "secretKey");
                var reg = JsonUtil.Str(m, "region");
                _eoRegion.Text = string.IsNullOrEmpty(reg) ? "ap-guangzhou" : reg;
            }
        });

    private async Task SaveCfAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateCloudflareConfig", new
            {
                enabled = _cfCard.IsEnabledToggle == true,
                apiToken = _cfToken.Text ?? "",
                email = _cfEmail.Text ?? "",
                zoneId = _cfZone.Text ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存 Cloudflare 失败");
            ToastService.Success("Cloudflare 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task TestCfAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/testCloudflareConnection", new
            {
                enabled = _cfCard.IsEnabledToggle == true,
                apiToken = _cfToken.Text ?? "",
                email = _cfEmail.Text ?? "",
                zoneId = _cfZone.Text ?? ""
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "Cloudflare 连接成功");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Info(r.message);
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveEoAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateEdgeOneConfig", new
            {
                enabled = _eoCard.IsEnabledToggle == true,
                secretId = _eoSid.Text ?? "",
                secretKey = _eoSkey.Text ?? "",
                region = _eoRegion.Text ?? "ap-guangzhou"
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存 EdgeOne 失败");
            ToastService.Success("EdgeOne 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task TestEoAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/testEdgeOneConnection", new
            {
                enabled = _eoCard.IsEnabledToggle == true,
                secretId = _eoSid.Text ?? "",
                secretKey = _eoSkey.Text ?? "",
                region = _eoRegion.Text ?? "ap-guangzhou"
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "EdgeOne 连接成功");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Info(r.message);
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }
}
