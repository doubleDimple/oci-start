using System;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
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
                Dispatcher.Invoke(RefreshStatusAndBootState);
            }
        };
        LoadFromSession();
        PopulateRegionDirectory();
    }

    private void PopulateRegionDirectory()
    {
        RegionDirectoryItems.ItemsSource = LoginPublicRegion.All.Select(r => new
        {
            DisplayTitle = $"{r.Zh} ({r.En})",
            r.Id,
            r.Coordinates
        }).ToList();
    }

    private void LoadFromSession()
    {
        ServerUrlBox.Text = _session.ServerUrl;
        UserBox.Text = _session.Username;
        RefreshModeButtons();
        RefreshStatusAndBootState();

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

        RefreshStatusAndBootState();
    }

    private void RefreshModeButtons()
    {
        var local = _session.DeploymentMode == DeploymentMode.Local;
        LocalModeButton.Style = (Style)FindResource(local ? "PrimaryButton" : "SecondaryButton");
        RemoteModeButton.Style = (Style)FindResource(local ? "SecondaryButton" : "PrimaryButton");
        ServerUrlBox.IsEnabled = !local;
        ServerUrlLabel.Opacity = local ? 0.5 : 1.0;
        if (local)
            ServerUrlBox.Text = AppPaths.LocalDefaultUrl;
    }

    private void RefreshStatusAndBootState()
    {
        var isLocal = _session.DeploymentMode == DeploymentMode.Local;

        if (isLocal)
        {
            switch (_backend.State.Status)
            {
                case BackendStatus.Starting:
                    BootLoadingPanel.Visibility = Visibility.Visible;
                    BootFailedPanel.Visibility = Visibility.Collapsed;
                    FormFieldsPanel.Opacity = 0.5;
                    FormFieldsPanel.IsEnabled = false;
                    StatusText.Text = "正在启动本机后端服务…";
                    break;

                case BackendStatus.Failed:
                    BootLoadingPanel.Visibility = Visibility.Collapsed;
                    BootFailedPanel.Visibility = Visibility.Visible;
                    BootFailedErrorText.Text = _backend.State.ErrorMessage ?? "未知网络或服务故障";
                    FormFieldsPanel.Opacity = 0.5;
                    FormFieldsPanel.IsEnabled = false;
                    StatusText.Text = "服务启动失败";
                    break;

                default:
                    BootLoadingPanel.Visibility = Visibility.Collapsed;
                    BootFailedPanel.Visibility = Visibility.Collapsed;
                    FormFieldsPanel.Opacity = 1.0;
                    FormFieldsPanel.IsEnabled = true;
                    StatusText.Text = _backend.StatusText;
                    break;
            }
        }
        else
        {
            BootLoadingPanel.Visibility = Visibility.Collapsed;
            BootFailedPanel.Visibility = Visibility.Collapsed;
            FormFieldsPanel.Opacity = 1.0;
            FormFieldsPanel.IsEnabled = true;
            StatusText.Text = $"远程模式 · {_session.ServerUrl}";
        }
    }

    private async void OnLocalMode(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
        _session.SetDeploymentMode(DeploymentMode.Local);
        ServerUrlBox.Text = AppPaths.LocalDefaultUrl;
        RefreshModeButtons();
        await _backend.StartAsync().ConfigureAwait(true);
        RefreshStatusAndBootState();
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
        RefreshStatusAndBootState();
    }

    private async void OnRetryStartLocal(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
        await _backend.StartAsync().ConfigureAwait(true);
        RefreshStatusAndBootState();
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
        EnterButton.IsEnabled = false;
        try
        {
            await _auth.LoginAsync(user, pass).ConfigureAwait(true);
            _session.MarkLoggedIn(user);
            LoginSucceeded?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            ShowError(ex is ApiError ae ? ae.Message : ex.Message);
            RefreshStatusAndBootState();
        }
        finally
        {
            _session.SetBusy(false);
            EnterButton.IsEnabled = true;
        }
    }

    private void ShowError(string msg)
    {
        ErrorText.Text = msg;
        ErrorText.Visibility = Visibility.Visible;
    }

    // Modal Region Directory
    private void OnToggleRegionDirectory(object sender, RoutedEventArgs e)
    {
        RegionDirectoryModal.Visibility = Visibility.Visible;
    }

    private void OnCloseRegionDirectory(object sender, RoutedEventArgs e)
    {
        RegionDirectoryModal.Visibility = Visibility.Collapsed;
    }

    private void OnModalContentClick(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true; // prevent outer grid click from closing
    }

    // External Link Handlers
    private void OnOpenGithub(object sender, MouseButtonEventArgs e) =>
        OpenUrl("https://github.com/doubleDimple/oci-start");

    private void OnOpenDocs(object sender, MouseButtonEventArgs e) =>
        OpenUrl("https://github.com/doubleDimple/oci-start#readme");

    private void OnOpenOracleDocs(object sender, MouseButtonEventArgs e) =>
        OpenUrl("https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm");

    private void OnOpenGeoNames(object sender, MouseButtonEventArgs e) =>
        OpenUrl("https://www.geonames.org/");

    private static void OpenUrl(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch { }
    }
}
