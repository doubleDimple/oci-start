using System.Windows.Controls;
using OciStart.Features.AiChat;
using OciStart.Features.AiModels;
using OciStart.Features.ApiTokens;
using OciStart.Features.Boot;
using OciStart.Features.Cloudflare;
using OciStart.Features.Dashboard;
using OciStart.Features.EdgeOne;
using OciStart.Features.Email;
using OciStart.Features.Instances;
using OciStart.Features.IpQuality;
using OciStart.Features.KeyConfig;
using OciStart.Features.Memo;
using OciStart.Features.MfaBackup;
using OciStart.Features.Migration;
using OciStart.Features.MultiCloud;
using OciStart.Features.Notify;
using OciStart.Features.OpenLogs;
using OciStart.Features.Placeholder;
using OciStart.Features.ProxyConfig;
using OciStart.Features.Regions;
using OciStart.Features.SecuritySettings;
using OciStart.Features.SpeedTest;
using OciStart.Features.Storage;
using OciStart.Features.SystemLogs;
using OciStart.Features.Tenants;
using OciStart.Features.Vps;

namespace OciStart.Navigation;

/// <summary>NavId → page factory. Align Mac FeatureRouter (native first, no full-page WebView).</summary>
public static class FeatureRouter
{
    public static UserControl CreateView(NavId nav)
    {
        var item = NavigationCatalog.ItemFor(nav);
        var title = item?.Title ?? nav.ToString();
        var path = item?.WebPath ?? "";

        return nav switch
        {
            // service
            NavId.Dashboard => new DashboardView(),
            NavId.Regions => new RegionsView(),
            NavId.Tenants => new TenantsView(),
            NavId.Instances => new InstancesView(),
            NavId.Email => new EmailView(),
            NavId.Storage => new StorageView(),
            NavId.Boot => new BootView(),
            NavId.Ai => new AiModelsView(),
            NavId.SpeedTest => new SpeedTestView(),
            NavId.OpenLogs => new OpenLogsView(),
            // multi-cloud: GCP real; Azure/AWS native shell until server SPI
            NavId.GcpAccounts => new TenantsView(2, "GCP 账户", "Service Account · cloudType=2"),
            NavId.GcpInstances => new GcpInstancesView(),
            NavId.AzureVms => new MultiCloudComingSoonView(title, "Azure", path,
                "虚拟机列表 / 启停", "资源组", "订阅切换"),
            NavId.AzureResources => new MultiCloudComingSoonView(title, "Azure", path,
                "资源清单", "标签筛选"),
            NavId.AzureStorage => new MultiCloudComingSoonView(title, "Azure", path,
                "存储账户", "Blob 容器"),
            NavId.AzureNetworks => new MultiCloudComingSoonView(title, "Azure", path,
                "VNet / NSG", "公网 IP"),
            NavId.AwsEc2 => new MultiCloudComingSoonView(title, "AWS", path,
                "EC2 实例", "启停 / 换 IP"),
            NavId.AwsS3 => new MultiCloudComingSoonView(title, "AWS", path,
                "Bucket / 对象", "预签名"),
            NavId.AwsLambda => new MultiCloudComingSoonView(title, "AWS", path,
                "函数列表", "调用日志"),
            NavId.AwsRds => new MultiCloudComingSoonView(title, "AWS", path,
                "数据库实例", "连接信息"),
            // proxy
            NavId.KeyConfig => new KeyConfigView(),
            NavId.Cloudflare => new CloudflareView(),
            NavId.EdgeOne => new EdgeOneView(),
            // vps
            NavId.VpsList => new VpsListView(),
            // system
            NavId.IpQuality => new IpQualityView(),
            NavId.SystemLogs => new SystemLogsView(),
            NavId.Settings => new SecuritySettingsView(),
            NavId.ProxyConfig => new ProxyConfigView(),
            // tools
            NavId.AiChat => new AiChatView(),
            NavId.Notify => new NotifyView(),
            NavId.Memo => new MemoView(),
            NavId.Migration => new MigrationView(),
            NavId.Mfa => new MfaBackupView(),
            // dev
            NavId.ApiTokens => new ApiTokensView(),
            _ => new PlaceholderView(title, path, nav)
        };
    }
}
