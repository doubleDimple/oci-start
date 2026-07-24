using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace OciStart.Common.Components;

/// <summary>
/// Standard module card: fixed header + body + footer.
/// Align Mac ModuleSettingsCard / windows-ui-standard.
/// </summary>
public sealed class ModuleSettingsCard : Border
{
    private readonly TextBlock _title;
    private readonly TextBlock _subtitle;
    private readonly CheckBox? _enabledToggle;
    private readonly StackPanel _body;
    private readonly StackPanel _footer;
    private readonly Brush _accent;
    private readonly double _minHeight;

    public ModuleSettingsCard(
        string title,
        string subtitle,
        string glyph,
        Color accent,
        bool showToggle,
        double minHeight = 380)
    {
        _minHeight = minHeight;
        _accent = new SolidColorBrush(accent);
        CornerRadius = new CornerRadius(14);
        Background = (Brush)Application.Current.FindResource("SidebarBgBrush");
        BorderThickness = new Thickness(1);
        BorderBrush = (Brush)Application.Current.FindResource("AppBorderBrush");
        MinHeight = minHeight;
        Margin = new Thickness(0);
        SnapsToDevicePixels = true;

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(64) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(56) });

        // Header
        var header = new DockPanel { Margin = new Thickness(16, 0, 16, 0), VerticalAlignment = VerticalAlignment.Center };
        var icon = new Border
        {
            Width = 36,
            Height = 36,
            CornerRadius = new CornerRadius(10),
            Background = new SolidColorBrush(Color.FromArgb(0x26, accent.R, accent.G, accent.B)),
            Child = new TextBlock
            {
                Text = glyph,
                Foreground = _accent,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                FontSize = 14
            }
        };
        DockPanel.SetDock(icon, Dock.Left);
        icon.Margin = new Thickness(0, 0, 10, 0);
        header.Children.Add(icon);

        if (showToggle)
        {
            _enabledToggle = new CheckBox
            {
                VerticalAlignment = VerticalAlignment.Center,
                Content = "启用"
            };
            _enabledToggle.Checked += (_, _) => UpdateChrome(true);
            _enabledToggle.Unchecked += (_, _) => UpdateChrome(false);
            DockPanel.SetDock(_enabledToggle, Dock.Right);
            header.Children.Add(_enabledToggle);
        }

        var titles = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        _title = new TextBlock
        {
            Text = title,
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush")
        };
        _subtitle = new TextBlock
        {
            Text = subtitle,
            FontSize = 11,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
        };
        titles.Children.Add(_title);
        titles.Children.Add(_subtitle);
        header.Children.Add(titles);
        Grid.SetRow(header, 0);
        root.Children.Add(header);

        // Body
        _body = new StackPanel { Margin = new Thickness(16), Orientation = Orientation.Vertical };
        var bodyScroll = new ScrollViewer
        {
            Content = _body,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        Grid.SetRow(bodyScroll, 1);
        root.Children.Add(bodyScroll);

        // Footer
        _footer = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(16, 0, 16, 0)
        };
        Grid.SetRow(_footer, 2);
        root.Children.Add(_footer);

        // Dividers via borders on body area edges — simple separator lines
        Child = root;
        UpdateChrome(false);
    }

    public bool? IsEnabledToggle
    {
        get => _enabledToggle?.IsChecked;
        set
        {
            if (_enabledToggle != null)
            {
                _enabledToggle.IsChecked = value;
                UpdateChrome(value == true);
            }
        }
    }

    public event RoutedEventHandler? EnabledChanged
    {
        add { if (_enabledToggle != null) { _enabledToggle.Checked += value; _enabledToggle.Unchecked += value; } }
        remove { if (_enabledToggle != null) { _enabledToggle.Checked -= value; _enabledToggle.Unchecked -= value; } }
    }

    public void SetBody(params UIElement[] children)
    {
        _body.Children.Clear();
        foreach (var c in children)
        {
            if (c is FrameworkElement fe && fe.Margin == new Thickness(0))
                fe.Margin = new Thickness(0, 0, 0, 12);
            _body.Children.Add(c);
        }
    }

    public void SetFooter(params UIElement[] children)
    {
        _footer.Children.Clear();
        foreach (var c in children)
        {
            if (c is FrameworkElement fe)
                fe.Margin = new Thickness(8, 0, 0, 0);
            _footer.Children.Add(c);
        }
    }

    private void UpdateChrome(bool on)
    {
        BorderBrush = on
            ? new SolidColorBrush(Color.FromArgb(0x73, ((SolidColorBrush)_accent).Color.R, ((SolidColorBrush)_accent).Color.G, ((SolidColorBrush)_accent).Color.B))
            : (Brush)Application.Current.FindResource("AppBorderBrush");
        Effect = on
            ? new System.Windows.Media.Effects.DropShadowEffect
            {
                BlurRadius = 10,
                ShadowDepth = 3,
                Opacity = 0.25,
                Color = Colors.Black
            }
            : null;
        MinHeight = _minHeight;
    }
}

/// <summary>Two equal-width columns (align Mac EqualHeightCardRow).</summary>
public sealed class EqualHeightCardRow : Grid
{
    public EqualHeightCardRow(UIElement first, UIElement second, double minHeight = 380, double spacing = 14)
    {
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(spacing) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        MinHeight = minHeight;
        Margin = new Thickness(0, 0, 0, spacing);

        if (first is FrameworkElement f1) f1.VerticalAlignment = VerticalAlignment.Stretch;
        if (second is FrameworkElement f2) f2.VerticalAlignment = VerticalAlignment.Stretch;

        Grid.SetColumn(first, 0);
        Grid.SetColumn(second, 2);
        Children.Add(first);
        Children.Add(second);
    }
}

public static class FormFieldFactory
{
    public static UIElement Labeled(string label, UIElement field)
    {
        var sp = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
        sp.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 12,
            Margin = new Thickness(0, 0, 0, 6),
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
        });
        sp.Children.Add(field);
        return sp;
    }

    public static TextBox TextField(string? text = null, string? watermark = null)
    {
        var tb = new TextBox
        {
            Text = text ?? "",
            Style = (Style)Application.Current.FindResource("AppTextBox")
        };
        if (!string.IsNullOrEmpty(watermark))
            tb.ToolTip = watermark;
        return tb;
    }

    public static PasswordBox PasswordField()
    {
        return new PasswordBox { Style = (Style)Application.Current.FindResource("AppPasswordBox") };
    }

    public static Button Primary(string title, RoutedEventHandler onClick)
    {
        var b = new Button { Content = title, Style = (Style)Application.Current.FindResource("PrimaryButton") };
        b.Click += onClick;
        return b;
    }

    public static Button Secondary(string title, RoutedEventHandler onClick)
    {
        var b = new Button { Content = title, Style = (Style)Application.Current.FindResource("SecondaryButton") };
        b.Click += onClick;
        return b;
    }

    public static ComboBox Combo(IEnumerable<string> items, string? selected = null)
    {
        var cb = new ComboBox
        {
            ItemsSource = items.ToList(),
            SelectedItem = selected,
            MinWidth = 160,
            Padding = new Thickness(8, 6, 8, 6)
        };
        return cb;
    }
}
