import Foundation

// MARK: - List

struct TenantsListResponse: Decodable {
    var content: [TenantItem] = []
    var currentPage: Int = 0
    var totalPages: Int = 0
    var totalElements: Int64 = 0
    var size: Int = 10

    enum CodingKeys: String, CodingKey {
        case content, currentPage, totalPages, totalElements, size
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? c.decode([TenantItem].self, forKey: .content)) ?? []
        currentPage = Self.int(c, .currentPage) ?? 0
        totalPages = Self.int(c, .totalPages) ?? 0
        totalElements = Self.int64(c, .totalElements) ?? 0
        size = Self.int(c, .size) ?? 10
    }

    private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int? {
        if let v = try? c.decode(Int.self, forKey: k) { return v }
        if let v = try? c.decode(Int64.self, forKey: k) { return Int(v) }
        return nil
    }
    private static func int64(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int64? {
        if let v = try? c.decode(Int64.self, forKey: k) { return v }
        if let v = try? c.decode(Int.self, forKey: k) { return Int64(v) }
        return nil
    }
}

struct TenantItem: Decodable, Identifiable, Equatable {
    var id: Int64 = 0
    var tenantId: String = ""
    var userName: String = ""
    var fingerprint: String = ""
    var tenancy: String = ""
    var region: String = ""
    var regionEn: String = ""
    var tenancyName: String = ""
    var tenancyDes: String = ""
    var defName: String = ""
    var accountType: String = ""
    var accountTypeName: String = ""
    var accountCost: String = ""
    var activeDays: String = ""
    var emailAddress: String = ""
    var emailEnable: Int = 0
    var cloudType: Int = 1
    var transferStatus: Int = 0
    var transferAmount: String = ""
    var isHomeRegion: Bool = true
    var hasChildren: Bool = false
    var openBootFlag: Bool = false
    var isActive: Bool = true
    var supportAI: Int = 0
    var createdAt: String = ""
    var children: [TenantItem] = []
    var registerDetail: TenantRegisterDetail?

    enum CodingKeys: String, CodingKey {
        case id, tenantId, userName, fingerprint, tenancy, region, regionEn
        case tenancyName, tenancyDes, defName
        case accountType, accountTypeName, accountCost, activeDays
        case emailAddress, emailEnable, cloudType
        case transferStatus, transferAmount
        case isHomeRegion, homeRegion
        case hasChildren, openBootFlag
        case isActive, active
        case supportAI, createdAt, createdAtStr
        case children, registerDetail
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.int64(c, .id) ?? 0
        tenantId = Self.str(c, .tenantId)
        userName = Self.str(c, .userName)
        fingerprint = Self.str(c, .fingerprint)
        tenancy = Self.str(c, .tenancy)
        region = Self.str(c, .region)
        regionEn = Self.str(c, .regionEn)
        tenancyName = Self.str(c, .tenancyName)
        tenancyDes = Self.str(c, .tenancyDes)
        defName = Self.str(c, .defName)
        accountType = Self.str(c, .accountType)
        accountTypeName = Self.str(c, .accountTypeName)
        accountCost = Self.str(c, .accountCost)
        activeDays = Self.str(c, .activeDays)
        emailAddress = Self.str(c, .emailAddress)
        emailEnable = Self.int(c, .emailEnable) ?? 0
        cloudType = Self.int(c, .cloudType) ?? 1
        transferStatus = Self.int(c, .transferStatus) ?? 0
        transferAmount = Self.str(c, .transferAmount)
        isHomeRegion = Self.bool(c, .isHomeRegion) ?? Self.bool(c, .homeRegion) ?? true
        hasChildren = Self.bool(c, .hasChildren) ?? false
        openBootFlag = Self.bool(c, .openBootFlag) ?? false
        isActive = Self.bool(c, .isActive) ?? Self.bool(c, .active) ?? true
        supportAI = Self.int(c, .supportAI) ?? 0
        createdAt = Self.str(c, .createdAtStr)
        if createdAt.isEmpty { createdAt = Self.time(c, .createdAt) ?? "" }
        children = (try? c.decode([TenantItem].self, forKey: .children)) ?? []
        registerDetail = try? c.decode(TenantRegisterDetail.self, forKey: .registerDetail)
    }

