using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.MfaBackup;

public sealed class MfaKeyItem
{
    public string KeyName { get; set; } = "";
    public string SecretKey { get; set; } = "";
    public string Issuer { get; set; } = "Default";
    public string QrCodeBase64 { get; set; } = "";
    public string OtpCode { get; set; } = "------";
    public bool RevealSecret { get; set; }
}

/// <summary>MFA 备份 — 对齐 Mac MfaBackupView：卡片列表 · QR · 倒计时 OTP · 导出.</summary>
public sealed class MfaBackupView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly TextBox _search = FormFieldFactory.TextField(watermark: "搜索名称 / 发行方");
    private readonly TextBlock _countdownLabel = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        FontSize = 11,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(12, 0, 0, 0)
    };
    private readonly StackPanel _list = new() { Margin = new Thickness(16, 0, 16, 16) };
    private readonly TextBlock _empty = new()
    {
        Text = "暂无 MFA 密钥\n添加密钥后可查看动态验证码",
        TextAlignment = TextAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        FontSize = 13,
        TextWrapping = TextWrapping.Wrap,
        Visibility = Visibility.Collapsed
    };

    private List<MfaKeyItem> _items = [];
    private int _countdown = 30;
    private DispatcherTimer? _timer;

    public MfaBackupView()
    {
        _scaffold.Title = "MFA 备份";
        _scaffold.Subtitle = "TOTP 密钥托管 · 动态验证码 · 导出";
        _scaffold.SetToolbar(
            FormFieldFactory.Primary("添加密钥", (_, _) => ShowAddDialog()),
            FormFieldFactory.Secondary("导出 CSV", async (_, _) => await ExportCsvAsync()),
            FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));

        _search.Width = 220;
        _search.TextChanged += (_, _) => RebuildList();

        var filterBar = ListPageHelper.TopBar(_search, _countdownLabel);
        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = _list
        };
        var body = new Grid();
        body.Children.Add(scroll);
        body.Children.Add(_empty);

        Content = ListPageHelper.Wrap(_scaffold, filterBar, body);
        Loaded += async (_, _) =>
        {
            StartTimer();
            await LoadAsync();
        };
        Unloaded += (_, _) => StopTimer();
    }

    private void StartTimer()
    {
        StopTimer();
        UpdateCountdown();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += async (_, _) =>
        {
            UpdateCountdown();
            foreach (var child in _list.Children)
            {
                if (child is Border { Tag: CardRefs refs })
                    refs.OtpHint.Text = $"点击复制 · {_countdown}s";
            }
            if (_countdown == 30 || _items.Any(i => i.OtpCode.Contains('-') || string.IsNullOrEmpty(i.OtpCode)))
                await RefreshOtpsAsync();
        };
        _timer.Start();
    }

    private void StopTimer()
    {
        if (_timer == null) return;
        _timer.Stop();
        _timer = null;
    }

    private void UpdateCountdown()
    {
        var sec = (int)(DateTimeOffset.UtcNow.ToUnixTimeSeconds() % 30);
        _countdown = 30 - sec;
        _countdownLabel.Text = $"刷新倒计时 {_countdown}s";
    }

    private async Task LoadAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/api/mfa/keys").ConfigureAwait(true);
            var root = JsonUtil.Obj(raw);
            if (root != null && root.TryGetValue("success", out var okEl) &&
                okEl.ValueKind == System.Text.Json.JsonValueKind.False)
            {
                var msg = JsonUtil.Str(root, "message");
                throw ApiError.Server(string.IsNullOrEmpty(msg) ? "加载 MFA 失败" : msg);
            }

            var (rows, _, _, _) = JsonPage.Parse(raw, ["data", "content", "list", "keys"]);
            _items = rows.Select(m =>
            {
                var name = JsonPage.Pick(m, "keyName", "name", "id");
                var secret = JsonPage.Pick(m, "secretKey", "secret", "key");
                return new MfaKeyItem
                {
                    KeyName = name,
                    SecretKey = secret,
                    Issuer = string.IsNullOrEmpty(JsonPage.Pick(m, "issuer"))
                        ? "Default"
                        : JsonPage.Pick(m, "issuer"),
                    QrCodeBase64 = JsonPage.Pick(m, "qrCode", "qrCodeBase64", "qr"),
                    OtpCode = "------"
                };
            }).Where(x => !string.IsNullOrEmpty(x.KeyName) && !string.IsNullOrEmpty(x.SecretKey)).ToList();

            RebuildList();
            await RefreshOtpsAsync();
        });

    private IEnumerable<MfaKeyItem> Filtered()
    {
        var q = (_search.Text ?? "").Trim();
        if (string.IsNullOrEmpty(q)) return _items;
        return _items.Where(i =>
            i.KeyName.Contains(q, StringComparison.OrdinalIgnoreCase) ||
            i.Issuer.Contains(q, StringComparison.OrdinalIgnoreCase));
    }

    private void RebuildList()
    {
        _list.Children.Clear();
        var filtered = Filtered().ToList();
        _empty.Visibility = filtered.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        _empty.Text = _items.Count == 0
            ? "暂无 MFA 密钥\n添加密钥后可查看动态验证码"
            : "无匹配结果\n试试其他关键词";

        foreach (var item in filtered)
            _list.Children.Add(BuildCard(item));
    }

    private Border BuildCard(MfaKeyItem item)
    {
        var accent = (Brush)Application.Current.FindResource("AccentBrush");
        var cardBg = (Brush)Application.Current.FindResource("SidebarBgBrush");
        var borderBrush = (Brush)Application.Current.FindResource("AppBorderBrush");
        var textPrimary = (Brush)Application.Current.FindResource("TextPrimaryBrush");
        var textSecondary = (Brush)Application.Current.FindResource("TextSecondaryBrush");

        var root = new DockPanel { LastChildFill = true };

        // QR
        var qrHost = new Border
        {
            Width = 72,
            Height = 72,
            CornerRadius = new CornerRadius(8),
            BorderBrush = borderBrush,
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 0, 16, 0),
            ClipToBounds = true
        };
        var qrImg = DecodeQr(item.QrCodeBase64);
        if (qrImg != null)
        {
            qrHost.Child = new Image
            {
                Source = qrImg,
                Stretch = Stretch.Uniform,
                Width = 72,
                Height = 72
            };
            qrHost.Cursor = Cursors.Hand;
            qrHost.MouseLeftButtonUp += (_, _) => ShowQrPreview(item, qrImg);
        }
        else
        {
            qrHost.Background = new SolidColorBrush(Color.FromArgb(0x1F, 0x4a, 0x9e, 0xff));
            qrHost.Child = new TextBlock
            {
                Text = "QR",
                FontSize = 14,
                FontWeight = FontWeights.SemiBold,
                Foreground = accent,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
        }
        DockPanel.SetDock(qrHost, Dock.Left);
        root.Children.Add(qrHost);

        // Delete
        var delBtn = FormFieldFactory.Secondary("删除", async (_, _) => await DeleteAsync(item));
        delBtn.Margin = new Thickness(12, 0, 0, 0);
        DockPanel.SetDock(delBtn, Dock.Right);
        root.Children.Add(delBtn);

        // OTP block
        var otpPanel = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            MinWidth = 100,
            Margin = new Thickness(12, 0, 0, 0),
            Cursor = Cursors.Hand
        };
        var otpText = new TextBlock
        {
            Text = item.OtpCode,
            FontSize = 22,
            FontWeight = FontWeights.Bold,
            FontFamily = new FontFamily("Cascadia Mono, Consolas, Courier New"),
            Foreground = textPrimary,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        var otpHint = new TextBlock
        {
            Text = $"点击复制 · {_countdown}s",
            FontSize = 10,
            Foreground = textSecondary,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 4, 0, 0)
        };
        otpPanel.Children.Add(otpText);
        otpPanel.Children.Add(otpHint);
        otpPanel.MouseLeftButtonUp += (_, _) => CopyOtp(item.OtpCode);
        DockPanel.SetDock(otpPanel, Dock.Right);
        root.Children.Add(otpPanel);

        // Name / issuer / secret
        var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var nameRow = new StackPanel { Orientation = Orientation.Horizontal };
        nameRow.Children.Add(new TextBlock
        {
            Text = item.KeyName,
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Foreground = textPrimary,
            VerticalAlignment = VerticalAlignment.Center
        });
        nameRow.Children.Add(new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0x26, 0x4a, 0x9e, 0xff)),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(8, 2, 8, 2),
            Margin = new Thickness(8, 0, 0, 0),
            Child = new TextBlock
            {
                Text = item.Issuer,
                FontSize = 11,
                Foreground = accent
            }
        });
        info.Children.Add(nameRow);

        var secretLabel = new TextBlock
        {
            Text = item.RevealSecret ? item.SecretKey : "••••••••••••",
            FontSize = 11,
            FontFamily = new FontFamily("Cascadia Mono, Consolas, Courier New"),
            Foreground = textSecondary,
            Margin = new Thickness(0, 6, 0, 0),
            Cursor = Cursors.Hand,
            ToolTip = "点击显示/隐藏密钥"
        };
        secretLabel.MouseLeftButtonUp += (_, _) =>
        {
            item.RevealSecret = !item.RevealSecret;
            secretLabel.Text = item.RevealSecret ? item.SecretKey : "••••••••••••";
        };
        info.Children.Add(secretLabel);
        root.Children.Add(info);

        return new Border
        {
            Background = cardBg,
            BorderBrush = borderBrush,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(14),
            Margin = new Thickness(0, 0, 0, 12),
            Child = root,
            Tag = new CardRefs(item, otpText, otpHint)
        };
    }

    private sealed record CardRefs(MfaKeyItem Item, TextBlock OtpText, TextBlock OtpHint);

    private async Task RefreshOtpsAsync()
    {
        if (_items.Count == 0) return;
        try
        {
            var secrets = _items.Select(r => r.SecretKey).Where(s => !string.IsNullOrEmpty(s)).ToList();
            if (secrets.Count == 0) return;
            var raw = await _api.PostJsonAsync("/generate-otp-batch", new { secretKeys = secrets })
                .ConfigureAwait(true);
            var map = ParseBatchOtp(raw);
            foreach (var row in _items)
            {
                if (map.TryGetValue(row.SecretKey, out var code))
                    row.OtpCode = code;
            }
            // Update visible OTP labels without full rebuild (preserve secret reveal)
            foreach (var child in _list.Children)
            {
                if (child is not Border { Tag: CardRefs refs }) continue;
                refs.OtpText.Text = refs.Item.OtpCode;
                refs.OtpHint.Text = $"点击复制 · {_countdown}s";
            }
        }
        catch
        {
            // OTP optional — list still usable
        }
    }

    /// <summary>API returns List&lt;OtpResponse&gt;: [{secretKey, otpCode}, ...].</summary>
    private static Dictionary<string, string> ParseBatchOtp(byte[] raw)
    {
        var map = new Dictionary<string, string>(StringComparer.Ordinal);
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(raw);
            var root = doc.RootElement;
            if (root.ValueKind == System.Text.Json.JsonValueKind.Object &&
                root.TryGetProperty("data", out var data) &&
                data.ValueKind == System.Text.Json.JsonValueKind.Array)
                root = data;

            if (root.ValueKind == System.Text.Json.JsonValueKind.Array)
            {
                foreach (var el in root.EnumerateArray())
                {
                    if (el.ValueKind != System.Text.Json.JsonValueKind.Object) continue;
                    var secret = el.TryGetProperty("secretKey", out var s) ? JsonUtil.Str(s) : "";
                    var code = el.TryGetProperty("otpCode", out var c) ? JsonUtil.Str(c) : "";
                    if (!string.IsNullOrEmpty(secret) && !string.IsNullOrEmpty(code))
                        map[secret] = code;
                }
                return map;
            }

            // fallback: object map secret → code
            if (root.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                foreach (var p in root.EnumerateObject())
                {
                    if (p.Name is "success" or "message" or "data") continue;
                    var v = JsonUtil.Str(p.Value);
                    if (!string.IsNullOrEmpty(v)) map[p.Name] = v;
                }
            }
        }
        catch
        {
            // ignore
        }
        return map;
    }

    private static BitmapImage? DecodeQr(string base64)
    {
        if (string.IsNullOrWhiteSpace(base64)) return null;
        var s = base64.Trim();
        var idx = s.IndexOf("base64,", StringComparison.OrdinalIgnoreCase);
        if (idx >= 0) s = s[(idx + 7)..];
        try
        {
            var bytes = Convert.FromBase64String(s);
            var img = new BitmapImage();
            using var ms = new MemoryStream(bytes);
            img.BeginInit();
            img.CacheOption = BitmapCacheOption.OnLoad;
            img.StreamSource = ms;
            img.EndInit();
            img.Freeze();
            return img;
        }
        catch
        {
            return null;
        }
    }

    private static void ShowQrPreview(MfaKeyItem item, BitmapImage img)
    {
        var win = new Window
        {
            Title = "二维码 — " + item.KeyName,
            Width = 360,
            Height = 400,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null)
            win.Owner = Application.Current.MainWindow;
        var panel = new StackPanel
        {
            Margin = new Thickness(24),
            HorizontalAlignment = HorizontalAlignment.Center
        };
        panel.Children.Add(new Image
        {
            Source = img,
            Width = 240,
            Height = 240,
            Stretch = Stretch.Uniform,
            HorizontalAlignment = HorizontalAlignment.Center
        });
        panel.Children.Add(new TextBlock
        {
            Text = item.KeyName + " · " + item.Issuer,
            Margin = new Thickness(0, 16, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
        });
        panel.Children.Add(FormFieldFactory.Secondary("关闭", (_, _) => win.Close()));
        win.Content = panel;
        win.ShowDialog();
    }

    private static void CopyOtp(string code)
    {
        if (string.IsNullOrEmpty(code) || code.Contains('-') || code.Length < 4)
            return;
        try
        {
            Clipboard.SetText(code);
            ToastService.Success("已复制 " + code);
        }
        catch
        {
            ToastService.Error("复制失败");
        }
    }

    private void ShowAddDialog()
    {
        var nameBox = FormFieldFactory.TextField(watermark: "留空则用时间戳");
        var secretBox = FormFieldFactory.TextField(watermark: "Base32 Secret");
        var ok = false;
        var win = new Window
        {
            Title = "添加 MFA 密钥",
            Width = 440,
            Height = 280,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null)
            win.Owner = Application.Current.MainWindow;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(FormFieldFactory.Labeled("名称", nameBox));
        panel.Children.Add(FormFieldFactory.Labeled("密钥", secretBox));
        panel.Children.Add(new TextBlock
        {
            Text = "当前支持手动填写 Base32 密钥；二维码图片导入可后续扩展。",
            FontSize = 11,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 4, 0, 0)
        });
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary("保存", (_, _) =>
        {
            ok = true;
            win.Close();
        }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        if (!ok) return;

        var secret = (secretBox.Text ?? "").Trim();
        if (string.IsNullOrEmpty(secret))
        {
            ToastService.Error("请填写密钥");
            return;
        }
        var name = (nameBox.Text ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            name = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString();

        _ = SaveSecretAsync(name, secret);
    }

    private async Task SaveSecretAsync(string keyName, string secretKey)
    {
        try
        {
            _scaffold.SetLoading(true);
            var (data, status) = await _api.PostFormAsync("/save-secret", new Dictionary<string, string>
            {
                ["keyName"] = keyName,
                ["secretKey"] = secretKey
            }).ConfigureAwait(true);
            if ((int)status is < 200 or >= 400)
            {
                var msg = System.Text.Encoding.UTF8.GetString(data);
                throw ApiError.Server(string.IsNullOrWhiteSpace(msg) ? "保存失败" : msg);
            }
            ToastService.Success("已保存");
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

    private async Task DeleteAsync(MfaKeyItem item)
    {
        if (MessageBox.Show(
                $"确定删除「{item.KeyName}」？",
                "删除密钥",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;
        try
        {
            var raw = await _api.PostJsonAsync("/delete-key", new { keyName = item.KeyName })
                .ConfigureAwait(true);
            // OtpResponse2: { otpCode: "OK" } — not standard success envelope
            var root = JsonUtil.Obj(raw);
            if (root != null)
            {
                var msg = JsonUtil.Str(root, "message");
                if (string.IsNullOrEmpty(msg)) msg = JsonUtil.Str(root, "otpCode");
                if (msg.Contains("null", StringComparison.OrdinalIgnoreCase) ||
                    msg.Contains("is null", StringComparison.OrdinalIgnoreCase))
                    throw ApiError.Server("删除失败");
            }
            ToastService.Success("已删除");
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
    }

    private async Task ExportCsvAsync()
    {
        try
        {
            _scaffold.SetLoading(true);
            var (data, filename, _) = await _api.DownloadAsync("/export-data").ConfigureAwait(true);
            var save = new SaveFileDialog
            {
                Title = "导出 MFA 密钥",
                FileName = string.IsNullOrEmpty(filename) ? "otp_keys.csv" : filename.Trim('"'),
                Filter = "CSV|*.csv|All|*.*"
            };
            if (save.ShowDialog() != true) return;
            await File.WriteAllBytesAsync(save.FileName, data).ConfigureAwait(true);
            ToastService.Success("已导出");
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
