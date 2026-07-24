using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.IpQuality;

/// <summary>UI 基准页 — 对齐 Mac IpQualityView / windows-ui-standard.</summary>
public sealed class IpQualityView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly IpQualityService _service = new();
    private readonly ModuleSettingsCard _ipCard;
    private readonly ModuleSettingsCard _telecomCard;
    private readonly ModuleSettingsCard _unicomCard;
    private readonly ModuleSettingsCard _mobileCard;

    private ComboBox _intervalBox = null!;
    private VpsFields _telecom = null!;
    private VpsFields _unicom = null!;
    private VpsFields _mobile = null!;

    private bool _ipEnabled;
    private string? _savingKey;

    public IpQualityView()
    {
        _scaffold.Title = "质量管理";
        _scaffold.Subtitle = "IP 质量检测开关 · 三网 VPS SSH 探测节点";

        var refresh = FormFieldFactory.Secondary("刷新", async (_, _) => await ReloadAsync());
        _scaffold.SetToolbar(refresh);

        const double minH = 380;
        var accent = Color.FromRgb(0x4a, 0x9e, 0xff);

        _ipCard = new ModuleSettingsCard("IP 质量检测", "定时检测实例公网 IP 质量", "🛡", accent, showToggle: true, minH);
        _telecomCard = new ModuleSettingsCard(IpCarrier.Telecom.Title(), IpCarrier.Telecom.Subtitle(), IpCarrier.Telecom.Glyph(), accent, true, minH);
        _unicomCard = new ModuleSettingsCard(IpCarrier.Unicom.Title(), IpCarrier.Unicom.Subtitle(), IpCarrier.Unicom.Glyph(), accent, true, minH);
        _mobileCard = new ModuleSettingsCard(IpCarrier.Mobile.Title(), IpCarrier.Mobile.Subtitle(), IpCarrier.Mobile.Glyph(), accent, true, minH);

        BuildIpCard();
        _telecom = BuildVpsCard(_telecomCard, IpCarrier.Telecom);
        _unicom = BuildVpsCard(_unicomCard, IpCarrier.Unicom);
        _mobile = BuildVpsCard(_mobileCard, IpCarrier.Mobile);

        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(16)
        };
        var stack = new StackPanel();
        stack.Children.Add(new EqualHeightCardRow(_ipCard, _telecomCard, minH));
        stack.Children.Add(new EqualHeightCardRow(_unicomCard, _mobileCard, minH));
        scroll.Content = stack;
        _scaffold.SetBody(scroll);
        Content = _scaffold;

        Loaded += async (_, _) => await ReloadAsync();
    }

    private void BuildIpCard()
    {
        _intervalBox = FormFieldFactory.Combo(Enumerable.Range(1, 24).Select(i => $"{i} 小时"), "1 小时");
        _ipCard.SetBody(
            FormFieldFactory.Labeled("检测间隔", _intervalBox),
            new TextBlock
            {
                Text = "按设定小时周期执行 IP 质量检测任务",
                FontSize = 11,
                Foreground = (Brush)FindResource("TextSecondaryBrush")
            });
        _ipCard.SetFooter(FormFieldFactory.Primary("保存配置", async (_, _) => await SaveIpCheckAsync()));
        _ipCard.EnabledChanged += (_, _) => _ipEnabled = _ipCard.IsEnabledToggle == true;
    }

    private sealed class VpsFields
    {
        public TextBox Server = null!;
        public TextBox User = null!;
        public PasswordBox Pass = null!;
        public TextBox Port = null!;
        public ModuleSettingsCard Card = null!;
        public IpCarrier Carrier;
    }

    private VpsFields BuildVpsCard(ModuleSettingsCard card, IpCarrier carrier)
    {
        var f = new VpsFields
        {
            Carrier = carrier,
            Card = card,
            Server = FormFieldFactory.TextField(watermark: "IP 或域名"),
            User = FormFieldFactory.TextField("root"),
            Pass = FormFieldFactory.PasswordField(),
            Port = FormFieldFactory.TextField("22")
        };
        card.SetBody(
            FormFieldFactory.Labeled("服务器地址", f.Server),
            FormFieldFactory.Labeled("用户名", f.User),
            FormFieldFactory.Labeled("密码", f.Pass),
            FormFieldFactory.Labeled("SSH 端口", f.Port));
        card.SetFooter(
            FormFieldFactory.Secondary("测试连接", async (_, _) => await TestVpsAsync(f)),
            FormFieldFactory.Primary("保存", async (_, _) => await SaveVpsAsync(f)));
        return f;
    }

    private async Task ReloadAsync()
    {
        _scaffold.SetLoading(true);
        _scaffold.SetError(null);
        try
        {
            var cfg = await _service.FetchConfigsAsync().ConfigureAwait(true);
            _ipEnabled = cfg.IpCheck.Enabled;
            _ipCard.IsEnabledToggle = cfg.IpCheck.Enabled;
            _intervalBox.SelectedItem = $"{Math.Clamp(cfg.IpCheck.CheckInterval, 1, 24)} 小时";
            ApplyVps(_telecom, cfg.Telecom);
            ApplyVps(_unicom, cfg.Unicom);
            ApplyVps(_mobile, cfg.Mobile);
        }
        catch (Exception ex)
        {
            _scaffold.SetError(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _scaffold.SetLoading(false);
        }
    }

    private static void ApplyVps(VpsFields f, VpsConfigDto c)
    {
        f.Card.IsEnabledToggle = c.Enabled;
        f.Server.Text = c.ServerIp;
        f.User.Text = string.IsNullOrEmpty(c.Username) ? "root" : c.Username;
        f.Pass.Password = c.Password ?? "";
        f.Port.Text = c.SshPort > 0 ? c.SshPort.ToString() : "22";
    }

    private VpsConfigDto ReadVps(VpsFields f)
    {
        _ = int.TryParse(f.Port.Text?.Trim(), out var port);
        if (port <= 0) port = 22;
        return new VpsConfigDto
        {
            Type = f.Carrier.Raw(),
            Enabled = f.Card.IsEnabledToggle == true,
            ServerIp = (f.Server.Text ?? "").Trim(),
            Username = (f.User.Text ?? "").Trim(),
            Password = f.Pass.Password ?? "",
            SshPort = port
        };
    }

    private async Task SaveIpCheckAsync()
    {
        if (_savingKey != null) return;
        _savingKey = "ipCheck";
        try
        {
            var intervalText = (_intervalBox.SelectedItem as string) ?? "1 小时";
            var n = int.Parse(intervalText.Split(' ')[0]);
            await _service.UpdateIpCheckAsync(_ipCard.IsEnabledToggle == true, n).ConfigureAwait(true);
            ToastService.Success("IP 检测配置已保存");
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _savingKey = null;
        }
    }

    private async Task SaveVpsAsync(VpsFields f)
    {
        if (_savingKey != null) return;
        var cfg = ReadVps(f);
        if (cfg.Enabled &&
            (string.IsNullOrEmpty(cfg.ServerIp) || string.IsNullOrEmpty(cfg.Username) || string.IsNullOrEmpty(cfg.Password)))
        {
            ToastService.Error("启用时请填写服务器地址、用户名与密码");
            return;
        }
        if (cfg.SshPort is < 1 or > 65535)
        {
            ToastService.Error("SSH 端口范围应为 1–65535");
            return;
        }
        _savingKey = cfg.Type;
        try
        {
            await _service.SaveVpsAsync(cfg).ConfigureAwait(true);
            ToastService.Success(f.Carrier.Title() + " 已保存");
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _savingKey = null;
        }
    }

    private async Task TestVpsAsync(VpsFields f)
    {
        if (_savingKey != null) return;
        var cfg = ReadVps(f);
        if (string.IsNullOrEmpty(cfg.ServerIp) || string.IsNullOrEmpty(cfg.Username) || string.IsNullOrEmpty(cfg.Password))
        {
            ToastService.Error("请填写服务器地址、用户名与密码后再测试");
            return;
        }
        if (cfg.SshPort is < 1 or > 65535)
        {
            ToastService.Error("SSH 端口范围应为 1–65535");
            return;
        }
        _savingKey = "test-" + cfg.Type;
        try
        {
            var msg = await _service.TestConnectionAsync(cfg).ConfigureAwait(true);
            ToastService.Info(msg);
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _savingKey = null;
        }
    }
}
