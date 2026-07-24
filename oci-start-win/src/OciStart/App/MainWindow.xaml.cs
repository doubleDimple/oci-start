using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Core;
using OciStart.Features.Login;
using OciStart.Navigation;

namespace OciStart.App;

public partial class MainWindow : Window
{
    private readonly AppSession _session = AppSession.Shared;
    private readonly NavigationState _nav = NavigationState.Shared;
    private readonly AuthService _auth = new();
    private LoginView? _loginView;

    public MainWindow()
    {
        InitializeComponent();
        ApiClient.Shared.Unauthorized += () => Dispatcher.Invoke(() =>
        {
            _session.Logout();
            ShowLogin();
        });
        ShowLogin();
    }

    private void ShowLogin()
    {
        ShellHost.Visibility = Visibility.Collapsed;
        LoginHost.Visibility = Visibility.Visible;
        LoginHost.Children.Clear();
        _loginView = new LoginView();
        _loginView.LoginSucceeded += (_, _) => ShowShell();
        LoginHost.Children.Add(_loginView);
    }

    private void ShowShell()
    {
        LoginHost.Visibility = Visibility.Collapsed;
        LoginHost.Children.Clear();
        _loginView = null;
        ShellHost.Visibility = Visibility.Visible;
        InitCloudBox();
        SidebarUserText.Text = $"{_session.Username} · {_session.CloudProviderName}";
        RebuildNav();
        NavigateTo(_nav.SelectedNav == default ? NavId.Dashboard : _nav.SelectedNav);
    }

    private static readonly (int Type, string Title)[] CloudOptions =
    [
        (1, "Oracle Cloud"),
        (2, "Google Cloud"),
        (3, "Azure"),
        (4, "AWS")
    ];

    private bool _cloudBoxReady;

    private void InitCloudBox()
    {
        _cloudBoxReady = false;
        CloudBox.ItemsSource = CloudOptions.Select(c => c.Title).ToList();
        var idx = Array.FindIndex(CloudOptions, c => c.Type == _session.CloudProvider);
        CloudBox.SelectedIndex = idx >= 0 ? idx : 0;
        _cloudBoxReady = true;
    }

    private void OnCloudChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_cloudBoxReady) return;
        var i = CloudBox.SelectedIndex;
        if (i < 0 || i >= CloudOptions.Length) return;
        var type = CloudOptions[i].Type;
        if (type == _session.CloudProvider) return;
        _session.CloudProvider = type;
        SidebarUserText.Text = $"{_session.Username} · {_session.CloudProviderName}";
        // Prefer first menu of current cloud; fallback dashboard
        var filtered = NavigationCatalog.Filtered("", type);
        var first = filtered.SelectMany(s => s.Items).FirstOrDefault();
        NavigateTo(first?.Nav ?? NavId.Dashboard);
    }

    private void RebuildNav()
    {
        NavPanel.Children.Clear();
        var filtered = NavigationCatalog.Filtered(SearchBox.Text ?? "", _session.CloudProvider);

        foreach (var (section, items) in filtered)
        {
            var header = new TextBlock
            {
                Text = section.Title(),
                Foreground = (Brush)FindResource("TextSecondaryBrush"),
                FontSize = 11,
                Margin = new Thickness(12, 12, 12, 4),
                FontWeight = FontWeights.SemiBold
            };
            NavPanel.Children.Add(header);

            foreach (var item in items)
            {
                var btn = new Button
                {
                    Content = $"{item.IconGlyph}  {item.Title}",
                    Style = (Style)FindResource("SidebarNavButton"),
                    Tag = item.Nav,
                    Margin = new Thickness(4, 1, 4, 1)
                };
                if (item.Nav == _nav.SelectedNav)
                    btn.Background = new SolidColorBrush(Color.FromArgb(0x33, 0x3B, 0x82, 0xF6));
                btn.Click += (_, _) =>
                {
                    if (btn.Tag is NavId id)
                        NavigateTo(id);
                };
                NavPanel.Children.Add(btn);
            }
        }
    }

    private void NavigateTo(NavId nav)
    {
        _nav.SelectedNav = nav;
        ContentHost.Children.Clear();
        ContentHost.Children.Add(FeatureRouter.CreateView(nav));
        RebuildNav();
    }

    private void OnSearchChanged(object sender, TextChangedEventArgs e) => RebuildNav();

    private async void OnLogout(object sender, RoutedEventArgs e)
    {
        try { await _auth.LogoutAsync().ConfigureAwait(true); }
        catch { /* ignore */ }
        _session.Logout();
        ShowLogin();
    }
}
