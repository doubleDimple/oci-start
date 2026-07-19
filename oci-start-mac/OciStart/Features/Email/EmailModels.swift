import Foundation

// MARK: - Sheets

enum EmailSheet: Identifiable, Equatable {
    case compose
    case addContact
    case enableTenant(DisabledTenantItem)
    case recordDetail(EmailBodyItem)

    var id: String {
        switch self {
        case .compose: return "compose"
        case .addContact: return "addContact"
        case .enableTenant(let t): return "enable-\(t.id)"
        case .recordDetail(let r): return "detail-\(r.emailBodyId.isEmpty ? "\(r.id)" : r.emailBodyId)"
        }
    }
}

/// 邮件管理主分区（全页切换，避免三栏嵌套滚动）。
enum EmailMainSection: String, CaseIterable, Identifiable {
    case tenants
    case contacts
    case records

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tenants: return "租户服务"
        case .contacts: return "收件人"
        case .records: return "发送记录"
        }
    }

    var systemImage: String {
        switch self {
        case .tenants: return "server.rack"
        case .contacts: return "person.2"
        case .records: return "envelope"
        }
    }
}

enum EmailTenantTab: String, CaseIterable, Identifiable {
    case enabled
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enabled: return "已开启"
        case .disabled: return "未开启"
        }
    }

    var systemImage: String {
        switch self {
        case .enabled: return "checkmark.circle"
        case .disabled: return "plus.circle"
        }
    }
}

// MARK: - Tenant email config (enabled)

struct TenantEmailConfigItem: Identifiable, Equatable {
    var id: Int64 = 0
    var tenantId: Int64 = 0
    var tenantName: String = ""
    var domainName: String = ""
    var senderEmail: String = ""
    var active: Bool = true
    var dailyEmailLimit: Int64 = 200
    var todaySentCount: Int64 = 0
    var createdTime: String = ""

    var displaySender: String {
        if !senderEmail.isEmpty { return senderEmail }
        if !domainName.isEmpty { return domainName }
        return tenantId > 0 ? "租户 \(tenantId)" : "#\(id)"
    }

    var usagePercent: Double {
        guard dailyEmailLimit > 0 else { return 0 }
        return min(1, Double(todaySentCount) / Double(dailyEmailLimit))
    }

    var usageTone: StatusTone {
        let p = usagePercent
        if p >= 0.9 { return .danger }
        if p >= 0.75 { return .warning }
        return .success
    }
}

// MARK: - Disabled tenant (not yet enabled)

struct DisabledTenantItem: Identifiable, Equatable {
    var id: Int64 = 0
    var name: String = ""
    var region: String = ""
}

// MARK: - Contact (receive)

struct EmailContactItem: Identifiable, Equatable {
    var id: Int64 = 0
    var name: String = ""
    var email: String = ""
    var createTime: String = ""
}

// MARK: - Email body (send record)

struct EmailBodyItem: Identifiable, Equatable {
    var id: Int64 = 0
    var emailBodyId: String = ""
    var tenantId: Int64 = 0
    var tenantName: String = ""
    var tenantEmailConfigId: Int64 = 0
    var senderEmail: String = ""
    var title: String = ""
    var content: String = ""
    var receiveTotal: Int64 = 0
    var receiveSuccessTotal: Int64 = 0
    var receiveFailTotal: Int64 = 0
    var createTime: String = ""

    var subjectText: String { title.isEmpty ? "（无主题）" : title }
    var tenantText: String {
        if !tenantName.isEmpty { return tenantName }
        if !senderEmail.isEmpty { return senderEmail }
        return "—"
    }
}

// MARK: - Per-recipient send record

struct EmailSendRecordItem: Identifiable, Equatable {
    var id: Int64 = 0
    var emailSendRecordId: String = ""
    var emailBodyId: String = ""
    var receiveEmailAddress: String = ""
    var sendState: Int = 0
    var createTime: String = ""

    var isSuccess: Bool { sendState == 1 }
    var stateLabel: String { isSuccess ? "成功" : "失败" }
    var stateTone: StatusTone { isSuccess ? .success : .danger }
}

// MARK: - Page wrappers

struct EmailPageResult<T> {
    var content: [T] = []
    var totalElements: Int64 = 0
    var totalPages: Int = 0
    var number: Int = 0
    var size: Int = 10
}

// MARK: - JSON helpers

