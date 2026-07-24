using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.AiChat;

public sealed class AiChatView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly TextBox _history = new()
    {
        IsReadOnly = true,
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        FontSize = 13,
        Background = (Brush)Application.Current.FindResource("CardBgBrush"),
        Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush"),
        Margin = new Thickness(16, 16, 16, 8)
    };
    private readonly TextBox _input = FormFieldFactory.TextField(watermark: "输入消息…");

    public AiChatView()
    {
        _scaffold.Title = "AI 对话";
        _scaffold.Subtitle = "与已配置模型对话";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("清空", (_, _) => _history.Clear()));

        var sendBar = ListPageHelper.TopBar(
            _input,
            FormFieldFactory.Primary("发送", async (_, _) => await SendAsync()));
        _input.Width = 480;
        _input.MinWidth = 320;

        var root = new DockPanel();
        DockPanel.SetDock(sendBar, Dock.Bottom);
        root.Children.Add(sendBar);
        root.Children.Add(_history);
        _scaffold.SetBody(root);
        Content = _scaffold;
    }

    private async Task SendAsync()
    {
        var text = (_input.Text ?? "").Trim();
        if (string.IsNullOrEmpty(text)) return;
        Append("你", text);
        _input.Text = "";
        try
        {
            byte[] raw;
            try
            {
                raw = await _api.PostJsonAsync("/ai/chat", new { message = text, content = text }).ConfigureAwait(true);
            }
            catch
            {
                raw = await _api.PostJsonAsync("/api/ai/chat", new { message = text, prompt = text }).ConfigureAwait(true);
            }

            var root = JsonUtil.Obj(raw);
            var reply = "";
            if (root != null)
            {
                reply = JsonPage.Pick(root, "message", "reply", "content", "answer", "data");
                if (root.TryGetValue("data", out var data))
                {
                    if (data.ValueKind == System.Text.Json.JsonValueKind.String)
                        reply = data.GetString() ?? reply;
                    else if (data.ValueKind == System.Text.Json.JsonValueKind.Object)
                        reply = JsonPage.Pick(JsonUtil.ToDict(data), "message", "content", "reply", "answer");
                }
            }
            if (string.IsNullOrEmpty(reply))
                reply = Encoding.UTF8.GetString(raw);
            Append("AI", reply);
        }
        catch (Exception ex)
        {
            Append("系统", ex is ApiError ae ? ae.Message : ex.Message);
        }
    }

    private void Append(string who, string msg)
    {
        _history.AppendText($"[{who}] {msg}{Environment.NewLine}{Environment.NewLine}");
        _history.ScrollToEnd();
    }
}