    var displayName: String {
        if !tenancyName.isEmpty { return tenancyName }
        if !userName.isEmpty { return userName }
        if !tenantId.isEmpty { return tenantId }
        return "#\(id)"
    }

    var maskedName: String {
        let tn = displayName
        guard tn.count > 2 else { return tn.isEmpty ? "" : "***" }
        return "\(tn.prefix(1))***\(tn.suffix(1))"
    }

    var isMultiRegion: Bool {
        guard !children.isEmpty else { return false }
        if children.count == 1, children[0].region == region { return false }
        return true
    }

    var isTransferred: Bool { transferStatus == 1 }
    var openTaskText: String { openBootFlag ? "有任务" : "无任务" }
    var multiRegionText: String { isMultiRegion ? "是" : "否" }
    var typeText: String {
        if !accountTypeName.isEmpty, accountTypeName != "未知" { return accountTypeName }
        return hasChildren ? "简易多区域" : "未知"
    }
    var statusText: String { isActive ? "有效" : "失效" }
    var activeDaysText: String { activeDays.isEmpty ? "0" : activeDays }
    var costText: String { accountCost.isEmpty ? "—" : accountCost }
    var defNameText: String { defName.isEmpty ? "—" : defName }

    private static func str(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> String {
        if let s = try? c.decode(String.self, forKey: k) { return s }
        if let n = try? c.decode(Int64.self, forKey: k) { return String(n) }
        if let n = try? c.decode(Int.self, forKey: k) { return String(n) }
        return ""
    }
    private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int? {
        if let v = try? c.decode(Int.self, forKey: k) { return v }
        if let v = try? c.decode(Int64.self, forKey: k) { return Int(v) }
        if let s = try? c.decode(String.self, forKey: k) { return Int(s) }
        return nil
    }
    private static func int64(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int64? {
        if let v = try? c.decode(Int64.self, forKey: k) { return v }
        if let v = try? c.decode(Int.self, forKey: k) { return Int64(v) }
        if let s = try? c.decode(String.self, forKey: k) { return Int64(s) }
        return nil
    }
    private static func bool(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Bool? {
        if let v = try? c.decode(Bool.self, forKey: k) { return v }
        if let n = try? c.decode(Int.self, forKey: k) { return n != 0 }
        if let s = try? c.decode(String.self, forKey: k) {
            let l = s.lowercased()
            if l == "true" || l == "1" { return true }
            if l == "false" || l == "0" { return false }
        }
        return nil
    }
    private static func time(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: k) { return s }
        if let arr = try? c.decode([Int].self, forKey: k), arr.count >= 5 {
            let sec = arr.count > 5 ? arr[5] : 0
            return String(format: "%04d-%02d-%02d %02d:%02d:%02d", arr[0], arr[1], arr[2], arr[3], arr[4], sec)
        }
        return nil
    }
}

struct TenantRegisterDetail: Decodable, Equatable {
    var accountType: String = ""
    var planType: String = ""
    var emailAddress: String = ""
    var firstName: String = ""
    var city: String = ""
    var country: String = ""
    var registerTime: String = ""

    enum CodingKeys: String, CodingKey {
        case accountType, planType, emailAddress, firstName, city, country, registerTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountType = (try? c.decode(String.self, forKey: .accountType)) ?? ""
        planType = (try? c.decode(String.self, forKey: .planType)) ?? ""
        emailAddress = (try? c.decode(String.self, forKey: .emailAddress)) ?? ""
        firstName = (try? c.decode(String.self, forKey: .firstName)) ?? ""
        city = (try? c.decode(String.self, forKey: .city)) ?? ""
        country = (try? c.decode(String.self, forKey: .country)) ?? ""
        if let s = try? c.decode(String.self, forKey: .registerTime) {
            registerTime = s
        } else if let n = try? c.decode(Double.self, forKey: .registerTime) {
            registerTime = String(Int(n))
        }
    }
}

// MARK: - Users

struct TenantOracleUser: Decodable, Identifiable, Equatable {
    var id: String = ""
    var username: String = ""
    var lifecycleState: String = ""
    var userId: String = ""
    var email: String = ""
    var domain: String = ""
    var lastSuccessfulLoginTime: String = ""
    var timeCreated: String = ""

    enum CodingKeys: String, CodingKey {
        case id, username, lifecycleState, userId, email, domain
        case lastSuccessfulLoginTime, timeCreated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        lifecycleState = (try? c.decode(String.self, forKey: .lifecycleState)) ?? ""
        userId = (try? c.decode(String.self, forKey: .userId)) ?? id
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        domain = (try? c.decode(String.self, forKey: .domain)) ?? ""
        lastSuccessfulLoginTime = Self.anyTime(c, .lastSuccessfulLoginTime)
        timeCreated = Self.anyTime(c, .timeCreated)
    }

    private static func anyTime(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> String {
        if let s = try? c.decode(String.self, forKey: k) { return s }
        if let n = try? c.decode(Double.self, forKey: k) {
            let d = Date(timeIntervalSince1970: n / (n > 1e12 ? 1000 : 1))
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: d)
        }
        return ""
    }
}

struct TenantOciGroup: Decodable, Identifiable, Equatable {
    var id: String = ""
    var name: String = ""
    var description: String = ""

    enum CodingKeys: String, CodingKey { case id, name, description, groupId, groupName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id))
            ?? (try? c.decode(String.self, forKey: .groupId))
            ?? ""
        name = (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .groupName))
            ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
    }
}

