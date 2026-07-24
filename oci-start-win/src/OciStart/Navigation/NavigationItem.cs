namespace OciStart.Navigation;

public sealed class NavigationItem
{
    public NavigationItem(
        NavId nav,
        string title,
        string iconGlyph,
        string webPath,
        IReadOnlySet<int>? cloudTypes = null)
    {
        Nav = nav;
        Title = title;
        IconGlyph = iconGlyph;
        WebPath = webPath;
        CloudTypes = cloudTypes;
    }

    public NavId Nav { get; }
    public string Title { get; }
    /// <summary>Segoe MDL2 / fluent glyph or short emoji placeholder for Phase 0.</summary>
    public string IconGlyph { get; }
    public string WebPath { get; }
    /// <summary>null = always visible; else 1=OCI 2=GCP 3=Azure 4=AWS</summary>
    public IReadOnlySet<int>? CloudTypes { get; }
}
