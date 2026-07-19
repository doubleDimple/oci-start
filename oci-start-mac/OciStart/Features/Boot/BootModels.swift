import Foundation

// MARK: - Sheets

enum BootSheet: Identifiable, Equatable {
    case editDetail(BootDetailItem)
    /// 原生添加抢机配置（对齐 Web `/tenants/bootPage`，禁止 WebEmbed）
    case createConfig(BootTaskItem)

    var id: String {
        switch self {
        case .editDetail(let d): return "edit-\(d.id)"
        case .createConfig(let t): return "create-\(t.id)-\(t.tenantId)"
        }
    }

    static func == (lhs: BootSheet, rhs: BootSheet) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Boot log line (web full_machine_list.js appendBootLogLine)

struct BootLogLine: Identifiable, Equatable {
    let id: Int
    let text: String
    let tone: BootLogTone

    enum BootLogTone: Equatable {
        case normal, success, warn, error
    }

    static func make(id: Int, raw: String) -> BootLogLine {
        // 对齐 web appendBootLogLine
        var text = raw
        var tone: BootLogTone = .normal
        if text.range(of: "[success]", options: .caseInsensitive) != nil {
            tone = .success
            text = text.replacingOccurrences(of: "[success]", with: "", options: .caseInsensitive)
        } else if text.range(of: "[warn]", options: .caseInsensitive) != nil {
            tone = .warn
            text = text.replacingOccurrences(of: "[warn]", with: "", options: .caseInsensitive)
        } else if text.range(of: "[error]", options: .caseInsensitive) != nil {
            tone = .error
            text = text.replacingOccurrences(of: "[error]", with: "", options: .caseInsensitive)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return BootLogLine(id: id, text: text.isEmpty ? raw : text, tone: tone)
    }
}

enum BootLogConnectionState: Equatable {
    case disconnected, connecting, connected
    var title: String {
        switch self {
        case .disconnected: return "已断开"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        }
    }
}

// MARK: - Main list row (grouped task from fullBootList)

struct BootTaskItem: Identifiable, Equatable {
    var id: Int64 = 0
    var bootId: String = ""
    var tenantId: Int64 = 0
    var tenancyName: String = ""
    var defName: String = ""
    var userName: String = ""
    var regionName: String = ""
    var architecture: String = ""
    var openBootFlag: Bool = false
    var recordCount: Int64 = 0
    var executingCount: Int64 = 0
    var totalCount: Int64 = 0
    var yesterdayAttemptCount: Int = 0
    var currentAttemptCount: Int = 0
    var failCount: Int = 0
    var successCount: Int = 0
    var createAtStr: String = ""
    var status: Int = 0
    var ocpu: Int = 0
    var memory: Int = 0
    var disk: Int = 0
    var loopTime: Int = 0
    var dayGap: String = ""
    var rootPassword: String = ""

    var displayTenant: String {
        if !tenancyName.isEmpty { return tenancyName }
        if !defName.isEmpty { return defName }
        if !userName.isEmpty { return userName }
        return tenantId > 0 ? "#\(tenantId)" : "—"
    }

    var maskedTenant: String {
        let tn = displayTenant
        if tn.isEmpty || tn == "—" { return "—" }
        if tn.count <= 2 { return "***" }
        return "\(tn.prefix(1))***\(tn.suffix(1))"
    }

    var remarkText: String {
        defName.isEmpty ? "—" : defName
    }

    var taskStatusText: String { openBootFlag ? "有任务" : "无任务" }
    var taskStatusTone: StatusTone { openBootFlag ? .success : .neutral }

    var archText: String { architecture.isEmpty ? "—" : architecture }
    var createText: String { createAtStr.isEmpty ? "—" : createAtStr }
}

// MARK: - Detail subtask (bootDetail)

struct BootDetailItem: Identifiable, Equatable {
    var id: Int64 = 0
    var bootId: String = ""
    var tenantId: Int64 = 0
    var status: Int = 0
    var architecture: String = ""
    var ocpu: Int = 0
    var memory: Int = 0
    var disk: Int = 0
    var loopTime: Int = 0
    var dayGap: String = ""
    var rootPassword: String = ""
    var operatingSystem: String = ""
    var operatingSystemVersion: String = ""
    var yesterdayAttemptCount: Int = 0
    var currentAttemptCount: Int = 0
    var failCount: Int = 0
    var successCount: Int = 0
    var createdAt: String = ""

    var statusText: String {
        switch status {
        case 0: return "未开机"
        case 1: return "开机中"
        case 2: return "已开机"
        default: return "未知"
        }
    }

    var statusTone: StatusTone {
        switch status {
        case 0: return .neutral
        case 1: return .warning
        case 2: return .success
        default: return .neutral
        }
    }

    var configText: String {
        "\(ocpu)/\(memory)/\(disk)/\(architecture.isEmpty ? "—" : architecture)"
    }