struct TenantPasswordPolicy: Decodable, Identifiable, Equatable {
    var id: String { name + "\(isEnabled)" }
    var name: String = ""
    var isEnabled: Bool = false
    var description: String = ""

    enum CodingKeys: String, CodingKey {
        case name, isEnabled, enabled, description, policyName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .policyName))
            ?? ""
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled))
            ?? (try? c.decode(Bool.self, forKey: .enabled))
            ?? false
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
    }
}

// MARK: - Traffic / Boot / Social / Quota / Check

struct TenantTrafficAlert: Decodable, Equatable {
    var tenantId: Int64?
    var threshold: Double?
    var autoShutdown: Bool?
    var enabled: Bool?
    var statisticsEnabled: Bool?
    var success: Bool?
    var message: String?

    var thresholdText: String {
        guard let t = threshold, t > 0 else { return "" }
        if t == Double(Int(t)) { return "\(Int(t))" }
        return String(format: "%.2f", t)
    }
}

struct TenantBootVolume: Decodable, Identifiable, Equatable {
    var id: String = ""
    var displayName: String = ""
    var sizeInGBs: Int64 = 0
    var vpusPerGB: Int64 = 0
    var status: String = ""
    var instanceName: String = ""
    var regionCode: String = ""

    enum CodingKeys: String, CodingKey {
        case id, displayName, sizeInGBs, vpusPerGB, status, instanceName, regionCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        sizeInGBs = (try? c.decode(Int64.self, forKey: .sizeInGBs))
            ?? Int64((try? c.decode(Int.self, forKey: .sizeInGBs)) ?? 0)
        vpusPerGB = (try? c.decode(Int64.self, forKey: .vpusPerGB))
            ?? Int64((try? c.decode(Int.self, forKey: .vpusPerGB)) ?? 0)
        status = (try? c.decode(String.self, forKey: .status)) ?? ""
        instanceName = (try? c.decode(String.self, forKey: .instanceName)) ?? ""
        regionCode = (try? c.decode(String.self, forKey: .regionCode)) ?? ""
    }
}

struct TenantSocialItem: Decodable, Identifiable, Equatable {
    var id: Int64 = 0
    var tenantId: Int64 = 0
    var clientId: String = ""
    var clientSecret: String = ""
    var socialTypeStr: String = ""
    var thirdLoginAddress: String = ""
    var redirectUrl: String = ""
    var socialStatus: String = "active"
    var cloudType: Int = 1

