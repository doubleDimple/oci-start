using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using OciStart.Core;

namespace OciStart.Common.Components;

public static class ListPageHelper
{
    public static DataGrid CreateGrid()
    {
        return new DataGrid
        {
            AutoGenerateColumns = false,
            IsReadOnly = true,
            HeadersVisibility = DataGridHeadersVisibility.Column,
            GridLinesVisibility = DataGridGridLinesVisibility.Horizontal,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            RowBackground = Brushes.Transparent,
            AlternatingRowBackground = new SolidColorBrush(Color.FromArgb(0x18, 0xFF, 0xFF, 0xFF)),
            Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush"),
            SelectionMode = DataGridSelectionMode.Single
        };
    }

    public static DataGridTextColumn Col(string header, string path, double width = 100, bool star = false)
    {
        return new DataGridTextColumn
        {
            Header = header,
            Binding = new Binding(path),
            Width = star
                ? new DataGridLength(1, DataGridLengthUnitType.Star)
                : new DataGridLength(width)
        };
    }

    public static TextBlock PageInfo() => new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(12, 0, 0, 0)
    };

    public static StackPanel TopBar(params UIElement[] children)
    {
        var bar = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(16, 8, 16, 8)
        };
        foreach (var c in children)
        {
            if (c is FrameworkElement fe && fe.Margin == new Thickness(0))
                fe.Margin = new Thickness(0, 0, 8, 0);
            bar.Children.Add(c);
        }
        return bar;
    }

    public static UserControl Wrap(PageScaffold scaffold, UIElement topBar, UIElement body)
    {
        var root = new DockPanel();
        DockPanel.SetDock((UIElement)topBar, Dock.Top);
        root.Children.Add(topBar);
        root.Children.Add(body);
        scaffold.SetBody(root);
        return scaffold;
    }

    public static async Task SafeLoad(PageScaffold scaffold, Func<Task> action)
    {
        scaffold.SetLoading(true);
        scaffold.SetError(null);
        try
        {
            await action().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            scaffold.SetError(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            scaffold.SetLoading(false);
        }
    }
}

public static class JsonPage
{
    /// <summary>Parse Spring/MyBatis page: content/list/records + totalElements/total/pages.</summary>
    public static (List<Dictionary<string, System.Text.Json.JsonElement>> rows, int page, int pages, long total) Parse(
        byte[] raw,
        string[]? arrayKeys = null)
    {
        var root = JsonUtil.Obj(raw) ?? new Dictionary<string, System.Text.Json.JsonElement>();
        // unwrap data
        if (root.TryGetValue("data", out var dataEl) && dataEl.ValueKind == System.Text.Json.JsonValueKind.Object)
            root = JsonUtil.ToDict(dataEl);

        arrayKeys ??= ["content", "list", "records", "rows", "items"];
        System.Text.Json.JsonElement arr = default;
        var found = false;
        foreach (var k in arrayKeys)
        {
            if (root.TryGetValue(k, out arr) && arr.ValueKind == System.Text.Json.JsonValueKind.Array)
            {
                found = true;
                break;
            }
        }

        // root itself array
        if (!found)
        {
            try
            {
                using var doc = System.Text.Json.JsonDocument.Parse(raw);
                if (doc.RootElement.ValueKind == System.Text.Json.JsonValueKind.Array)
                {
                    arr = doc.RootElement.Clone();
                    found = true;
                }
            }
            catch { /* ignore */ }
        }

        var rows = new List<Dictionary<string, System.Text.Json.JsonElement>>();
        if (found)
        {
            foreach (var el in arr.EnumerateArray())
            {
                if (el.ValueKind == System.Text.Json.JsonValueKind.Object)
                    rows.Add(JsonUtil.ToDict(el));
            }
        }

        var page = JsonUtil.Int(root, "currentPage", JsonUtil.Int(root, "number", JsonUtil.Int(root, "page", 0)));
        var pages = JsonUtil.Int(root, "totalPages", JsonUtil.Int(root, "pages", 1));
        var total = JsonUtil.Int64(root, "totalElements", JsonUtil.Int64(root, "total", rows.Count));
        if (pages <= 0) pages = 1;
        return (rows, page, pages, total);
    }

    public static string Pick(Dictionary<string, System.Text.Json.JsonElement> m, params string[] keys)
    {
        foreach (var k in keys)
        {
            var s = JsonUtil.Str(m, k);
            if (!string.IsNullOrEmpty(s)) return s;
        }
        return "";
    }
}
