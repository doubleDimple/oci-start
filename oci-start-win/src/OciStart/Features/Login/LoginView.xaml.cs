using System.Windows;
using System.Windows.Controls;
using OciStart.Core;

namespace OciStart.Features.Login;

public partial class LoginView : UserControl
{
    public event EventHandler? LoginSucceeded;

    private readonly AppSession _session = AppSession.Shared;
    private readonly BackendController _backend = BackendController.Shared;
    private readonly AuthService _auth = new();

    public LoginView()
    {
        InitializeComponent();
        _backend.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(BackendController.StatusText)
                or nameof(BackendController.State))
            {
                Dispatcher.Invoke(RefreshStatus);
            }
        };
        LoadFromSession();
    }

    private void LoadFromSession()
    {
        ServerUrlBox.Text = _session.ServerUrl;
        UserBox.Text = _session.Username;
        RefreshModeButtons();
        RefreshStatus();

        if (_session.HasChosenDeploymentMode)
            _ = ActivateRestoredModeAsync();
        else
            StatusText.Text = "首次使用：请选择本机内嵌或远程服务器。";
    }

    private async Task ActivateRestoredModeAsync()
    {
        _session.SetDeploymentMode(_session.DeploymentMode, userChosen: false);
        ServerUrlBox.Text = _session.ServerUrl;
        ServerUrlBox.IsEnabled = _session.IsRemoteDeployment;
        RefreshModeButtons();

        if (_session.DeploymentMode == DeploymentMode.Local)
            await _backend.StartAsync().ConfigureAwait(true);
        else
            RefreshStatus();
    }

    private void RefreshModeButtons()
    {
        var local = _session.DeploymentMode == DeploymentMode.Local;
        LocalModeButton.Opacity = local ? 1.0 : 0.55;
        RemoteModeButton.Opacity = local ? 0.55 : 1.0;
        ServerUrlBox.IsEnabled = !local;
        if (local)
            ServerUrlBox.Text = AppPaths.LocalDefaultUrl;
    }

    private void RefreshStatus()
    {
        StatusText.Text = _session.IsRemoteDeployment
            ? $"远程模式 · {_session.ServerUrl}"
            : _backend.StatusText;
    }

    private async void OnLocalMode(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
        _session.SetDeploymentMode(DeploymentMode.Local);
        ServerUrlBox.Text = AppPaths.LocalDefaultUrl;
        RefreshModeButtons();
        await _backend.StartAsync().ConfigureAwait(true);
        RefreshStatus();
    }

    private void OnRemoteMode(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
        _backend.Stop();
        _session.SetDeploymentMode(DeploymentMode.Remote);
        ServerUrlBox.Text = _session.LastRemoteServerUrl == "https://"
            ? "https://"
            : _session.LastRemoteServerUrl;
        RefreshModeButtons();
        RefreshStatus();
    }

    private async void OnEnter(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;

        if (!_session.HasChosenDeploymentMode && !_session.ModeActivated)
        {
            ShowError("请先选择本机内嵌或远程服务器。");
            return;
        }

        if (_session.IsRemoteDeployment)
        {
            var url = AppSession.Normalize(ServerUrlBox.Text);
            if (AppSession.IsLocalServerUrl(url) || url is "https://" or "http://")
            {
                ShowError("请填写有效的远程服务器地址（含端口）。");
                return;
            }
            _session.ServerUrl = url;
            ServerUrlBox.Text = _session.ServerUrl;
        }
        else
        {
            if (!_backend.IsReadyForLogin)
            {
                StatusText.Text = "正在启动本机后端…";
                await _backend.StartAsync().ConfigureAwait(true);
            }
            if (_backend.State.Status == BackendStatus.Failed)
            {
                ShowError(_backend.State.ErrorMessage ?? "后端启动失败");
                return;
            }
        }

        var user = (UserBox.Text ?? "").Trim();
        var pass = PassBox.Password ?? "";
        if (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(pass))
        {
            ShowError("请输入用户名和密码。");
            return;
        }

        _session.SetBusy(true);
        StatusText.Text = "正在登录…";
        try
        {
            await _auth.LoginAsync(user, pass).ConfigureAwait(true);
            _session.MarkLoggedIn(user);
            LoginSucceeded?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            ShowError(ex is ApiError ae ? ae.Message : ex.Message);
            RefreshStatus();
        }
        finally
        {
            _session.SetBusy(false);
        }
    }

    private void ShowError(string msg)
    {
        ErrorText.Text = msg;
        ErrorText.Visibility = Visibility.Visible;
    }
}