    enum CodingKeys: String, CodingKey {
        case id, tenantId, clientId, clientSecret, socialTypeStr
        case thirdLoginAddress, redirectUrl, socialStatus, cloudType
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        tenantId = (try? c.decode(Int64.self, forKey: .tenantId)) ?? 0
        clientId = (try? c.decode(String.self, forKey: .clientId)) ?? ""
        clientSecret = (try? c.decode(String.self, forKey: .clientSecret)) ?? ""
        socialTypeStr = (try? c.decode(String.self, forKey: .socialTypeStr)) ?? ""
        thirdLoginAddress = (try? c.decode(String.self, forKey: .thirdLoginAddress)) ?? ""
        redirectUrl = (try? c.decode(String.self, forKey: .redirectUrl)) ?? ""
        socialStatus = (try? c.decode(String.self, forKey: .socialStatus)) ?? "active"
        cloudType = (try? c.decode(Int.self, forKey: .cloudType)) ?? 1
    }
}

/// Web `TenantResp` from `GET /tenants/listRegions?parentId=`
struct TenantRegionOption: Decodable, Identifiable, Equatable {
    var id: String = ""
    var tenancyName: String = ""
    var userName: String = ""
    var region: String = ""
    var tenantId: String = ""
    var isHomeRegion: Bool = false
    var hasChildren: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, tenancyName, userName, region, tenantId, isHomeRegion, hasChildren
    }

    init(
        id: String = "",
        tenancyName: String = "",
        userName: String = "",
        region: String = "",
        tenantId: String = "",
        isHomeRegion: Bool = false,
        hasChildren: Bool = false
    ) {
        self.id = id
        self.tenancyName = tenancyName
        self.userName = userName
        self.region = region
        self.tenantId = tenantId
        self.isHomeRegion = isHomeRegion
        self.hasChildren = hasChildren
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decode(Int64.self, forKey: .id) {
            id = String(n)
        }
        tenancyName = (try? c.decode(String.self, forKey: .tenancyName)) ?? ""
        userName = (try? c.decode(String.self, forKey: .userName)) ?? ""
        region = (try? c.decode(String.self, forKey: .region)) ?? ""
        tenantId = (try? c.decode(String.self, forKey: .tenantId)) ?? ""
        isHomeRegion = (try? c.decode(Bool.self, forKey: .isHomeRegion)) ?? false
        hasChildren = (try? c.decode(Bool.self, forKey: .hasChildren)) ?? false
    }

    var label: String {
        var s = tenancyName.isEmpty ? (userName.isEmpty ? tenantId : userName) : tenancyName
        if s.isEmpty { s = id }
        if !region.isEmpty { s += " (\(region))" }
        return s
    }

    /// 转为列表行模型，不足字段从父租户继承（对齐 Web regionList 行数据）
    func toTenantItem(fallback parent: TenantItem) -> TenantItem {
        var t = TenantItem()
        t.id = Int64(id) ?? 0
        t.tenantId = tenantId.isEmpty ? parent.tenantId : tenantId
        t.tenancyName = tenancyName.isEmpty ? (userName.isEmpty ? parent.tenancyName : userName) : tenancyName
        t.userName = userName.isEmpty ? parent.userName : userName
        t.region = region
        t.isHomeRegion = isHomeRegion
        t.hasChildren = hasChildren
        t.defName = parent.defName
        t.cloudType = parent.cloudType
        t.supportAI = parent.supportAI
        t.openBootFlag = false
        t.createdAt = ""
        t.isActive = true
        return t
    }
}

// MARK: - Security rules / MySQL (租户详情页弹层)

struct TenantSecurityRule: Decodable, Identifiable, Equatable {
    var id: String { "\(type)-\(protocolValue)-\(source)-\(ports)" }
    var type: String = ""
    var protocolValue: String = ""
    var source: String = ""
    var ports: String = ""

