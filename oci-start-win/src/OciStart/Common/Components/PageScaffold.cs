using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace OciStart.Common.Components;

/// <summary>Page header + toolbar + content (align Mac PageScaffold).</summary>
public sealed class PageScaffold : UserControl
{
    private readonly TextBlock _title;
    private readonly TextBlock _subtitle;
    private readonly StackPanel _toolbar;
    private readonly Grid _contentHost;
    private readonly Border _loadingOverlay;
    private readonly TextBlock _errorBanner;

    public PageScaffold()
    {
        var root = new Grid { Background = Brushes.Transparent };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var header = new DockPanel { Margin = new Thickness(16, 16, 16, 8) };
        var titles = new StackPanel();
        _title = new TextBlock
        {
            FontSize = 20,
            FontWeight = FontWeights.SemiBold,
            Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush")
        };
        _subtitle = new TextBlock
        {
            FontSize = 12,
            Margin = new Thickness(0, 4, 0, 0),
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            TextWrapping = TextWrapping.Wrap
        };
        titles.Children.Add(_title);
        titles.Children.Add(_subtitle);
        DockPanel.SetDock(titles, Dock.Left);
        header.Children.Add(titles);

        _toolbar = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        header.Children.Add(_toolbar);
        Grid.SetRow(header, 0);
        root.Children.Add(header);

        _errorBanner = new TextBlock
        {
            Margin = new Thickness(16, 0, 16, 8),
            Padding = new Thickness(12, 8, 12, 8),
            Background = new SolidColorBrush(Color.FromArgb(0x33, 0xEF, 0x44, 0x44)),
            Foreground = (Brush)Application.Current.FindResource("DangerBrush"),
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed
        };
        Grid.SetRow(_errorBanner, 1);
        root.Children.Add(_errorBanner);

        _contentHost = new Grid();
        Grid.SetRow(_contentHost, 2);
        root.Children.Add(_contentHost);

        _loadingOverlay = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0x66, 0x12, 0x14, 0x1A)),
            Visibility = Visibility.Collapsed,
            Child = new TextBlock
            {
                Text = "加载中…",
                Foreground = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                FontSize = 14
            }
        };
        Grid.SetRowSpan(_loadingOverlay, 3);
        root.Children.Add(_loadingOverlay);

        Content = root;
    }

    public string Title
    {
        get => _title.Text;
        set => _title.Text = value;
    }

    public string Subtitle
    {
        get => _subtitle.Text;
        set => _subtitle.Text = value;
    }

    public void SetToolbar(params UIElement[] elements)
    {
        _toolbar.Children.Clear();
        foreach (var e in elements)
        {
            if (e is FrameworkElement fe)
                fe.Margin = new Thickness(8, 0, 0, 0);
            _toolbar.Children.Add(e);
        }
    }

    public void SetBody(UIElement body)
    {
        _contentHost.Children.Clear();
        _contentHost.Children.Add(body);
    }

    public void SetError(string? message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            _errorBanner.Visibility = Visibility.Collapsed;
            _errorBanner.Text = "";
            return;
        }
        _errorBanner.Text = message;
        _errorBanner.Visibility = Visibility.Visible;
    }

    public void SetLoading(bool loading) =>
        _loadingOverlay.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
}
