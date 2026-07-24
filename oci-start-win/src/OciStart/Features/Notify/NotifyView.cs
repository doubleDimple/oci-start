using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Notify;

/// <summary>通知管理 — 对齐 Mac：定时任务 · Telegram · 代理 · Bark · 钉钉 · 飞书.</summary>
public sealed class NotifyView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;

    private ModuleSettingsCard _taskCard = null!, _tgCard = null!, _proxyCard = null!;
    private ModuleSettingsCard _barkCard = null!, _dingCard = null!, _fsCard = null!;

    private readonly CheckBox _accCheck = new() { Content = "账号检测", Foreground = Brushes.White };
    private readonly CheckBox _bootLog = new() { Content = "开机日志", Foreground = Brushes.White };
    private readonly CheckBox _costCheck = new() { Content = "费用检测", Foreground = Brushes.White };
    private readonly ComboBox _hourBox = FormFieldFactory.Combo(Enumerable.Range(0, 24).Select(i => $"{i} 点"), "9 点");

    private readonly TextBox _tgToken = FormFieldFactory.TextField(watermark: "从 @BotFather 获取");
    private readonly TextBox _tgChat = FormFieldFactory.TextField(watermark: "会话 ID");
    private readonly TextBox _tgChatName = FormFieldFactory.TextField(watermark: "可选备注名");

    private readonly ComboBox _proxyType = FormFieldFactory.Combo(["HTTP", "HTTPS", "SOCKS5"], "HTTP");
    private readonly TextBox _proxyHost = FormFieldFactory.TextField("127.0.0.1", "127.0.0.1");
    private readonly TextBox _proxyPort = FormFieldFactory.TextField("7890", "7890");
    private readonly TextBox _proxyUser = FormFieldFactory.TextField(watermark: "可选");
    private readonly PasswordBox _proxyPass = FormFieldFactory.PasswordField();

    private readonly TextBox _barkUrl = FormFieldFactory.TextField(watermark: "https://api.day.app");
    private readonly TextBox _barkKey = FormFieldFactory.TextField(watermark: "设备密钥");
    private readonly TextBox _dingUrl = FormFieldFactory.TextField(watermark: "Webhook URL");
    private readonly TextBox _dingSecret = FormFieldFactory.TextField(watermark: "可选加签密钥");
    private readonly TextBox _fsUrl = FormFieldFactory.TextField(watermark: "Webhook URL");
    private readonly TextBox _fsSecret = FormFieldFactory.TextField(watermark: "可选密钥");

    public NotifyView()
    {
        _scaffold.Title = "通知管理";
        _scaffold.Subtitle = "定时任务 · Telegram · 代理 · Bark · 钉钉 · 飞书";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));

        var accent = Color.FromRgb(0x3B, 0x82, 0xF6);
        var tgAccent = Color.FromRgb(0x2A, 0xAB, 0xEE);
        var proxyAccent = Color.FromRgb(0x9B, 0x59, 0xB6);
        var barkAccent = Color.FromRgb(0xF0, 0x88, 0x1A);
        var dingAccent = Color.FromRgb(0x00, 0x89, 0xFF);
        var fsAccent = Color.FromRgb(0x33, 0x7A, 0xFF);

        _taskCard = new ModuleSettingsCard("定时任务", "每天固定时刻执行所选检测任务", "⏰", accent, true);
        _taskCard.SetBody(
            FormFieldFactory.Labeled("执行小时", _hourBox),
            _accCheck, _bootLog, _costCheck);
        _taskCard.SetFooter(FormFieldFactory.Primary("保存任务", async (_, _) => await SaveTaskAsync()));

        _tgCard = new ModuleSettingsCard("Telegram", "Bot 消息推送", "✈", tgAccent, true);
        _tgCard.SetBody(
            FormFieldFactory.Labeled("Bot Token", _tgToken),
            FormFieldFactory.Labeled("Chat ID", _tgChat),
            FormFieldFactory.Labeled("Chat Name", _tgChatName));
        _tgCard.SetFooter(
            FormFieldFactory.Secondary("测试", async (_, _) => await TestAsync("/api/system/testTgTalk", "Telegram 测试发送成功")),
            FormFieldFactory.Primary("保存", async (_, _) => await SaveTgAsync()));

        _proxyCard = new ModuleSettingsCard("Telegram 代理", "访问 Telegram API 的出站代理", "🕸", proxyAccent, true);
        _proxyCard.SetBody(
            FormFieldFactory.Labeled("代理类型", _proxyType),
            FormFieldFactory.Labeled("地址", _proxyHost),
            FormFieldFactory.Labeled("端口", _proxyPort),
            FormFieldFactory.Labeled("用户名", _proxyUser),
            FormFieldFactory.Labeled("密码", _proxyPass));
        _proxyCard.SetFooter(
            FormFieldFactory.Secondary("测试", async (_, _) => await TestProxyAsync()),
            FormFieldFactory.Primary("保存", async (_, _) => await SaveProxyAsync()));

        _barkCard = new ModuleSettingsCard("Bark", "iOS Bark 推送", "📱", barkAccent, true);
        _barkCard.SetBody(
            FormFieldFactory.Labeled("服务 URL", _barkUrl),
            FormFieldFactory.Labeled("Device Key", _barkKey));
        _barkCard.SetFooter(
            FormFieldFactory.Secondary("测试", async (_, _) => await TestAsync("/api/system/testBark", "Bark 测试发送成功")),
            FormFieldFactory.Primary("保存", async (_, _) => await SaveBarkAsync()));

        _dingCard = new ModuleSettingsCard("钉钉", "群机器人 Webhook", "🔔", dingAccent, true);
        _dingCard.SetBody(
            FormFieldFactory.Labeled("Webhook", _dingUrl),
            FormFieldFactory.Labeled("加签密钥", _dingSecret));
        _dingCard.SetFooter(
            FormFieldFactory.Secondary("测试", async (_, _) => await TestAsync("/api/system/testDingTalk", "钉钉测试发送成功")),
            FormFieldFactory.Primary("保存", async (_, _) => await SaveDingAsync()));

        _fsCard = new ModuleSettingsCard("飞书", "群机器人 Webhook", "飞", fsAccent, true);
        _fsCard.SetBody(
            FormFieldFactory.Labeled("Webhook", _fsUrl),
            FormFieldFactory.Labeled("密钥", _fsSecret));
        _fsCard.SetFooter(
            FormFieldFactory.Secondary("测试", async (_, _) => await TestAsync("/api/system/testFeishu", "飞书测试发送成功")),
            FormFieldFactory.Primary("保存", async (_, _) => await SaveFeishuAsync()));

        // 对齐 Mac：任务全宽；TG|代理；Bark|钉钉；飞书半宽
        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(16),
            Content = new StackPanel
            {
                Children =
                {
                    _taskCard,
                    new Border { Height = 14 },
                    new EqualHeightCardRow(_tgCard, _proxyCard),
                    new EqualHeightCardRow(_barkCard, _dingCard),
                    new EqualHeightCardRow(_fsCard, new Border())
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
            var raw = await _api.GetJsonAsync("/api/system/notifyConfigs").ConfigureAwait(true);
            var root = JsonUtil.Obj(raw) ?? new();
            if (root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
                root = JsonUtil.ToDict(data);

            if (root.TryGetValue("task", out var task) && task.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                var m = JsonUtil.ToDict(task);
                _taskCard.IsEnabledToggle = JsonUtil.Bool(m, "enabled");
                var h = Math.Clamp(JsonUtil.Int(m, "executeHour", 9), 0, 23);
                _hourBox.SelectedItem = $"{h} 点";
                _accCheck.IsChecked = JsonUtil.Bool(m, "enableAccountCheck");
                _bootLog.IsChecked = JsonUtil.Bool(m, "enableBootLog");
                _costCheck.IsChecked = JsonUtil.Bool(m, "enableCostCheck");
            }

            ApplyChannel(root, "telegram", _tgCard, m =>
            {
                _tgToken.Text = JsonUtil.Str(m, "botToken");
                _tgChat.Text = JsonUtil.Str(m, "chatId");
                _tgChatName.Text = JsonUtil.Str(m, "chatName");
            });

            ApplyChannel(root, "proxy", _proxyCard, m =>
            {
                var t = JsonUtil.Str(m, "type").ToUpperInvariant();
                if (string.IsNullOrEmpty(t)) t = "HTTP";
                _proxyType.SelectedItem = t is "HTTP" or "HTTPS" or "SOCKS5" ? t : "HTTP";
                var host = JsonUtil.Str(m, "host");
                _proxyHost.Text = string.IsNullOrEmpty(host) ? "127.0.0.1" : host;
                var port = JsonUtil.Int(m, "port", 7890);
                _proxyPort.Text = port > 0 ? port.ToString() : "7890";
                _proxyUser.Text = JsonUtil.Str(m, "username");
                // password often not echoed; keep empty if server omits
                var pw = JsonUtil.Str(m, "password");
                if (!string.IsNullOrEmpty(pw)) _proxyPass.Password = pw;
            });

            ApplyChannel(root, "bark", _barkCard, m =>
            {
                _barkUrl.Text = JsonPage.Pick(m, "url", "serverUrl");
                _barkKey.Text = JsonPage.Pick(m, "deviceKey", "key");
            });

            ApplyChannel(root, "dingTalk", _dingCard, m =>
            {
                _dingUrl.Text = JsonPage.Pick(m, "webhook", "webhookUrl", "url");
                _dingSecret.Text = JsonUtil.Str(m, "secret");
            });
            if (string.IsNullOrEmpty(_dingUrl.Text))
            {
                ApplyChannel(root, "dingtalk", _dingCard, m =>
                {
                    _dingUrl.Text = JsonPage.Pick(m, "webhook", "webhookUrl", "url");
                    _dingSecret.Text = JsonUtil.Str(m, "secret");
                });
            }

            ApplyChannel(root, "feishu", _fsCard, m =>
            {
                _fsUrl.Text = JsonPage.Pick(m, "webhook", "webhookUrl", "url");
                _fsSecret.Text = JsonUtil.Str(m, "secret");
            });
            if (string.IsNullOrEmpty(_fsUrl.Text))
            {
                ApplyChannel(root, "lark", _fsCard, m =>
                {
                    _fsUrl.Text = JsonPage.Pick(m, "webhook", "webhookUrl", "url");
                    _fsSecret.Text = JsonUtil.Str(m, "secret");
                });
            }
        });

    private static void ApplyChannel(
        Dictionary<string, System.Text.Json.JsonElement> root,
        string key,
        ModuleSettingsCard card,
        Action<Dictionary<string, System.Text.Json.JsonElement>> fill)
    {
        if (!root.TryGetValue(key, out var el) || el.ValueKind != System.Text.Json.JsonValueKind.Object) return;
        var m = JsonUtil.ToDict(el);
        card.IsEnabledToggle = JsonUtil.Bool(m, "enabled");
        fill(m);
    }

    private int Hour()
    {
        var t = (_hourBox.SelectedItem as string) ?? "9 点";
        return int.TryParse(t.Split(' ')[0], out var h) ? h : 9;
    }

    private int ProxyPort()
    {
        var s = (_proxyPort.Text ?? "").Trim();
        return int.TryParse(s, out var p) ? p : 0;
    }

    private async Task SaveTaskAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateTaskConfig", new
            {
                enabled = _taskCard.IsEnabledToggle == true,
                executeHour = Hour(),
                notificationSecret = "",
                enableAccountCheck = _accCheck.IsChecked == true,
                enableBootLog = _bootLog.IsChecked == true,
                enableCostCheck = _costCheck.IsChecked == true
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存任务失败");
            ToastService.Success("定时任务已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveTgAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateTelegramConfig", new
            {
                enabled = _tgCard.IsEnabledToggle == true,
                botToken = _tgToken.Text ?? "",
                chatId = _tgChat.Text ?? "",
                chatName = _tgChatName.Text ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存 Telegram 失败");
            ToastService.Success("Telegram 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveProxyAsync()
    {
        var port = ProxyPort();
        if (port is < 1 or > 65535)
        {
            ToastService.Error("端口范围应为 1–65535");
            return;
        }
        try
        {
            var type = (_proxyType.SelectedItem as string) ?? "HTTP";
            var raw = await _api.PostJsonAsync("/api/system/updateProxyConfig", new
            {
                enabled = _proxyCard.IsEnabledToggle == true,
                type,
                host = (_proxyHost.Text ?? "").Trim(),
                port,
                username = _proxyUser.Text ?? "",
                password = _proxyPass.Password ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存 Telegram 代理失败");
            ToastService.Success("代理已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task TestProxyAsync()
    {
        var port = ProxyPort();
        if (port is < 1 or > 65535)
        {
            ToastService.Error("端口范围应为 1–65535");
            return;
        }
        try
        {
            var type = (_proxyType.SelectedItem as string) ?? "HTTP";
            var raw = await _api.PostJsonAsync("/api/system/testProxyConnection", new
            {
                enabled = _proxyCard.IsEnabledToggle == true,
                type,
                host = (_proxyHost.Text ?? "").Trim(),
                port,
                username = _proxyUser.Text ?? "",
                password = _proxyPass.Password ?? ""
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "代理连接测试成功");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveBarkAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateBarkConfig", new
            {
                enabled = _barkCard.IsEnabledToggle == true,
                url = _barkUrl.Text ?? "",
                deviceKey = _barkKey.Text ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存 Bark 失败");
            ToastService.Success("Bark 已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveDingAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateDingTalkConfig", new
            {
                enabled = _dingCard.IsEnabledToggle == true,
                webhook = _dingUrl.Text ?? "",
                secret = _dingSecret.Text ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存钉钉失败");
            ToastService.Success("钉钉已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task SaveFeishuAsync()
    {
        try
        {
            var raw = await _api.PostJsonAsync("/api/system/updateFeishuConfig", new
            {
                enabled = _fsCard.IsEnabledToggle == true,
                webhook = _fsUrl.Text ?? "",
                secret = _fsSecret.Text ?? ""
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "保存飞书失败");
            ToastService.Success("飞书已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task TestAsync(string path, string okMsg)
    {
        try
        {
            var raw = await _api.PostJsonAsync(path, new { }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, okMsg);
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }
}
