namespace OciStart.Navigation;

/// <summary>
/// Menu identifiers. Sidebar order lives in <see cref="NavigationCatalog"/>.
/// Source of truth for labels/paths: sidebar.ftl
/// </summary>
public enum NavId
{
    // service
    Dashboard,
    Regions,
    Tenants,
    Instances,
    Email,
    Storage,
    Boot,
    Ai,
    SpeedTest,
    OpenLogs,
    GcpAccounts,
    GcpInstances,
    AzureVms,
    AzureResources,
    AzureStorage,
    AzureNetworks,
    AwsEc2,
    AwsS3,
    AwsLambda,
    AwsRds,
    // proxy
    KeyConfig,
    Cloudflare,
    EdgeOne,
    // vps
    VpsList,
    // system
    IpQuality,
    SystemLogs,
    Settings,
    ProxyConfig,
    // tools
    AiChat,
    Notify,
    Memo,
    Migration,
    Mfa,
    // dev
    ApiTokens
}