    enum CodingKeys: String, CodingKey {
        case type, source, ports
        case protocolValue = "protocol"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        if let s = try? c.decode(String.self, forKey: .protocolValue) {
            protocolValue = s
        } else if let n = try? c.decode(Int.self, forKey: .protocolValue) {
            protocolValue = String(n)
        }
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        if let s = try? c.decode(String.self, forKey: .ports) {
            ports = s
        } else if let n = try? c.decode(Int.self, forKey: .ports) {
            ports = String(n)
        }
    }

    var protocolDisplay: String {
        switch protocolValue.lowercased() {
        case "all", "all protocols": return "全部"
        case "6", "tcp": return "TCP"
        case "17", "udp": return "UDP"
        case "1", "icmp": return "ICMP"
        default: return protocolValue.isEmpty ? "—" : protocolValue
        }
    }

    var portsDisplay: String {
        if ports.isEmpty || ports == "null" || ports == "N/A" || protocolValue == "1" { return "—" }
        return ports
    }
}

struct TenantMysqlInstance: Decodable, Identifiable, Equatable {
    var id: String = ""
    var dbId: String = ""
    var displayName: String = ""
    var dbVersion: String = ""
    var dbStatus: String = ""
    var dbPublicUrl: String = ""
    var dbPort: String = ""
    var dbUsername: String = ""
    var shape: String = ""
    var dataStorageSizeInGBs: String = ""

    enum CodingKeys: String, CodingKey {
        case id, dbId, displayName, dbVersion, dbStatus, dbPublicUrl, dbPort, dbUsername, shape
        case dataStorageSizeInGBs, storageSize, dataStorageSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let n = try? c.decode(Int64.self, forKey: .id) { id = String(n) }
        dbId = (try? c.decode(String.self, forKey: .dbId)) ?? id
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        dbVersion = (try? c.decode(String.self, forKey: .dbVersion)) ?? ""
        dbStatus = (try? c.decode(String.self, forKey: .dbStatus)) ?? ""
        dbPublicUrl = (try? c.decode(String.self, forKey: .dbPublicUrl)) ?? ""
        if let s = try? c.decode(String.self, forKey: .dbPort) { dbPort = s }
        else if let n = try? c.decode(Int.self, forKey: .dbPort) { dbPort = String(n) }
        dbUsername = (try? c.decode(String.self, forKey: .dbUsername)) ?? ""
        shape = (try? c.decode(String.self, forKey: .shape)) ?? ""
        if let s = try? c.decode(String.self, forKey: .dataStorageSizeInGBs) { dataStorageSizeInGBs = s }
        else if let n = try? c.decode(Int.self, forKey: .dataStorageSizeInGBs) { dataStorageSizeInGBs = String(n) }
        else if let s = try? c.decode(String.self, forKey: .storageSize) { dataStorageSizeInGBs = s }
        else if let n = try? c.decode(Int.self, forKey: .dataStorageSize) { dataStorageSizeInGBs = String(n) }
        if id.isEmpty { id = dbId.isEmpty ? displayName : dbId }
    }
}

struct TenantAccountCheckResult: Decodable, Equatable {
    var totalAccounts: Int = 0
    var activeAccounts: Int = 0
    var inactiveAccounts: Int = 0
    var inactiveAccountNames: [String] = []
    var message: String = ""

    enum CodingKeys: String, CodingKey {
        case totalAccounts, activeAccounts, inactiveAccounts, message
        case total, active, inactive
        case inactiveAccountNames, inactiveNames, inActiveAccountNames
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalAccounts = (try? c.decode(Int.self, forKey: .totalAccounts))
            ?? (try? c.decode(Int.self, forKey: .total))
            ?? 0
        activeAccounts = (try? c.decode(Int.self, forKey: .activeAccounts))
            ?? (try? c.decode(Int.self, forKey: .active))
            ?? 0
        inactiveAccounts = (try? c.decode(Int.self, forKey: .inactiveAccounts))
            ?? (try? c.decode(Int.self, forKey: .inactive))
            ?? 0
        inactiveAccountNames = (try? c.decode([String].self, forKey: .inactiveAccountNames))
            ?? (try? c.decode([String].self, forKey: .inactiveNames))
            ?? (try? c.decode([String].self, forKey: .inActiveAccountNames))
            ?? []
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
    }
}

