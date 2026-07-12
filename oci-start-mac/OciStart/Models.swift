import Foundation

// MARK: - Generic API Response

struct GenericResponse<T: Decodable>: Decodable {
    let success: Bool?
    let message: String?
    let data: T?
    let code: Int?
}

// MARK: - Login

struct LoginSuccessResponse: Codable {
    let success: Bool?
    let redirectUrl: String?
    let message: String?
}

// MARK: - OCI Instance

struct OciInstance: Identifiable, Codable, Equatable {
    let id: String
    let instanceId: String?
    let displayName: String?
    let state: String?
    let shape: String?
    let ocpus: Int?
    let memoryInGBs: Int?
    let bootVolumeSizeInGBs: Int64?
    let publicIps: String?
    let privateIps: String?
    let availabilityDomain: String?
    let regionName: String?
    let tenantId: Int64?
    let tenantIdStr: String?
    let tenancyName: String?
    let userName: String?
    let remark: String?
    let ipv6Addresses: String?
    let connTime: Int64?
    let enablePing: Int?
    let onLineEnable: Int?
    let cpuAndMem: String?
    let architecture: String?
    let timeCreated: String?
    let cloudType: Int?

    var isRunning: Bool { state?.uppercased() == "RUNNING" }
    var isStopped: Bool { state?.uppercased() == "STOPPED" }
    var isTransitioning: Bool {
        let s = state?.uppercased() ?? ""
        return ["PROVISIONING","STARTING","STOPPING","TERMINATING"].contains(s)
    }
    var displayPublicIP: String { (publicIps?.isEmpty == false) ? publicIps! : "—" }
    var displayShape: String {
        if let c = cpuAndMem, !c.isEmpty, c != "/" { return c }
        return shape ?? "—"
    }
    var displayTenant: String { tenancyName ?? userName ?? "—" }

    static func == (lhs: OciInstance, rhs: OciInstance) -> Bool { lhs.id == rhs.id }
}

struct InstanceListResponse: Codable {
    let content: [OciInstance]?
    let currentPage: Int?
    let totalPages: Int?
    let totalElements: Int64?
    let size: Int?
}

struct ActionResponse: Codable {
    let success: Bool?
    let message: String?
}

// MARK: - Dashboard

struct DashboardStats: Codable {
    let totalApiCalls: Int64?
    let totalBootInstances: Int64?
    let totalAttempts: Int64?
    let successfulAttempts: Int64?
    let successRate: Int64?
    let failCounts: Int64?
}

// MARK: - Tenant

struct Tenant: Identifiable, Codable, Equatable, Hashable {
    let id: Int64
    let tenantId: String?
    let userName: String?
    let tenancyName: String?
    let region: String?
    let enabled: Bool?
    let cloudType: Int?
    let createTime: String?

    var displayName: String { tenancyName ?? userName ?? "Tenant \(id)" }
    var displayRegion: String { region ?? "—" }
    var cloudLabel: String {
        switch cloudType {
        case 1: return "OCI"
        case 2: return "GCP"
        case 3: return "Azure"
        case 4: return "AWS"
        default: return "OCI"
        }
    }
    static func == (lhs: Tenant, rhs: Tenant) -> Bool { lhs.id == rhs.id }
}

struct TenantListResponse: Codable {
    let content: [Tenant]?
    let currentPage: Int?
    let totalPages: Int?
    let totalElements: Int64?
    let size: Int?
}

// MARK: - Object Storage

struct StorageBucket: Identifiable, Codable, Equatable, Hashable {
    let name: String
    var id: String { name }
    let namespace: String?
    let timeCreated: String?
    let publicAccessType: String?
}

struct StorageObject: Identifiable, Codable {
    let name: String
    var id: String { name }
    let size: Int64?
    let timeModified: String?

    var sizeDisplay: String {
        guard let s = size else { return "—" }
        if s < 1024 { return "\(s) B" }
        if s < 1024 * 1024 { return String(format: "%.1f KB", Double(s) / 1024) }
        if s < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(s) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(s) / (1024 * 1024 * 1024))
    }
}

struct StorageBucketsResponse: Codable {
    let items: [StorageBucket]?
    let nextPage: String?
}

