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