enum EmailJSON {
    static func obj(_ raw: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    static func string(_ any: Any?) -> String {
        guard let any = any else { return "" }
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if any is NSNull { return "" }
        return "\(any)"
    }

    static func int64(_ any: Any?) -> Int64 {
        guard let any = any else { return 0 }
        if let n = any as? Int64 { return n }
        if let n = any as? Int { return Int64(n) }
        if let n = any as? Double { return Int64(n) }
        if let n = any as? NSNumber { return n.int64Value }
        if let s = any as? String, let v = Int64(s) { return v }
        return 0
    }

    static func int(_ any: Any?) -> Int { Int(int64(any)) }

    static func bool(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        if let s = any as? String {
            let l = s.lowercased()
            return l == "true" || l == "1"
        }
        return false
    }

    static func dateString(_ any: Any?) -> String {
        if let s = any as? String, !s.isEmpty {
            return s.replacingOccurrences(of: "T", with: " ")
        }
        if let arr = any as? [Any], arr.count >= 5 {
            let y = int(arr[0]), m = int(arr[1]), d = int(arr[2])
            let h = int(arr[3]), mi = int(arr[4])
            let s = arr.count > 5 ? int(arr[5]) : 0
            return String(format: "%04d-%02d-%02d %02d:%02d:%02d", y, m, d, h, mi, s)
        }
        return ""
    }

    /// `ApiResponse` envelope → data dict / array / nil
    static func envelopeData(_ raw: Data) throws -> Any? {
        guard let root = obj(raw) else {
            throw APIError.serverMessage("响应解析失败")
        }
        if let success = root["success"] as? Bool, !success {
            let msg = string(root["message"]).isEmpty ? "操作失败" : string(root["message"])
            throw APIError.serverMessage(msg)
        }
        if let code = root["code"] as? Int, code != 200, code != 0 {
            let msg = string(root["message"]).isEmpty ? "操作失败" : string(root["message"])
            throw APIError.serverMessage(msg)
        }
        return root["data"]
    }

    static func ensureSuccess(_ raw: Data, fallback: String = "操作失败") throws {
        guard let root = obj(raw) else { return }
        if let success = root["success"] as? Bool, !success {
            let msg = string(root["message"]).isEmpty ? fallback : string(root["message"])
            throw APIError.serverMessage(msg)
        }
        if let code = root["code"] as? Int, code != 200, code != 0 {
            let msg = string(root["message"]).isEmpty ? fallback : string(root["message"])
            throw APIError.serverMessage(msg)
        }
    }

    static func pageDict(_ raw: Data) throws -> [String: Any] {
        let data = try envelopeData(raw)
        if let d = data as? [String: Any] { return d }
        throw APIError.serverMessage("分页数据解析失败")
    }

    static func parsePageMeta(_ page: [String: Any]) -> (total: Int64, pages: Int, number: Int, size: Int) {
        let total = int64(page["totalElements"])
        let pages = int(page["totalPages"])
        var number = int(page["number"])
        if number == 0, page["number"] == nil {
            number = int(page["currentPage"])
        }
        if let pageable = page["pageable"] as? [String: Any], page["number"] == nil, page["currentPage"] == nil {
            number = int(pageable["pageNumber"])
        }
        let size = int(page["size"])
        return (total, pages, number, size > 0 ? size : 10)
    }

    static func contentArray(_ page: [String: Any]) -> [[String: Any]] {
        (page["content"] as? [[String: Any]]) ?? []
    }

    // MARK: - Item parsers

    static func parseConfig(_ d: [String: Any]) -> TenantEmailConfigItem {
        var item = TenantEmailConfigItem()
        item.id = int64(d["id"])
        item.tenantId = int64(d["tenantId"])
        item.tenantName = string(d["tenantName"])
        item.domainName = string(d["domainName"])
        item.senderEmail = string(d["senderEmail"])
        item.active = bool(d["active"])
        item.dailyEmailLimit = int64(d["dailyEmailLimit"])
        if item.dailyEmailLimit <= 0 { item.dailyEmailLimit = 200 }
        item.todaySentCount = int64(d["todaySentCount"])
        item.createdTime = dateString(d["createdTime"])
        return item
    }

    static func parseContact(_ d: [String: Any]) -> EmailContactItem {
        var item = EmailContactItem()
        item.id = int64(d["id"])
        item.name = string(d["name"])
        item.email = string(d["email"])
        item.createTime = dateString(d["createTime"])
        return item
    }

    static func parseBody(_ d: [String: Any]) -> EmailBodyItem {
        var item = EmailBodyItem()
        item.id = int64(d["id"])
        item.emailBodyId = string(d["emailBodyId"])
        item.tenantId = int64(d["tenantId"])
        item.tenantName = string(d["tenantName"])
        item.tenantEmailConfigId = int64(d["tenantEmailConfigId"])
        item.senderEmail = string(d["senderEmail"])
        item.title = string(d["title"])
        item.content = string(d["content"])
        item.receiveTotal = int64(d["receiveTotal"])
        item.receiveSuccessTotal = int64(d["receiveSuccessTotal"])
        item.receiveFailTotal = int64(d["receiveFailTotal"])
        item.createTime = dateString(d["createTime"])
        return item
    }

    static func parseSendRecord(_ d: [String: Any]) -> EmailSendRecordItem {
        var item = EmailSendRecordItem()
        item.id = int64(d["id"])
        item.emailSendRecordId = string(d["emailSendRecordId"])
        item.emailBodyId = string(d["emailBodyId"])
        item.receiveEmailAddress = string(d["receiveEmailAddress"])
        item.sendState = int(d["sendState"])
        item.createTime = dateString(d["createTime"])
        return item
    }

    static func parseDisabledTenant(_ d: [String: Any]) -> DisabledTenantItem {
        var item = DisabledTenantItem()
        item.id = int64(d["id"])
        let tenancyName = string(d["tenancyName"])
        let defName = string(d["defName"])
        if !tenancyName.isEmpty {
            item.name = tenancyName
        } else if !defName.isEmpty {
            item.name = defName
        } else {
            item.name = item.id > 0 ? "#\(item.id)" : "—"
        }
        item.region = string(d["region"])
        return item
    }
}
