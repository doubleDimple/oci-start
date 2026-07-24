using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Memo;

public sealed class MemoItem
{
    public long Id { get; set; }
    public string Title { get; set; } = "";
    public string Summary { get; set; } = "";
    public string Content { get; set; } = "";
}

public sealed class MemoView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly ListBox _list = new();

    public MemoView()
    {
        _scaffold.Title = "备忘管理";
        _scaffold.Subtitle = "本地备忘录";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("刷新", async (_, _) => await LoadAsync()));

        _list.Background = Brushes.Transparent;
        _list.BorderThickness = new Thickness(0);
        _list.Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush");
        _list.ItemTemplate = CreateItemTemplate();

        var bar = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 8, 16, 8) };
        bar.Children.Add(FormFieldFactory.Primary("新建", async (_, _) => await CreateAsync()));
        bar.Children.Add(FormFieldFactory.Secondary("删除选中", async (_, _) => await DeleteAsync()));

        var root = new DockPanel();
        DockPanel.SetDock(bar, Dock.Top);
        root.Children.Add(bar);
        root.Children.Add(_list);
        _scaffold.SetBody(root);
        Content = _scaffold;
        Loaded += async (_, _) => await LoadAsync();
    }

    private static DataTemplate CreateItemTemplate()
    {
        var template = new DataTemplate(typeof(MemoItem));
        var factory = new FrameworkElementFactory(typeof(StackPanel));
        factory.SetValue(StackPanel.MarginProperty, new Thickness(12, 10, 12, 10));

        var title = new FrameworkElementFactory(typeof(TextBlock));
        title.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(nameof(MemoItem.Title)));
        title.SetValue(TextBlock.FontWeightProperty, FontWeights.SemiBold);
        title.SetValue(TextBlock.FontSizeProperty, 14.0);

        var summary = new FrameworkElementFactory(typeof(TextBlock));
        summary.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(nameof(MemoItem.Summary)));
        summary.SetValue(TextBlock.MarginProperty, new Thickness(0, 4, 0, 0));
        summary.SetValue(TextBlock.ForegroundProperty, Application.Current.FindResource("TextSecondaryBrush"));
        summary.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap);

        factory.AppendChild(title);
        factory.AppendChild(summary);
        template.VisualTree = factory;
        return template;
    }

    private async Task LoadAsync()
    {
        _scaffold.SetLoading(true);
        _scaffold.SetError(null);
        try
        {
            var raw = await _api.GetJsonAsync("/api/memos").ConfigureAwait(true);
            var items = ParseList(raw);
            _list.ItemsSource = items;
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

    private static List<MemoItem> ParseList(byte[] raw)
    {
        var list = new List<MemoItem>();
        // may be array or {data:[...]} or {content:[...]}
        try
        {
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            JsonElement arr = root;
            if (root.ValueKind == JsonValueKind.Object)
            {
                if (root.TryGetProperty("data", out var d)) arr = d;
                else if (root.TryGetProperty("content", out var c)) arr = c;
            }
            if (arr.ValueKind != JsonValueKind.Array) return list;
            foreach (var el in arr.EnumerateArray())
            {
                if (el.ValueKind != JsonValueKind.Object) continue;
                var m = JsonUtil.ToDict(el);
                list.Add(new MemoItem
                {
                    Id = JsonUtil.Int64(m, "id"),
                    Title = JsonUtil.Str(m, "title"),
                    Summary = JsonUtil.Str(m, "summary"),
                    Content = JsonUtil.Str(m, "content")
                });
            }
        }
        catch
        {
            // ignore
        }
        return list;
    }

    private async Task CreateAsync()
    {
        var title = Prompt("新建备忘", "标题", "新备忘");
        if (string.IsNullOrWhiteSpace(title)) return;
        try
        {
            await _api.PostJsonAsync("/api/memos", new
            {
                title,
                summary = "",
                content = ""
            }).ConfigureAwait(true);
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
    }

    private static string? Prompt(string title, string label, string initial)
    {
        var win = new Window
        {
            Title = title,
            Width = 360,
            Height = 160,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null)
            win.Owner = Application.Current.MainWindow;

        var box = FormFieldFactory.TextField(initial);
        var ok = false;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = label,
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
        buttons.Children.Add(FormFieldFactory.Primary("确定", (_, _) =>
        {
            ok = true;
            win.Close();
        }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        return ok ? box.Text?.Trim() : null;
    }

    private async Task DeleteAsync()
    {
        if (_list.SelectedItem is not MemoItem item) { ToastService.Info("请先选择"); return; }
        try
        {
            await _api.DeleteJsonAsync($"/api/memos/{item.Id}").ConfigureAwait(true);
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
    }
}