struct StorageObjectsResponse: Codable {
    let items: [StorageObject]?
    let nextStartWith: String?
}

// MARK: - Memo

struct Memo: Identifiable, Codable, Hashable, Equatable {
    let id: Int64?
    var title: String?
    var content: String?
    let createTime: String?
    let updateTime: String?

    var displayTitle: String { (title?.isEmpty == false) ? title! : "无标题" }
}

// MARK: - API Token

struct ApiTokenStatus: Codable {
    let token: String?
    let enabled: Bool?
    let createdAt: String?
    let description: String?
    let tokenName: String?
}

// MARK: - VPS Instance (monitoring view)

struct VpsInstance: Identifiable, Codable {
    // reuses InstanceDetailsRes fields; aliased for clarity
    let id: String
    let displayName: String?
    let publicIps: String?
    let privateIps: String?
    let onLineEnable: Int?
    let enablePing: Int?
    let connTime: Int64?
    let tenancyName: String?
    let regionName: String?
    let state: String?

    var isOnline: Bool { onLineEnable == 1 }
    var pingEnabled: Bool { enablePing == 1 }
    var latencyDisplay: String {
        guard let t = connTime, t > 0 else { return "—" }
        return "\(t) ms"
    }
}

struct VpsListResponse: Codable {
    let content: [VpsInstance]?
    let totalElements: Int64?
}

// MARK: - ARM Records

struct ArmRegionRecord: Identifiable, Codable {
    let id: Int64?
    let region: String?
    let regionName: String?
    let status: String?
    let createTime: String?

    var displayId: Int64 { id ?? 0 }
}

// MARK: - Boot

struct RegionItem: Codable, Identifiable {
    let id: Int64
    let region: String?
    let isHomeRegion: Bool?
    var displayName: String { region ?? "Region \(id)" }
}

struct SystemImage: Codable {
    let operatingSystem: String?
    let operatingSystemVersion: String?
    let imageId: String?
}

// MARK: - Notification config models (read-only for display)

struct NotifyConfig: Codable {
    struct TelegramConfig: Codable {
        var enabled: Bool?
        var botToken: String?
        var chatId: String?
    }
    struct DingTalkConfig: Codable {
        var enabled: Bool?
        var accessToken: String?
        var secret: String?
    }
    struct BarkConfig: Codable {
        var enabled: Bool?
        var barkKey: String?
        var sound: String?
    }
    var telegram: TelegramConfig?
    var dingTalk: DingTalkConfig?
    var bark: BarkConfig?
}

// MARK: - Boot tasks (one-click boot)

struct BootTask: Identifiable, Codable, Equatable {
    let id: Int64?
    let bootId: String?
    let tenantId: Int64?
    let ocpu: Int?
    let memory: Int?
    let disk: Int?
    let status: Int?
    let architecture: String?
    let publicIp: String?
    let successCount: Int?
    let addCount: Int64?
    let remark: String?
    let userName: String?
    let tenancyName: String?
    let regionName: String?
    let createAtStr: String?
    let currentAttemptCount: Int?

    var displayId: Int64 { id ?? 0 }
    var statusLabel: String {
        switch status ?? -1 {
        case 0: return "未启动"
        case 1: return "抢机中"
        case 2: return "已成功"
        default: return "未知"
        }
    }
    var displayTenant: String { tenancyName ?? userName ?? "—" }
    var displayShape: String {
        let o = ocpu.map { "\($0)" } ?? "?"
        let m = memory.map { "\($0)" } ?? "?"
        let d = disk.map { "\($0)" } ?? "?"
        return "\(o)C/\(m)G/\(d)G"
    }
}

struct BootTaskListData: Codable {
    let list: [BootTask]?
    let total: Int64?
    let runningCount: Int64?
}

// MARK: - Notify configs (load)

struct NotifyConfigsBundle: Codable {
    var telegram: TelegramNotifyConfig?
    var dingTalk: DingTalkNotifyConfig?
    var bark: BarkNotifyConfig?
    var feishu: FeishuNotifyConfig?
}

struct TelegramNotifyConfig: Codable {
    var enabled: Bool?
    var botToken: String?
    var chatId: String?
    var chatName: String?
}