/// One row from `/tenants/quota` items[].
struct TenantQuotaItem: Identifiable, Equatable {
    var id: String { "\(name)-\(scope)-\(available)-\(used)" }
    var name: String
    var scope: String
    var available: String
    var used: String
    var limit: String
    var instanceType: String

    static func parseList(from root: [String: Any]) -> (items: [TenantQuotaItem], page: Int, hasNext: Bool, region: String) {
        let page = (root["page"] as? Int) ?? 0
        let hasNext = (root["hasNextPage"] as? Bool) ?? false
        let region = (root["region"] as? String) ?? (root["regionEn"] as? String) ?? ""
        var items: [TenantQuotaItem] = []
        let rawItems = (root["items"] as? [[String: Any]]) ?? []
        for it in rawItems {
            let name = "\(it["name"] ?? it["limitName"] ?? it["resourceName"] ?? "—")"
            let scope = "\(it["scope"] ?? it["availabilityDomain"] ?? "")"
            let available = "\(it["available"] ?? it["availableQuota"] ?? it["remaining"] ?? "—")"
            let used = "\(it["used"] ?? it["usedQuota"] ?? "—")"
            let limit = "\(it["limit"] ?? it["value"] ?? it["total"] ?? "—")"
            items.append(TenantQuotaItem(
                name: name,
                scope: scope,
                available: available,
                used: used,
                limit: limit,
                instanceType: Self.inferType(name)
            ))
        }
        return (items, page, hasNext, region)
    }

    private static func inferType(_ limitName: String) -> String {
        let n = limitName.lowercased()
        let bm = n.hasPrefix("bm-") || n.contains("-bm-")
        var arch: String?
        if n.contains("-a1-") || n.contains("-a2-") { arch = "Ampere" }
        else if n.contains("-e5-") { arch = "AMD E5" }
        else if n.contains("-e4-") { arch = "AMD E4" }
        else if n.contains("-e3-") { arch = "AMD E3" }
        else if n.contains("-e2-") { arch = "AMD E2" }
        else if n.contains("gpu") { arch = "GPU" }
        else if n.contains("hpc") { arch = "HPC" }
        else if n.contains("x9") { arch = "Intel X9" }
        else if n.contains("standard3") { arch = "Intel" }
        else if n.contains("standard2") { arch = "Intel 旧款" }
        else if n.contains("mysql") { arch = "MySQL" }
        else if n.contains("nosql") { arch = "NoSQL" }
        else if n.contains("autonomous") || n.contains("adb") { arch = "ADB" }
        guard let arch = arch else { return bm ? "裸金属" : "—" }
        return bm ? "裸金属·\(arch)" : arch
    }
}

enum TenantUserTab: String, CaseIterable, Identifiable {
    case users, notifications, mfa
    var id: String { rawValue }
    var title: String {
        switch self {
        case .users: return "用户"
        case .notifications: return "通知邮箱"
        case .mfa: return "MFA"
        }
    }
}

struct TenantAuditLogEntry: Decodable, Identifiable, Equatable {
    var id: String { "\(eventName)-\(eventTime)-\(principalName)" }
    var eventName: String = ""
    var eventTime: String = ""
    var principalName: String = ""
    var sourceIP: String = ""
    var status: String = ""
    var message: String = ""

    enum CodingKeys: String, CodingKey {
        case eventName, eventTime, principalName, sourceIP, sourceIp, status, message
        case type, time, user, ip
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventName = (try? c.decode(String.self, forKey: .eventName))
            ?? (try? c.decode(String.self, forKey: .type))
            ?? ""
        eventTime = (try? c.decode(String.self, forKey: .eventTime))
            ?? (try? c.decode(String.self, forKey: .time))
            ?? ""
        principalName = (try? c.decode(String.self, forKey: .principalName))
            ?? (try? c.decode(String.self, forKey: .user))
            ?? ""
        sourceIP = (try? c.decode(String.self, forKey: .sourceIP))
            ?? (try? c.decode(String.self, forKey: .sourceIp))
            ?? (try? c.decode(String.self, forKey: .ip))
            ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? ""
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
    }
}

