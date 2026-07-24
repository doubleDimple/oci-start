using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace OciStart.Features.Instances;

/// <summary>Terminal theme keys (align Mac/Web terminal.theme).</summary>
public static class TerminalThemes
{
    public static readonly (string Key, string Title, Color Bg, Color Fg)[] All =
    [
        ("matrix", "Matrix", Color.FromRgb(0, 0, 0), Color.FromRgb(0, 255, 0)),
        ("tokyonight", "Tokyo Night", Color.FromRgb(0x1a, 0x1b, 0x26), Color.FromRgb(0xa9, 0xb1, 0xd6)),
        ("dracula", "Dracula", Color.FromRgb(0x28, 0x2a, 0x36), Color.FromRgb(0xf8, 0xf8, 0xf2)),
        ("nord", "Nord", Color.FromRgb(0x2e, 0x34, 0x40), Color.FromRgb(0xd8, 0xde, 0xe9)),
        ("monokai", "Monokai", Color.FromRgb(0x27, 0x28, 0x22), Color.FromRgb(0xf8, 0xf8, 0xf2)),
        ("solarizedLight", "Solarized Light", Color.FromRgb(0xfd, 0xf6, 0xe3), Color.FromRgb(0x65, 0x7b, 0x83)),
        ("highContrast", "High Contrast", Colors.Black, Colors.White)
    ];

    public static (Color Bg, Color Fg) Resolve(string key)
    {
        foreach (var t in All)
            if (string.Equals(t.Key, key, StringComparison.OrdinalIgnoreCase))
                return (t.Bg, t.Fg);
        return (All[0].Bg, All[0].Fg);
    }
}

/// <summary>Strip CSI/OSC for plain monospaced display (align Mac TerminalANSI).</summary>
public static class TerminalAnsi
{
    private static readonly Regex Csi = new(@"\u001B\[[0-9;?]*[ -/]*[@-~]", RegexOptions.Compiled);
    private static readonly Regex Osc = new(@"\u001B\][^\u0007\u001B]*(?:\u0007|\u001B\\)", RegexOptions.Compiled);

    public static string Strip(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        var outS = Csi.Replace(s, "");
        outS = Osc.Replace(outS, "");
        return outS.Replace("\u001B", "", StringComparison.Ordinal);
    }

    public static string PlainForLog(string s) =>
        Strip(s).Replace("\r\n", "\n", StringComparison.Ordinal).Replace("\r", "\n", StringComparison.Ordinal);
}

/// <summary>
/// Interactive terminal surface: monospaced TextBox, key capture, PTY size report.
/// Not full xterm (matches Mac); strips ANSI for readable shell output.
/// </summary>
public sealed class TerminalSurface : UserControl
{
    private readonly TextBox _box;
    private string _raw = "";
    private string _themeKey = "matrix";
    private double _fontSize = 14;
    private int _lastCols;
    private int _lastRows;

    public event Action<string>? Input;
    public event Action<int, int>? Resized;

    public bool IsInteractive { get; set; } = true;

    public string RawOutput => _raw;

    public string ThemeKey
    {
        get => _themeKey;
        set
        {
            _themeKey = value;
            ApplyTheme();
        }
    }

    public double TermFontSize
    {
        get => _fontSize;
        set
        {
            _fontSize = Math.Clamp(value, 10, 24);
            _box.FontSize = _fontSize;
            ReportResize();
        }
    }

    public TerminalSurface()
    {
        _box = new TextBox
        {
            IsReadOnly = true,
            AcceptsReturn = true,
            AcceptsTab = true,
            TextWrapping = TextWrapping.NoWrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            FontFamily = new FontFamily("Cascadia Mono, Consolas, Courier New"),
            FontSize = _fontSize,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(10),
            CaretBrush = Brushes.Transparent,
            Focusable = true
        };
        _box.PreviewKeyDown += OnPreviewKeyDown;
        _box.PreviewTextInput += OnPreviewTextInput;
        _box.SizeChanged += (_, _) => ReportResize();
        Content = _box;
        ApplyTheme();
        Focusable = true;
        Loaded += (_, _) =>
        {
            ReportResize();
            _box.Focus();
        };
    }

    public void FocusTerm() => _box.Focus();

    public void Clear()
    {
        _raw = "";
        _box.Text = "";
    }

