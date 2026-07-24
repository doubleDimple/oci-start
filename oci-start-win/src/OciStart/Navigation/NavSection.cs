namespace OciStart.Navigation;

public enum NavSection
{
    Service,
    Proxy,
    Vps,
    System,
    Tools,
    Dev
}

public static class NavSectionExtensions
{
    public static string Title(this NavSection section) => section switch
    {
        NavSection.Service => "服务管理",
        NavSection.Proxy => "代理管理",
        NavSection.Vps => "VPS 管理",
        NavSection.System => "系统管理",
        NavSection.Tools => "我的工具",
        NavSection.Dev => "开发者",
        _ => section.ToString()
    };
}
