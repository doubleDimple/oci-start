using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OciStart.Common.Components;

namespace OciStart.Features.MultiCloud;

/// <summary>
/// Azure / AWS 原生页壳：服务端尚无 REST 控制器时展示结构化空态（非 FTL WebView）。
/// 后端 SPI 就绪后在此替换为真实列表。
/// </summary>
public sealed class MultiCloudComingSoonView : UserControl
{
    public MultiCloudComingSoonView(string title, string provider, string webPath, params string[] capabilities)
    {
        var scaffold = new PageScaffold
        {
            Title = title,
            Subtitle = $"{provider} · 原生壳已就绪 · 等待服务端 API"
        };

        var accent = Color.FromRgb(0x4a, 0x9e, 0xff);
        var statusCard = new ModuleSettingsCard(
            "接入状态",
            "客户端路由与导航已原生落地",
            "☁",
            accent,
            showToggle: false,
            minHeight: 380);
        statusCard.SetBody(
            InfoLine("云厂商", provider),
            InfoLine("Web 路径", webPath),
            InfoLine("后端", "当前 oci-server 无 /azure/* · /aws/* 控制器"),
            InfoLine("策略", "禁止业务整页 WebView；待 SPI + REST 后接列表/操作"),
            new TextBlock
            {
                Text = "已实现：GCP 账户（tenants cloudType=2）与 GCP 实例（/other/instances/*）。\nAzure / AWS 与 GCP 对齐后再扩展。",
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 12, 0, 0),
                Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
            });

        var capCard = new ModuleSettingsCard(
            "规划能力",
            "对标侧栏菜单与 Web 占位路径",
            "▦",
            accent,
            showToggle: false,
            minHeight: 380);
        var capStack = new StackPanel();
        if (capabilities.Length == 0)
            capStack.Children.Add(InfoLine("—", "待产品定义"));
        else
        {
            foreach (var c in capabilities)
                capStack.Children.Add(new TextBlock
                {
                    Text = "·  " + c,
                    FontSize = 13,
                    Margin = new Thickness(0, 0, 0, 8),
                    Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush")
                });
        }
        capCard.SetBody(capStack);

        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(16),
            Content = new StackPanel
            {
                Children =
                {
                    new EqualHeightCardRow(statusCard, capCard, 380)
                }
            }
        };
        scaffold.SetBody(scroll);
        Content = scaffold;
    }

    private static UIElement InfoLine(string label, string value)
    {
        var sp = new StackPanel { Margin = new Thickness(0, 0, 0, 10) };
        sp.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 11,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 0, 0, 4)
        });
        sp.Children.Add(new TextBlock
        {
            Text = value,
            FontSize = 13,
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextPrimaryBrush")
        });
        return sp;
    }
}
