import Foundation

/// Single source of menu metadata. Keep aligned with
/// `oci-start-web/src/nav/menu.ts`.
struct NavigationItem: Identifiable, Hashable {
    var id: NavID { nav }
    let nav: NavID
    let chineseTitle: String
    var title: String { LanguageManager.shared.text(chineseTitle, Self.englishTitles[nav] ?? chineseTitle) }
    private static let englishTitles: [NavID: String] = [
        .dashboard: "System monitor", .regions: "OCI Regions", .tenants: "OCI Tenants",
        .instances: "OCI Instances", .email: "OCI Email", .storage: "OCI Object Storage",
        .boot: "OCI Boot", .ai: "OCI AI", .speedTest: "OCI Latency Test",
        .openLogs: "OCI boot logs", .keyConfig: "Key config", .cloudflare: "Cloudflare",
        .edgeOne: "EdgeOne", .vpsList: "Instances", .systemLogs: "System logs",
        .settings: "Security", .proxyConfig: "Proxy config", .notify: "Notifications",
        .memo: "Memos", .migration: "Migration", .mfa: "MFA backup", .apiTokens: "API tokens",
        .aiChat: "AI chat", .auditLogs: "Audit logs"
    ]
    let systemImage: String
    let webPath: String
    /// nil = always visible; else cloud types 1=OCI 2=GCP 3=Azure 4=AWS
    let cloudTypes: Set<Int>?
}

enum NavigationCatalog {

    static let sections: [(NavSection, [NavigationItem])] = [
        (.service, [
            item(.dashboard, "系统资源监控", "chart.pie", "/boot/dashboard"),
            item(.regions, "OCI 区域管理", "globe", "/resource/list", [1]),
            item(.tenants, "OCI 租户管理", "person.2", "/tenants/list", [1]),
            item(.instances, "OCI 实例列表", "server.rack", "/oci/list", [1]),
            item(.email, "OCI 邮箱服务", "envelope", "/email/management", [1]),
            item(.storage, "OCI 对象存储", "externaldrive", "/oci/storage/page", [1]),
            item(.boot, "OCI 开机管理", "play.circle", "/boot/fullBootList", [1]),
            item(.ai, "OCI AI 管理", "sparkles", "/system/ai/models", [1]),
            item(.speedTest, "OCI延迟测试", "speedometer", "/delayTest", [1]),
            item(.openLogs, "OCI 开机日志", "doc.text", "/system/openLogs", [1]),
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
            item(.cloudflare, "CF 管理", "globe", "/dns/cloudflare"),
            item(.edgeOne, "EO 管理", "globe", "/dns/edgeone")
        ]),
        (.vps, [
            item(.vpsList, "资源列表", "desktopcomputer", "/vps/instances/list")
        ]),
        (.system, [
            item(.systemLogs, "系统日志", "doc.plaintext", "/system/logs"),
            item(.settings, "安全管理", "slider.horizontal.3", "/system/settings"),
            item(.proxyConfig, "代理配置", "arrow.left.arrow.right", "/vpnProxy/page")
        ]),
        (.tools, [
            item(.notify, "通知管理", "bell", "/system/notifySettings"),
            item(.memo, "笔记管理", "book", "/system/memPage"),
            item(.migration, "数据迁移", "arrow.left.and.right", "/migration/migPage"),
            item(.mfa, "MFA 备份", "lock.shield", "/mfa/page")
        ]),
        (.dev, [
            item(.apiTokens, "Token 配置", "key.fill", "/system/apiTokens")
        ])
    ]

    /// Web secondary destinations stay reachable without adding sidebar entries.
    private static let secondaryItems = [
        item(.aiChat, "AI 对话", "bubble.left.and.bubble.right", "/ai/chat"),
        item(.auditLogs, "审计日志", "checkmark.shield", "/system/auditLogs")
    ]

    static func item(for nav: NavID) -> NavigationItem? {
        if let secondary = secondaryItems.first(where: { $0.nav == nav }) { return secondary }
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
                        || $0.webPath.localizedCaseInsensitiveContains(q)
                        || section.title.localizedCaseInsensitiveContains(q)
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
        NavigationItem(nav: nav, chineseTitle: title, systemImage: image, webPath: path, cloudTypes: clouds)
    }
}