    public void AppendRaw(string chunk)
    {
        if (string.IsNullOrEmpty(chunk)) return;
        _raw += chunk;
        if (_raw.Length > 400_000)
            _raw = _raw[^300_000..];
        RefreshDisplay(scroll: true);
    }

    public void SetRaw(string raw)
    {
        _raw = raw ?? "";
        RefreshDisplay(scroll: true);
    }

    public string PlainText => TerminalAnsi.PlainForLog(_raw);

    public int SearchCount(string needle)
    {
        if (string.IsNullOrEmpty(needle)) return 0;
        var plain = TerminalAnsi.Strip(_raw);
        var n = 0;
        var idx = 0;
        while (idx < plain.Length)
        {
            var found = plain.IndexOf(needle, idx, StringComparison.OrdinalIgnoreCase);
            if (found < 0) break;
            n++;
            idx = found + Math.Max(1, needle.Length);
        }
        return n;
    }

    private void RefreshDisplay(bool scroll)
    {
        var cleaned = TerminalAnsi.Strip(_raw);
        var nearBottom = true;
        try
        {
            // heuristic: caret/end selection near length
            nearBottom = _box.SelectionStart >= Math.Max(0, _box.Text.Length - 40);
        }
        catch { /* ignore */ }

        if (_box.Text != cleaned)
        {
            _box.Text = cleaned;
            if (scroll || nearBottom)
            {
                _box.CaretIndex = _box.Text.Length;
                _box.ScrollToEnd();
            }
        }
    }

    private void ApplyTheme()
    {
        var (bg, fg) = TerminalThemes.Resolve(_themeKey);
        _box.Background = new SolidColorBrush(bg);
        _box.Foreground = new SolidColorBrush(fg);
        Background = _box.Background;
    }

    public void ReportResize(bool force = false)
    {
        var w = _box.ActualWidth;
        var h = _box.ActualHeight;
        if (w < 40 || h < 40) return;
        var charW = Math.Max(_fontSize * 0.6, 7);
        var charH = Math.Max(_fontSize * 1.35, 14);
        var cols = Math.Max(40, (int)Math.Floor((w - 20) / charW));
        var rows = Math.Max(10, (int)Math.Floor((h - 20) / charH));
        if (!force && cols == _lastCols && rows == _lastRows) return;
        _lastCols = cols;
        _lastRows = rows;
        Resized?.Invoke(cols, rows);
    }

    public (int Cols, int Rows) LastSize => (_lastCols, _lastRows);

    private void OnPreviewTextInput(object sender, TextCompositionEventArgs e)
    {
        if (!IsInteractive) return;
        if (!string.IsNullOrEmpty(e.Text))
            Input?.Invoke(e.Text);
        e.Handled = true;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control) && e.Key == Key.C && _box.SelectionLength > 0)
            return; // allow copy
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control) && e.Key == Key.A)
            return;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control) && e.Key == Key.V)
        {
            if (IsInteractive)
            {
                try
                {
                    var t = Clipboard.GetText();
                    if (!string.IsNullOrEmpty(t)) Input?.Invoke(t);
                }
                catch { /* ignore */ }
            }
            e.Handled = true;
            return;
        }

        if (!IsInteractive)
        {
            e.Handled = true;
            return;
        }

        var seq = MapKey(e);
        if (seq != null)
        {
            Input?.Invoke(seq);
            e.Handled = true;
        }
        // printable handled by PreviewTextInput
    }

    private static string? MapKey(KeyEventArgs e)
    {
        // Ctrl+letter → control chars
        if (Keyboard.Modifiers == ModifierKeys.Control)
        {
            if (e.Key is >= Key.A and <= Key.Z)
            {
                var code = (char)(e.Key - Key.A + 1);
                return code.ToString();
            }
            return null;
        }

        return e.Key switch
        {
            Key.Up => "\u001b[A",
            Key.Down => "\u001b[B",
            Key.Right => "\u001b[C",
            Key.Left => "\u001b[D",
            Key.Back => "\u007f",
            Key.Delete => "\u001b[3~",
            Key.Home => "\u001b[H",
            Key.End => "\u001b[F",
            Key.PageUp => "\u001b[5~",
            Key.PageDown => "\u001b[6~",
            Key.Tab => "\t",
            Key.Enter or Key.Return => "\r",
            Key.Escape => "\u001b",
            _ => null
        };
    }
}