struct DingTalkNotifyConfig: Codable {
    var enabled: Bool?
    var webhook: String?
    var secret: String?
}

struct BarkNotifyConfig: Codable {
    var enabled: Bool?
    var url: String?
    var deviceKey: String?
}

struct FeishuNotifyConfig: Codable {
    var enabled: Bool?
    var webhook: String?
    var secret: String?
}

// MARK: - Tenant account check

struct AccountCheckResult: Codable {
    let totalAccounts: Int?
    let activeAccounts: Int?
    let inactiveAccounts: Int?
    let inactiveAccountNames: [String]?

    var summary: String {
        let total = totalAccounts ?? 0
        let active = activeAccounts ?? 0
        let inactive = inactiveAccounts ?? 0
        var s = "共 \(total) 个账号，正常 \(active)，异常 \(inactive)"
        if let names = inactiveAccountNames, !names.isEmpty {
            s += "：\(names.prefix(5).joined(separator: ", "))"
            if names.count > 5 { s += "…" }
        }
        return s
    }
}

// MARK: - AI Chat

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var content: String
    var isStreaming: Bool
    let time: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, isStreaming: Bool = false, time: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.time = time
    }
}

struct AiTenant: Identifiable, Codable, Hashable {
    let id: String
    let name: String?

    var displayName: String { (name?.isEmpty == false) ? name! : "Tenant \(id)" }
}

struct AiChatModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String?
    let description: String?
    let provider: String?
    let modelName: String?
    let enabled: Bool?
    let tenantId: String?

    var label: String {
        if let n = name, !n.isEmpty { return n }
        if let m = modelName, !m.isEmpty { return m }
        return id
    }
}

// MARK: - Domain provider keys

struct DomainProviderBundle: Codable {
    var cloudflare: CloudflareProviderConfig?
    var edgeOne: EdgeOneProviderConfig?
}

struct CloudflareProviderConfig: Codable {
    var enabled: Bool?
    var apiToken: String?
    var email: String?
    var zoneId: String?
}

struct EdgeOneProviderConfig: Codable {
    var enabled: Bool?
    var secretId: String?
    var secretKey: String?
    var region: String?
}

// MARK: - IP quality check

struct IpCheckConfigModel: Codable {
    var enabled: Bool?
    var checkInterval: Int?
}

struct OperatorVpsConfig: Codable {
    var enabled: Bool?
    var serverIp: String?
    var username: String?
    var password: String?
    var sshPort: Int?
    var type: String?
}

struct IpSettingsBundle: Codable {
    var ipCheck: IpCheckConfigModel?
    var telecom: OperatorVpsConfig?
    var unicom: OperatorVpsConfig?
    var mobile: OperatorVpsConfig?
}

// MARK: - VPN proxy

struct VpnProxyRecord: Identifiable, Equatable {
    let id: Int64
    var proxyType: String
    var proxyHost: String
    var proxyPort: Int
    var proxyUsername: String
    var proxyPassword: String
    var availableStatus: Int

    var isEnabled: Bool { availableStatus == 1 }

    init?(dict: [String: Any]) {
        let idNum: Int64?
        if let i = dict["id"] as? Int64 { idNum = i }
        else if let i = dict["id"] as? Int { idNum = Int64(i) }
        else if let i = dict["id"] as? String { idNum = Int64(i) }
        else { idNum = nil }
        guard let id = idNum else { return nil }
        self.id = id
        self.proxyType = (dict["proxyType"] as? String) ?? "HTTP"
        self.proxyHost = (dict["proxyHost"] as? String) ?? ""
        if let p = dict["proxyPort"] as? Int { self.proxyPort = p }
        else if let p = dict["proxyPort"] as? String { self.proxyPort = Int(p) ?? 0 }
        else { self.proxyPort = 0 }
        self.proxyUsername = (dict["proxyUsername"] as? String) ?? ""
        self.proxyPassword = (dict["proxyPassword"] as? String) ?? ""
        if let s = dict["availableStatus"] as? Int { self.availableStatus = s }
        else if let s = dict["availableStatus"] as? String { self.availableStatus = Int(s) ?? 0 }
        else { self.availableStatus = 0 }
    }
}
