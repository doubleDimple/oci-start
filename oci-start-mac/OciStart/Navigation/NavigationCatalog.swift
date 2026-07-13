import Foundation

/// Single source of menu metadata. Keep aligned with
/// `oci-server/src/main/resources/templates/common/sidebar.ftl`.
struct NavigationItem: Identifiable, Hashable {
    var id: NavID { nav }
    let nav: NavID
    let title: String
    let systemImage: String
    let webPath: String
    /// nil = always visible; else cloud types 1=OCI 2=GCP 3=Azure 4=AWS
    let cloudTypes: Set<Int>?
}

enum NavigationCatalog {

    static let sections: [(NavSection, [NavigationItem])] = [
        (.service, [
            item(.dashboard, "系统监控", "chart.pie", "/boot/dashboard"),
            item(.regions, "区域订阅", "globe", "/resource/list", [1]),
            item(.tenants, "租户管理", "person.2", "/tenants/list", [1]),
            item(.instances, "实例列表", "server.rack", "/oci/list", [1]),
            item(.email, "邮件管理", "envelope", "/email/management", [1]),
            item(.storage, "对象存储", "externaldrive", "/oci/storage/page", [1]),
            item(.boot, "开机管理", "play.circle", "/boot/fullBootList", [1]),
            item(.ai, "OCI AI 管理", "sparkles", "/system/ai/models", [1]),
            item(.speedTest, "延迟测试", "speedometer", "/delayTest", [1]),
            item(.openLogs, "开机日志", "doc.text", "/system/openLogs", [1]),
            item(.gcpAccounts, "GCP 账户", "g.circle", "/tenants/list", [2]),
            item(.gcpInstances, "GCP 实例", "server.rack", "/other/instances/list", [2]),
            item(.azureVms, "Azure 虚拟机", "square.stack.3d.up", "/azure/vms", [3]),
            item(.azureResources, "Azure 资源", "square.grid.2x2", "/azure/resources", [3]),
            item(.azureStorage, "Azure 存储", "externaldrive", "/azure/storage", [3]),
            item(.azureNetworks, "Azure 网络", "network", "/azure/networks", [3]),
            item(.awsEc2, "AWS EC2", "server.rack", "/aws/ec2", [4]),
            item(.awsS3, "AWS S3", "cloud", "/aws/s3", [4]),
            item(.awsLambda, "AWS Lambda", "f.circle", "/aws/lambda", [4]),
            item(.awsRds, "AWS RDS", "cylinder", "/aws/rds", [4])
        ]),
        (.proxy, [
            item(.keyConfig, "密钥配置", "key", "/system/domainSettings"),
            item(.cloudflare, "Cloudflare", "globe", "/dns/cloudflare"),
            item(.edgeOne, "EdgeOne", "globe", "/dns/edgeone")
        ]),
        (.vps, [
            item(.vpsList, "实例列表", "list.bullet", "/vps/instances/list")
        ]),
        (.system, [
            item(.ipQuality, "质量管理", "shield", "/system/ipSettings", [1]),
            item(.systemLogs, "系统日志", "doc.plaintext", "/system/logs"),
            item(.settings, "安全管理", "slider.horizontal.3", "/system/settings"),
            item(.proxyConfig, "代理配置", "arrow.left.arrow.right", "/vpnProxy/page")
        ]),
        (.tools, [
            item(.notify, "通知管理", "bell", "/system/notifySettings"),
            item(.memo, "备忘管理", "book", "/system/memPage"),
            item(.migration, "数据迁移", "arrow.left.and.right", "/migration/migPage"),
            item(.mfa, "MFA 备份", "lock.shield", "/mfa/page")
        ]),
        (.dev, [
            item(.apiTokens, "Token 配置", "key.fill", "/system/apiTokens")
        ])
    ]

    static func item(for nav: NavID) -> NavigationItem? {
        for (_, items) in sections {
            if let found = items.first(where: { $0.nav == nav }) {
                return found
            }
        }
        return nil
    }

    static func section(for nav: NavID) -> NavSection? {
        for (section, items) in sections {
            if items.contains(where: { $0.nav == nav }) {
                return section
            }
        }
        return nil
    }

    static func filtered(search: String, cloudType: Int? = nil) -> [(NavSection, [NavigationItem])] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return sections.compactMap { section, items in
            var list = items
            if let cloudType = cloudType {
                list = list.filter { item in
                    guard let allowed = item.cloudTypes else { return true }
                    return allowed.contains(cloudType)
                }
            }
            if !q.isEmpty {
                list = list.filter {
                    $0.title.localizedCaseInsensitiveContains(q)
                        || $0.nav.rawValue.localizedCaseInsensitiveContains(q)
                }
            }
            return list.isEmpty ? nil : (section, list)
        }
    }

    private static func item(
        _ nav: NavID,
        _ title: String,
        _ image: String,
        _ path: String,
        _ clouds: Set<Int>? = nil
    ) -> NavigationItem {
        NavigationItem(nav: nav, title: title, systemImage: image, webPath: path, cloudTypes: clouds)
    }
}