    var osText: String {
        let os = operatingSystem.isEmpty ? "—" : operatingSystem
        let ver = operatingSystemVersion.isEmpty ? "—" : operatingSystemVersion
        return "\(os)/\(ver)"
    }
}

// MARK: - List response

struct BootListResponse: Equatable {
    var content: [BootTaskItem] = []
    var currentPage: Int = 0
    var totalPages: Int = 0
    var totalElements: Int64 = 0
    var size: Int = 20
}

// MARK: - JSON

enum BootJSON {
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

    static func ensureSuccess(_ raw: Data, fallback: String = "操作失败") throws {
        guard let root = obj(raw) else { return }
        if let success = root["success"] as? Bool {
            if !success {
                let msg = string(root["message"]).isEmpty ? fallback : string(root["message"])
                throw APIError.serverMessage(msg)
            }
            return
        }
        if let code = root["code"] as? Int, code != 200, code != 0 {
            let msg = string(root["message"]).isEmpty ? fallback : string(root["message"])
            throw APIError.serverMessage(msg)
        }
    }

    static func parseList(_ raw: Data) throws -> BootListResponse {
        guard let root = obj(raw) else {
            throw APIError.serverMessage("开机列表响应无效")
        }
        // Support both flat page shape and ApiResponse envelope
        let page: [String: Any]
        if let data = root["data"] as? [String: Any], data["content"] != nil || data["list"] != nil {
            page = data
        } else {
            page = root
        }
        let arr = (page["content"] as? [[String: Any]])
            ?? (page["list"] as? [[String: Any]])
            ?? []
        var resp = BootListResponse()
        resp.content = arr.map { parseTask($0) }
        resp.currentPage = int(page["currentPage"] ?? page["number"])
        resp.totalPages = int(page["totalPages"])
        resp.totalElements = int64(page["totalElements"] ?? page["total"])
        resp.size = int(page["size"])
        if resp.size <= 0 { resp.size = 20 }
        if resp.totalPages <= 0, resp.totalElements > 0, resp.size > 0 {
            resp.totalPages = Int((resp.totalElements + Int64(resp.size) - 1) / Int64(resp.size))
        }
        return resp
    }

    static func parseTask(_ d: [String: Any]) -> BootTaskItem {
        var t = BootTaskItem()
        t.id = int64(d["id"])
        t.bootId = string(d["bootId"])
        t.tenantId = int64(d["tenantId"])
        t.tenancyName = string(d["tenancyName"])
        t.defName = string(d["defName"])
        t.userName = string(d["userName"])
        t.regionName = string(d["regionName"])
        t.architecture = string(d["architecture"])
        t.openBootFlag = bool(d["openBootFlag"])
        t.recordCount = int64(d["recordCount"])
        t.executingCount = int64(d["executingCount"])
        t.totalCount = int64(d["totalCount"])
        t.yesterdayAttemptCount = int(d["yesterdayAttemptCount"])
        t.currentAttemptCount = int(d["currentAttemptCount"])
        t.failCount = int(d["failCount"])
        t.successCount = int(d["successCount"])
        t.createAtStr = string(d["createAtStr"])
        if t.createAtStr.isEmpty { t.createAtStr = dateString(d["createdAt"]) }
        t.status = int(d["status"])
        t.ocpu = int(d["ocpu"])
        t.memory = int(d["memory"])
        t.disk = int(d["disk"])
        t.loopTime = int(d["loopTime"])
        t.dayGap = string(d["dayGap"])
        t.rootPassword = string(d["rootPassword"])
        return t
    }

    static func parseDetail(_ d: [String: Any]) -> BootDetailItem {
        var t = BootDetailItem()
        t.id = int64(d["id"])
        t.bootId = string(d["bootId"])
        t.tenantId = int64(d["tenantId"])
        t.status = int(d["status"])
        t.architecture = string(d["architecture"])
        t.ocpu = int(d["ocpu"])
        t.memory = int(d["memory"])
        t.disk = int(d["disk"])
        t.loopTime = int(d["loopTime"])
        t.dayGap = string(d["dayGap"])
        t.rootPassword = string(d["rootPassword"])
        t.operatingSystem = string(d["operatingSystem"])
        t.operatingSystemVersion = string(d["operatingSystemVersion"])
        t.yesterdayAttemptCount = int(d["yesterdayAttemptCount"])
        t.currentAttemptCount = int(d["currentAttemptCount"])
        t.failCount = int(d["failCount"])
        t.successCount = int(d["successCount"])
        t.createdAt = dateString(d["createdAt"])
        return t
    }

    static func parseDetailList(_ raw: Data) throws -> [BootDetailItem] {
        guard let root = obj(raw) else {
            throw APIError.serverMessage("详情响应无效")
        }
        try ensureSuccess(raw, fallback: "加载详情失败")
        let arr = (root["data"] as? [[String: Any]]) ?? []
        return arr.map { parseDetail($0) }
    }
}
