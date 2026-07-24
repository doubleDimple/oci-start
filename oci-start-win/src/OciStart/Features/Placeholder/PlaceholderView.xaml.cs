using System.Windows.Controls;
using OciStart.Navigation;

namespace OciStart.Features.Placeholder;

public partial class PlaceholderView : UserControl
{
    public PlaceholderView(string title, string webPath, NavId nav)
    {
        InitializeComponent();
        TitleText.Text = title;
        PathText.Text = $"NavId={nav}  ·  webPath={webPath}";
        SubtitleText.Text = nav == NavId.IpQuality
            ? "质量管理是 UI 基准页（Phase 1 优先实现），见 tasks/windows-ui-standard.md。"
            : "此页面将在后续 Phase 以原生 WPF 实现，对齐 oci-start-mac。禁止整页 WebView。";
    }
}
