import Foundation

/// Menu identifiers. Order of cases is not the sidebar order — see NavigationCatalog.
/// Source of truth for labels/paths: sidebar.ftl
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
    case settings
    case proxyConfig
    // tools
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
        case .service: return "服务管理"
        case .proxy: return "代理管理"
        case .vps: return "VPS 管理"
        case .system: return "系统管理"
        case .tools: return "我的工具"
        case .dev: return "开发者"
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