// MARK: - Generic API helpers

struct TenantBoolMessage: Decodable {
    var success: Bool = false
    var message: String = ""

    enum CodingKeys: String, CodingKey { case success, message, msg }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let b = try? c.decode(Bool.self, forKey: .success) {
            success = b
        } else if let n = try? c.decode(Int.self, forKey: .success) {
            success = n != 0
        }
        message = (try? c.decode(String.self, forKey: .message))
            ?? (try? c.decode(String.self, forKey: .msg))
            ?? ""
    }
}

struct TenantApiEnvelope: Decodable {
    var success: Bool?
    var message: String?
    var msg: String?
    var code: Int?
    var data: AnyCodableJSON?

    var ok: Bool {
        if let success = success { return success }
        if let code = code { return code == 200 || code == 0 }
        return false
    }
    var text: String { message ?? msg ?? (ok ? "成功" : "失败") }
}

/// Lightweight JSON tree for flexible envelope data.
enum AnyCodableJSON: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyCodableJSON])
    case object([String: AnyCodableJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyCodableJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyCodableJSON].self) { self = .object(o); return }
        self = .null
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    var dict: [String: AnyCodableJSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [AnyCodableJSON]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

// MARK: - Sheet routing

enum TenantSheet: Identifiable, Equatable {
    case add
    case editName(TenantItem)
    case editCost(TenantItem)
    case accountDetail(TenantItem)
    case users(TenantItem)
    case traffic(TenantItem)
    case audit(TenantItem)
    case email(TenantItem)
    case social(TenantItem)
    case quota(TenantItem)
    case bootVolumes(TenantItem)
    case accountCheck
    case exportAll
    case exportOne(TenantItem)
    case importJSON
    case updateProgress(tenantId: Int64, lines: [String])
    /// 原生二级弹层
    case bootCreate(TenantItem)
    case regionSub(TenantItem)
    case cost(TenantItem)
    case trafficQuery(TenantItem)
    case aiChat(TenantItem)
    case passwordResult(title: String, username: String, password: String)
    case securityRules(TenantItem)
    case mysql(TenantItem)

    var id: String {
        switch self {
        case .add: return "add"
        case .editName(let t): return "name-\(t.id)"
        case .editCost(let t): return "cost-\(t.id)"
        case .accountDetail(let t): return "detail-\(t.id)"
        case .users(let t): return "users-\(t.id)"
        case .traffic(let t): return "traffic-\(t.id)"
        case .audit(let t): return "audit-\(t.id)"
        case .email(let t): return "email-\(t.id)"
        case .social(let t): return "social-\(t.id)"
        case .quota(let t): return "quota-\(t.id)"
        case .bootVolumes(let t): return "vol-\(t.id)"
        case .accountCheck: return "check"
        case .exportAll: return "export-all"
        case .exportOne(let t): return "export-\(t.id)"
        case .importJSON: return "import"
        case .updateProgress(let id, _): return "upd-\(id)"
        case .bootCreate(let t): return "boot-\(t.id)"
        case .regionSub(let t): return "regs-\(t.id)"
        case .cost(let t): return "costp-\(t.id)"
        case .trafficQuery(let t): return "tq-\(t.id)"
        case .aiChat(let t): return "ai-\(t.id)"
        case .passwordResult: return "pwd-result"
        case .securityRules(let t): return "rules-\(t.id)"
        case .mysql(let t): return "mysql-\(t.id)"
        }
    }
}

// MARK: - Subpage models

struct TenantImageInfo: Decodable, Equatable, Identifiable {
    var id: String { imageId + operatingSystem + operatingSystemVersion }
    var imageId: String = ""
    var operatingSystem: String = ""
    var operatingSystemVersion: String = ""
}

struct TenantSubscribedRegion: Decodable, Identifiable, Equatable {
    var id: String { regionName.isEmpty ? regionKey : regionName }
    var regionKey: String = ""
    var regionName: String = ""
    var status: String = ""
    var isHomeRegion: Bool = false

    enum CodingKeys: String, CodingKey {
        case regionKey, regionName, status, isHomeRegion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regionKey = (try? c.decode(String.self, forKey: .regionKey)) ?? ""
        regionName = (try? c.decode(String.self, forKey: .regionName)) ?? ""
        if let s = try? c.decode(String.self, forKey: .status) {
            status = s
        } else if let obj = try? c.decode([String: String].self, forKey: .status) {
            status = obj["value"] ?? ""
        }
        isHomeRegion = (try? c.decode(Bool.self, forKey: .isHomeRegion)) ?? false
    }
}

struct TenantUnsubscribedRegion: Decodable, Identifiable, Equatable {
    var id: String { key }
    var key: String = ""
    var name: String = ""
    var cnName: String = ""
}

struct TenantTrafficRow: Decodable, Identifiable, Equatable {
    var id: String { instanceId + (displayName) }
    var instanceId: String = ""
    var displayName: String = ""
    var instanceName: String = ""
    var region: String = ""
    var publicIp: String = ""
    var state: String = ""
    var ingressBytes: Double = 0
    var egressBytes: Double = 0
    var totalBytes: Double = 0

    enum CodingKeys: String, CodingKey {
        case instanceId, displayName, instanceName, region, publicIp, state
        case ingressBytes, egressBytes, totalBytes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instanceId = (try? c.decode(String.self, forKey: .instanceId)) ?? ""
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        instanceName = (try? c.decode(String.self, forKey: .instanceName)) ?? ""
        region = (try? c.decode(String.self, forKey: .region)) ?? ""
        publicIp = (try? c.decode(String.self, forKey: .publicIp)) ?? ""
        state = (try? c.decode(String.self, forKey: .state)) ?? ""
        ingressBytes = (try? c.decode(Double.self, forKey: .ingressBytes)) ?? 0
        egressBytes = (try? c.decode(Double.self, forKey: .egressBytes)) ?? 0
        totalBytes = (try? c.decode(Double.self, forKey: .totalBytes)) ?? 0
    }

    var title: String {
        if !displayName.isEmpty { return displayName }
        if !instanceName.isEmpty { return instanceName }
        return instanceId
    }

    var totalGB: String {
        String(format: "%.2f GB", totalBytes / 1_073_741_824.0)
    }
}

struct TenantAiModel: Identifiable, Equatable {
    var id: String
    var displayName: String
    var version: String
}

struct TenantChatLine: Identifiable, Equatable {
    var id: UUID = UUID()
    var role: String // user / ai
    var text: String
}

enum TenantKnownRegions {
    static let oci: [SelectOption] = [
        "af-johannesburg-1", "af-casablanca-1",
        "ap-chuncheon-1", "ap-hyderabad-1", "ap-melbourne-1", "ap-mumbai-1",
        "ap-osaka-1", "ap-seoul-1", "ap-kulai-2", "ap-singapore-1", "ap-singapore-2",
        "ap-sydney-1", "ap-tokyo-1", "ap-batam-1",
        "ca-montreal-1", "ca-toronto-1",
        "eu-amsterdam-1", "eu-frankfurt-1", "eu-jovanovac-1", "eu-madrid-1", "eu-madrid-3",
        "eu-marseille-1", "eu-milan-1", "eu-turin-1", "eu-paris-1", "eu-stockholm-1", "eu-zurich-1",
        "il-jerusalem-1",
        "me-abudhabi-1", "me-dubai-1", "me-jeddah-1",
        "mx-monterrey-1", "mx-queretaro-1",
        "sa-bogota-1", "sa-santiago-1", "sa-saopaulo-1", "sa-vinhedo-1", "sa-valparaiso-1",
        "uk-cardiff-1", "uk-london-1",
        "us-ashburn-1", "us-chicago-1", "us-phoenix-1", "us-sanjose-1"
    ].map { SelectOption(id: $0, title: $0) }
}
