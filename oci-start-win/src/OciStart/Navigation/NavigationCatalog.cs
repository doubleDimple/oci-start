namespace OciStart.Navigation;

/// <summary>
/// Single source of menu metadata. Keep aligned with
/// oci-server/.../templates/common/sidebar.ftl and oci-start-mac NavigationCatalog.
/// </summary>
public static class NavigationCatalog
{
    public static IReadOnlyList<(NavSection Section, IReadOnlyList<NavigationItem> Items)> Sections { get; } =
        new List<(NavSection, IReadOnlyList<NavigationItem>)>
        {
            (NavSection.Service, new[]
            {
                Item(NavId.Dashboard, "系统监控", "📊", "/boot/dashboard"),
                Item(NavId.Regions, "区域订阅", "🌐", "/resource/list", Cloud(1)),
                Item(NavId.Tenants, "租户管理", "👥", "/tenants/list", Cloud(1)),
                Item(NavId.Instances, "实例列表", "🖥", "/oci/list", Cloud(1)),
                Item(NavId.Email, "邮件管理", "✉", "/email/management", Cloud(1)),
                Item(NavId.Storage, "对象存储", "📦", "/oci/storage/page", Cloud(1)),
                Item(NavId.Boot, "开机管理", "▶", "/boot/fullBootList", Cloud(1)),
                Item(NavId.Ai, "OCI AI 管理", "✨", "/system/ai/models", Cloud(1)),
                Item(NavId.SpeedTest, "延迟测试", "⏱", "/delayTest", Cloud(1)),
                Item(NavId.OpenLogs, "开机日志", "📄", "/system/openLogs", Cloud(1)),
                Item(NavId.GcpAccounts, "GCP 账户", "G", "/tenants/list", Cloud(2)),
                Item(NavId.GcpInstances, "GCP 实例", "🖥", "/other/instances/list", Cloud(2)),
                Item(NavId.AzureVms, "Azure 虚拟机", "☁", "/azure/vms", Cloud(3)),
                Item(NavId.AzureResources, "Azure 资源", "▦", "/azure/resources", Cloud(3)),
                Item(NavId.AzureStorage, "Azure 存储", "📦", "/azure/storage", Cloud(3)),
                Item(NavId.AzureNetworks, "Azure 网络", "🔗", "/azure/networks", Cloud(3)),
                Item(NavId.AwsEc2, "AWS EC2", "🖥", "/aws/ec2", Cloud(4)),
                Item(NavId.AwsS3, "AWS S3", "☁", "/aws/s3", Cloud(4)),
                Item(NavId.AwsLambda, "AWS Lambda", "λ", "/aws/lambda", Cloud(4)),
                Item(NavId.AwsRds, "AWS RDS", "🗄", "/aws/rds", Cloud(4))
            }),
            (NavSection.Proxy, new[]
            {
                Item(NavId.KeyConfig, "密钥配置", "🔑", "/system/domainSettings"),
                Item(NavId.Cloudflare, "Cloudflare", "CF", "/dns/cloudflare"),
                Item(NavId.EdgeOne, "EdgeOne", "EO", "/dns/edgeone")
            }),
            (NavSection.Vps, new[]
            {
                Item(NavId.VpsList, "监控看板", "🖥", "/vps/instances/list")
            }),
            (NavSection.System, new[]
            {
                Item(NavId.IpQuality, "质量管理", "🛡", "/system/ipSettings", Cloud(1)),
                Item(NavId.SystemLogs, "系统日志", "📋", "/system/logs"),
                Item(NavId.Settings, "安全管理", "⚙", "/system/settings"),
                Item(NavId.ProxyConfig, "代理配置", "↔", "/vpnProxy/page")
            }),
            (NavSection.Tools, new[]
            {
                Item(NavId.AiChat, "AI 对话", "💬", "/ai/chat"),
                Item(NavId.Notify, "通知管理", "🔔", "/system/notifySettings"),
                Item(NavId.Memo, "备忘管理", "📖", "/system/memPage"),
                Item(NavId.Migration, "数据迁移", "⇄", "/migration/migPage"),
                Item(NavId.Mfa, "MFA 备份", "🔒", "/mfa/page")
            }),
            (NavSection.Dev, new[]
            {
                Item(NavId.ApiTokens, "Token 配置", "🔑", "/system/apiTokens")
            })
        };

    public static NavigationItem? ItemFor(NavId nav)
    {
        foreach (var (_, items) in Sections)
        {
            foreach (var item in items)
            {
                if (item.Nav == nav)
                    return item;
            }
        }

        return null;
    }

    public static IReadOnlyList<(NavSection Section, IReadOnlyList<NavigationItem> Items)> Filtered(
        string search,
        int? cloudType = null)
    {
        var q = (search ?? "").Trim();
        var result = new List<(NavSection, IReadOnlyList<NavigationItem>)>();

        foreach (var (section, items) in Sections)
        {
            IEnumerable<NavigationItem> list = items;
            if (cloudType is int ct)
            {
                list = list.Where(i =>
                    i.CloudTypes == null || i.CloudTypes.Contains(ct));
            }

            if (q.Length > 0)
            {
                list = list.Where(i =>
                    i.Title.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                    i.Nav.ToString().Contains(q, StringComparison.OrdinalIgnoreCase));
            }

            var arr = list.ToList();
            if (arr.Count > 0)
                result.Add((section, arr));
        }

        return result;
    }

    private static NavigationItem Item(
        NavId nav,
        string title,
        string glyph,
        string path,
        IReadOnlySet<int>? clouds = null) =>
        new(nav, title, glyph, path, clouds);

    private static IReadOnlySet<int> Cloud(params int[] types) => new HashSet<int>(types);
}
