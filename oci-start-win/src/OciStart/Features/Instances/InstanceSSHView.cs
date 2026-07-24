using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Instances;

/// <summary>整页 SSH — 对齐 Mac：交互终端 · PTY resize · 主题/字号 · 搜索 · SFTP.</summary>
public sealed class InstanceSSHView : UserControl
{
    private readonly InstanceItem _item;
    private readonly Action _onBack;
    private readonly InstancesService _service = new();
    private readonly WsClient _ws = new();
    private readonly PageScaffold _scaffold = new();
    private readonly TerminalSurface _term = new();

    private readonly TextBox _user = FormFieldFactory.TextField("root");
    private readonly TextBox _host = FormFieldFactory.TextField();
    private readonly TextBox _port = FormFieldFactory.TextField("22");
    private readonly PasswordBox _pass = FormFieldFactory.PasswordField();
    private readonly ComboBox _themeBox = FormFieldFactory.Combo(
        TerminalThemes.All.Select(t => t.Title), "Matrix");
    private readonly TextBlock _status = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        FontSize = 11,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(12, 0, 0, 0),
        Text = "未连接"
    };
    private readonly TextBlock _sizeLabel = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        FontSize = 11,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(12, 0, 0, 0)
    };
    private readonly TextBox _search = FormFieldFactory.TextField(watermark: "搜索终端输出");
    private readonly TextBlock _searchHit = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        FontSize = 11,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(8, 0, 0, 0)
    };

    private bool _connected;
    private int _cols = 80;
    private int _rows = 24;

    public InstanceSSHView(InstanceItem item, Action onBack)
    {
        _item = item;
        _onBack = onBack;
        _host.Text = item.PublicIps;

        // restore prefs
        var fs = SettingsStore.GetInt("terminal.fontSize");
        if (fs is >= 10 and <= 24) _term.TermFontSize = fs;
        else _term.TermFontSize = 14;
        var th = SettingsStore.GetString("terminal.theme") ?? "matrix";
        _term.ThemeKey = th;
        var thIdx = Array.FindIndex(TerminalThemes.All, t => t.Key == th);
        if (thIdx >= 0) _themeBox.SelectedIndex = thIdx;

        _scaffold.Title = "SSH — " + (string.IsNullOrEmpty(item.DisplayName) ? "实例" : item.DisplayName);
        _scaffold.Subtitle = item.PublicIps;
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("返回列表", async (_, _) =>
            {
                await _ws.DisconnectAsync();
                _onBack();
            }),
            FormFieldFactory.Secondary("保存配置", async (_, _) => await SaveAsync()),
            FormFieldFactory.Primary("连接", async (_, _) => await ConnectAsync()),
            FormFieldFactory.Secondary("断开", async (_, _) => await DisconnectAsync()),
            FormFieldFactory.Secondary("重连", async (_, _) =>
            {
                await DisconnectAsync();
                await Task.Delay(400);
                await ConnectAsync();
            }),
            FormFieldFactory.Secondary("清屏", (_, _) =>
            {
                _term.Clear();
                _term.AppendRaw("\r\n");
            }),
            FormFieldFactory.Secondary("复制命令", (_, _) => CopyCommand()),
            FormFieldFactory.Secondary("下载日志", (_, _) => DownloadLog()),
            FormFieldFactory.Secondary("上传", async (_, _) => await UploadAsync()),
            FormFieldFactory.Secondary("下载", async (_, _) => await DownloadFileAsync()),
            FormFieldFactory.Secondary("A−", (_, _) =>
            {
                _term.TermFontSize -= 1;
                SettingsStore.SetInt("terminal.fontSize", (int)_term.TermFontSize);
            }),
            FormFieldFactory.Secondary("A+", (_, _) =>
            {
                _term.TermFontSize += 1;
                SettingsStore.SetInt("terminal.fontSize", (int)_term.TermFontSize);
            }));

        _themeBox.SelectionChanged += (_, _) =>
        {
            var i = _themeBox.SelectedIndex;
            if (i < 0 || i >= TerminalThemes.All.Length) return;
            _term.ThemeKey = TerminalThemes.All[i].Key;
            SettingsStore.SetString("terminal.theme", _term.ThemeKey);
        };

        _search.Width = 160;
        _search.TextChanged += (_, _) =>
        {
            var q = (_search.Text ?? "").Trim();
            if (string.IsNullOrEmpty(q))
            {
                _searchHit.Text = "";
                return;
            }
            var n = _term.SearchCount(q);
            _searchHit.Text = n > 0 ? $"{n} 处" : "无结果";
        };

        var form = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 8, 16, 4) };
        form.Children.Add(Labeled("用户", _user, 100));
        form.Children.Add(Labeled("主机", _host, 160));
        form.Children.Add(Labeled("端口", _port, 70));
        form.Children.Add(Labeled("密码", _pass, 140));
        form.Children.Add(Labeled("主题", _themeBox, 140));
        form.Children.Add(_status);
        form.Children.Add(_sizeLabel);

        var searchBar = ListPageHelper.TopBar(
            new TextBlock
            {
                Text = "搜索",
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
                Margin = new Thickness(0, 0, 8, 0)
            },
            _search,
            _searchHit,
            new TextBlock
            {
                Text = "点击终端区域输入 · Ctrl+V 粘贴 · Ctrl+C 复制选区",
                VerticalAlignment = VerticalAlignment.Center,
                FontSize = 11,
                Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
                Margin = new Thickness(16, 0, 0, 0)
            });

        var root = new DockPanel();
        DockPanel.SetDock(form, Dock.Top);
        DockPanel.SetDock(searchBar, Dock.Top);
        root.Children.Add(form);
        root.Children.Add(searchBar);
        root.Children.Add(_term);
        _scaffold.SetBody(root);
        Content = _scaffold;

        _term.Input += async s => await SendInputAsync(s);
        _term.Resized += async (c, r) =>
        {
            _cols = c;
            _rows = r;
            _sizeLabel.Text = $"{c}×{r}";
            if (_connected)
                await SendResizeAsync(c, r, force: false);
        };

        _ws.TextReceived += OnWsText;
        _ws.Closed += reason => Dispatcher.Invoke(() =>
        {
            _connected = false;
            _term.IsInteractive = false;
            _status.Text = "已断开" + (string.IsNullOrEmpty(reason) ? "" : " · " + reason);
            _term.AppendRaw($"\r\n● 已断开 {(reason ?? "")}\r\n");
        });

        Loaded += async (_, _) =>
        {
            _term.AppendRaw("欢迎使用 OCI-Start SSH 终端\r\n点击此区域后直接键入命令（对齐 Mac 交互终端）\r\n\r\n");
            await LoadConfigAsync();
        };
        Unloaded += async (_, _) => await _ws.DisconnectAsync();
    }

    private static UIElement Labeled(string label, UIElement field, double width)
    {
        var sp = new StackPanel { Margin = new Thickness(0, 0, 12, 0) };
        sp.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 11,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
        });
        if (field is FrameworkElement fe) fe.Width = width;
        sp.Children.Add(field);
        return sp;
    }

    private async Task LoadConfigAsync()
    {
        try
        {
            var (u, h, p, pw) = await _service.LoadSshConfigAsync(_item.Id).ConfigureAwait(true);
            if (!string.IsNullOrEmpty(u)) _user.Text = u;
            if (!string.IsNullOrEmpty(h)) _host.Text = h;
            else if (string.IsNullOrEmpty(_host.Text)) _host.Text = _item.PublicIps;
            if (!string.IsNullOrEmpty(p)) _port.Text = p;
            if (!string.IsNullOrEmpty(pw)) _pass.Password = pw;
        }
        catch
        {
            if (string.IsNullOrEmpty(_host.Text)) _host.Text = _item.PublicIps;
        }
    }

    private async Task SaveAsync()
    {
        try
        {
            await _service.SaveSshConfigAsync(
                _item.Id,
                (_user.Text ?? "").Trim(),
                (_port.Text ?? "22").Trim(),
                _pass.Password ?? "").ConfigureAwait(true);
            ToastService.Success("SSH 配置已保存");
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task ConnectAsync()
    {
        var u = (_user.Text ?? "").Trim();
        var h = (_host.Text ?? "").Trim();
        var p = (_port.Text ?? "").Trim();
        if (string.IsNullOrEmpty(u) || string.IsNullOrEmpty(h) || string.IsNullOrEmpty(p) ||
            string.IsNullOrEmpty(_pass.Password))
        {
            ToastService.Error("请填写用户名、地址、端口和密码");
            return;
        }
        if (!int.TryParse(p, out var portNum) || portNum is < 1 or > 65535)
        {
            ToastService.Error("端口无效");
            return;
        }
        try
        {
            _status.Text = "连接中…";
            _term.AppendRaw($"\r\n▶ 正在连接 {u}@{h}:{p} …\r\n");
            var url = WsClient.MakeWsUrl(AppSession.Shared.ServerUrl, "/ws/ssh");
            await _ws.ConnectAsync(url).ConfigureAwait(true);
            await Task.Delay(150);
            await _ws.SendJsonAsync(new
            {
                type = "connect",
                data = new
                {
                    host = h,
                    port = portNum,
                    username = u,
                    password = _pass.Password
                }
            }).ConfigureAwait(true);
            // mark pending; success banner or first output flips connected
            _term.IsInteractive = true;
            _term.FocusTerm();
            _term.ReportResize(force: true);
        }
        catch (Exception ex)
        {
            _connected = false;
            _term.IsInteractive = false;
            _status.Text = "连接失败";
            _term.AppendRaw("\r\n连接失败: " + ex.Message + "\r\n");
            ToastService.Error(ex.Message);
        }
    }

    private async Task DisconnectAsync()
    {
        await _ws.DisconnectAsync().ConfigureAwait(true);
        _connected = false;
        _term.IsInteractive = false;
        _status.Text = "已断开";
        _term.AppendRaw("\r\n● 连接已断开\r\n");
    }

    private async Task SendInputAsync(string text)
    {
        if (!_connected)
        {
            // allow buffer while connecting once WS is open
            if (!_ws.IsOpen)
            {
                _term.AppendRaw("\r\n请先建立 SSH 连接\r\n");
                return;
            }
        }
        try
        {
            await _ws.SendJsonAsync(new { type = "input", data = text }).ConfigureAwait(true);
        }
        catch (Exception ex) { _term.AppendRaw("\r\n发送失败: " + ex.Message + "\r\n"); }
    }

    private async Task SendResizeAsync(int cols, int rows, bool force)
    {
        if (!_connected && !force) return;
        if (!_ws.IsOpen) return;
        try
        {
            await _ws.SendJsonAsync(new
            {
                type = "resize",
                data = new { cols, rows }
            }).ConfigureAwait(true);
        }
        catch { /* ignore resize errors */ }
    }

    private void CopyCommand()
    {
        var u = (_user.Text ?? "root").Trim();
        var h = (_host.Text ?? "").Trim();
        var p = (_port.Text ?? "22").Trim();
        var cmd = p == "22" ? $"ssh {u}@{h}" : $"ssh {u}@{h} -p {p}";
        try
        {
            Clipboard.SetText(cmd);
            ToastService.Success("已复制: " + cmd);
        }
        catch { ToastService.Error("复制失败"); }
    }

    private void DownloadLog()
    {
        var plain = _term.PlainText;
        if (string.IsNullOrWhiteSpace(plain))
        {
            ToastService.Info("暂无终端输出");
            return;
        }
        var hostPart = string.IsNullOrWhiteSpace(_host.Text) ? "terminal" : _host.Text!.Trim();
        var dlg = new SaveFileDialog
        {
            FileName = $"ssh-{hostPart}-{DateTime.Now:yyyyMMdd-HHmmss}.txt",
            Filter = "Text|*.txt|All|*.*"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            File.WriteAllText(dlg.FileName, plain);
            ToastService.Success("日志已保存");
            _term.AppendRaw("\r\n✅ 日志已下载\r\n");
        }
        catch (Exception ex) { ToastService.Error(ex.Message); }
    }

    private async Task UploadAsync()
    {
        if (!_connected)
        {
            _term.AppendRaw("\r\n请先建立 SSH 连接\r\n");
            return;
        }
        if (!TryCreds(out var host, out var port, out var user, out var pass)) return;

        var open = new OpenFileDialog { Title = "选择要上传到服务器的文件" };
        if (open.ShowDialog() != true) return;
        var u = user;
        var defaultPath = string.IsNullOrEmpty(u) || u == "root" ? "/root/" : $"/home/{u}/";
        var remote = PromptPath("上传文件",
            $"文件：{Path.GetFileName(open.FileName)}\n请输入远程目录或完整路径", defaultPath);
        if (remote == null) return;
        remote = remote.Trim();
        if (string.IsNullOrEmpty(remote))
        {
            ToastService.Error("请输入远程路径");
            return;
        }

        _term.AppendRaw($"\r\n▶ 正在上传 {Path.GetFileName(open.FileName)} …\r\n");
        _scaffold.SetLoading(true);
        try
        {
            var msg = await _service.SftpUploadAsync(host, port, user, pass, remote, open.FileName)
                .ConfigureAwait(true);
            _term.AppendRaw($"\r\n✅ 上传成功: {msg}\r\n");
            ToastService.Success("上传成功");
        }
        catch (Exception ex)
        {
            _term.AppendRaw($"\r\n❌ 上传失败: {ex.Message}\r\n");
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally { _scaffold.SetLoading(false); }
    }

    private async Task DownloadFileAsync()
    {
        if (!_connected)
        {
            _term.AppendRaw("\r\n请先建立 SSH 连接\r\n");
            return;
        }
        if (!TryCreds(out var host, out var port, out var user, out var pass)) return;

        var hint = string.IsNullOrEmpty(user) || user == "root" ? "/root/file.txt" : $"/home/{user}/file.txt";
        var remote = PromptPath("下载文件", "请输入远程文件完整路径", hint);
        if (remote == null) return;
        remote = remote.Trim();
        if (string.IsNullOrEmpty(remote))
        {
            ToastService.Error("请输入远程文件路径");
            return;
        }

        _term.AppendRaw($"\r\n▶ 正在下载 {remote} …\r\n");
        _scaffold.SetLoading(true);
        try
        {
            var (data, name) = await _service.SftpDownloadAsync(host, port, user, pass, remote)
                .ConfigureAwait(true);
            var dlg = new SaveFileDialog { FileName = name, Filter = "All|*.*" };
            if (dlg.ShowDialog() == true)
            {
                await File.WriteAllBytesAsync(dlg.FileName, data).ConfigureAwait(true);
                _term.AppendRaw($"\r\n✅ 下载成功: {dlg.FileName}\r\n");
                ToastService.Success("下载成功");
            }
        }
        catch (Exception ex)
        {
            _term.AppendRaw($"\r\n❌ 下载失败: {ex.Message}\r\n");
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally { _scaffold.SetLoading(false); }
    }

    private bool TryCreds(out string host, out int port, out string user, out string pass)
    {
        host = (_host.Text ?? "").Trim();
        user = (_user.Text ?? "").Trim();
        pass = _pass.Password ?? "";
        port = 22;
        if (!int.TryParse((_port.Text ?? "22").Trim(), out port) || port is < 1 or > 65535)
        {
            ToastService.Error("端口无效");
            return false;
        }
        if (string.IsNullOrEmpty(host) || string.IsNullOrEmpty(user) || string.IsNullOrEmpty(pass))
        {
            ToastService.Error("请填写主机、用户名和密码");
            return false;
        }
        return true;
    }

    private static string? PromptPath(string title, string message, string initial)
    {
        var win = new Window
        {
            Title = title,
            Width = 440,
            Height = 200,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null) win.Owner = Application.Current.MainWindow;
        var box = FormFieldFactory.TextField(initial);
        var ok = false;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 0, 0, 8)
        });
        panel.Children.Add(box);
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary("确定", (_, _) => { ok = true; win.Close(); }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        return ok ? box.Text : null;
    }

    private void OnWsText(string text)
    {
        Dispatcher.Invoke(() =>
        {
            var payload = text;
            try
            {
                var root = JsonUtil.Obj(System.Text.Encoding.UTF8.GetBytes(text));
                if (root != null && root.TryGetValue("data", out var data))
                {
                    payload = data.ValueKind == System.Text.Json.JsonValueKind.String
                        ? data.GetString() ?? ""
                        : data.ToString();
                }
            }
            catch { /* raw PTY text */ }

            _term.AppendRaw(payload);

            if (payload.Contains("SSH conn error", StringComparison.OrdinalIgnoreCase) ||
                payload.Contains("❌"))
            {
                if (payload.Contains("SSH conn error", StringComparison.OrdinalIgnoreCase))
                {
                    _connected = false;
                    _term.IsInteractive = false;
                    _status.Text = "连接失败";
                }
            }
            else if (!_connected &&
                     (payload.Contains("SSH conn success", StringComparison.OrdinalIgnoreCase) ||
                      payload.Contains("✅") ||
                      payload.Length > 0))
            {
                // first traffic ⇒ connected (align Mac/Web)
                if (!payload.Contains("❌", StringComparison.Ordinal))
                {
                    _connected = true;
                    _term.IsInteractive = true;
                    _status.Text = "已连接";
                    _ = SendResizeAsync(_cols, _rows, force: true);
                    _term.FocusTerm();
                }
            }
        });
    }
}
