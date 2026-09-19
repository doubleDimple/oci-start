import Foundation

/// Menu identifiers. Order of cases is not the sidebar order — see NavigationCatalog.
/// Source of truth for labels/paths: oci-start-web/src/nav/menu.ts
enum NavID: String, CaseIterable, Hashable {
    // service
    case dashboard
    case regions
    case tenants
    case instances
    case email
    case storage
    case boot
    case ai
    case speedTest
    case openLogs
    case gcpAccounts
    case gcpInstances
    case azureVms
    case azureResources
    case azureStorage
    case azureNetworks
    case awsEc2
    case awsS3
    case awsLambda
    case awsRds
    // proxy
    case keyConfig
    case cloudflare
    case edgeOne
    // vps
    case vpsList
    // system
    case ipQuality
    case systemLogs
    case auditLogs
    case settings
    case proxyConfig
    // tools
    case aiChat
    case notify
    case memo
    case migration
    case mfa
    // dev
    case apiTokens
}

enum NavSection: String, CaseIterable {
    case service
    case proxy
    case vps
    case system
    case tools
    case dev

    var title: String {
        switch self {
        case .service: return LanguageManager.shared.text("服务管理", "Service")
        case .proxy: return LanguageManager.shared.text("代理管理", "Proxy")
        case .vps: return LanguageManager.shared.text("资源管理", "VPS")
        case .system: return LanguageManager.shared.text("系统管理", "System")
        case .tools: return LanguageManager.shared.text("我的工具", "Tools")
        case .dev: return LanguageManager.shared.text("开发配置", "Developer")
        }
    }

    var systemImage: String {
        switch self {
        case .service: return "server.rack"
        case .proxy: return "arrow.left.arrow.right"
        case .vps: return "desktopcomputer"
        case .system: return "gearshape"
        case .tools: return "wrench.and.screwdriver"
        // SF Symbols 2 (macOS 11) — avoid iOS15+ only names like chevron.left.forwardslash.chevron.right
        case .dev: return "chevron.left.slash.chevron.right"
        }
    }
}
