import Foundation

// MARK: - List item (`InstanceDetailsRes` / `/oci/list/json`)

/// 一行实例（对齐 Web `InstanceDetailsRes`）。
/// - `id`：本地 `instance_detail` 主键（绝大多数 `/oci/*` 动作参数 `instanceId` 用这个）
/// - `instanceId`：OCI OCID（VNIC 等少数接口用）
struct InstanceItem: Identifiable, Equatable {
    var id: String = ""
    var tenantId: Int64 = 0
    var tenantIdStr: String = ""
    var instanceId: String = ""
    var displayName: String = ""
    var shape: String = ""
    var state: String = ""
    var ocpus: Int = 0
    var memoryInGBs: Int = 0
    var bootVolumeSizeInGBs: Int64 = 0
    var publicIps: String = ""
    var privateIps: String = ""
    var availabilityDomain: String = ""
    var compartmentId: String = ""
    var userName: String = ""
    var remark: String = ""
    var bootVolumeName: String = ""
    var bootVolumeId: String = ""
    var createTime: String = ""
    var timeCreated: String = ""
    var ipv6Addresses: String = ""
    var tenancyName: String = ""
    var vpusPerGB: String = "0"
    var cloudType: Int = 1
    var architecture: String = ""
    var cpuAndMem: String = "/"
    var regionName: String = ""
    var regionCode: String = ""

    var stateLower: String { state.lowercased() }
    var isRunning: Bool { stateLower == "running" }
    var isStopped: Bool { stateLower == "stopped" }
    var hasIpv6: Bool {
        let s = ipv6Addresses.trimmingCharacters(in: .whitespacesAndNewlines)
        return !s.isEmpty && s != "—" && s != "-"
    }

    var volumeText: String {
        let vpu = vpusPerGB.isEmpty ? "0" : vpusPerGB
        if bootVolumeSizeInGBs > 0 {
            return "\(bootVolumeSizeInGBs)GB/\(vpu)"
        }
        return "—/\(vpu)"
    }

    var createDateText: String {
        if !createTime.isEmpty { return String(createTime.prefix(10)) }
        if !timeCreated.isEmpty { return String(timeCreated.prefix(10)) }
        return "—"
    }

    var maskedTenancyName: String {
        let tn = tenancyName
        if tn.isEmpty { return "—" }
        if tn.count <= 2 { return "***" }
        return "\(tn.prefix(1))***\(tn.suffix(1))"
    }

    var stateLabel: String {
        switch stateLower {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "starting": return "启动中"
        case "stopping": return "停止中"
        case "terminated", "terminating": return "已终止"
        default: return state.isEmpty ? "未知" : state
        }
    }
}

struct InstancesListResponse: Equatable {
    var content: [InstanceItem] = []
    var currentPage: Int = 0
    var totalPages: Int = 0
    var totalElements: Int64 = 0
    var size: Int = 10
}

// MARK: - Flexible decode helpers

enum InstanceJSON {
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

    static func int(_ any: Any?) -> Int {
        Int(int64(any))
    }

    /// Jackson Date → epoch ms / seconds / ISO string
    static func dateString(_ any: Any?) -> String {
        if let s = any as? String, !s.isEmpty {
            if s.count >= 10 { return String(s.prefix(19)).replacingOccurrences(of: "T", with: " ") }
            return s
        }
        if let n = any as? NSNumber {
            var ms = n.doubleValue
            if ms < 1_000_000_000_000 { ms *= 1000 } // seconds → ms
            let date = Date(timeIntervalSince1970: ms / 1000)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: date)
        }
        return ""
    }

    static func parseList(_ data: Data) throws -> InstancesListResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.serverMessage("实例列表响应无效")
        }
        let arr = (root["content"] as? [Any]) ?? []
        var items: [InstanceItem] = []
        items.reserveCapacity(arr.count)
        for el in arr {
            guard let m = el as? [String: Any] else { continue }
            items.append(parseItem(m))
        }
        var resp = InstancesListResponse()
        resp.content = items
        resp.currentPage = int(root["currentPage"])
        resp.totalPages = int(root["totalPages"])
        resp.totalElements = int64(root["totalElements"])
        resp.size = int(root["size"])
        if resp.size <= 0 { resp.size = 10 }
        return resp
    }

    static func parseItem(_ m: [String: Any]) -> InstanceItem {
        var it = InstanceItem()
        it.id = string(m["id"])
        it.tenantId = int64(m["tenantId"])
        it.tenantIdStr = string(m["tenantIdStr"]).isEmpty ? string(m["tenantId"]) : string(m["tenantIdStr"])
        it.instanceId = string(m["instanceId"])
        it.displayName = string(m["displayName"])
        it.shape = string(m["shape"])
        it.state = string(m["state"])
        it.ocpus = int(m["ocpus"])
        it.memoryInGBs = int(m["memoryInGBs"])
        it.bootVolumeSizeInGBs = int64(m["bootVolumeSizeInGBs"])
        it.publicIps = string(m["publicIps"])
        it.privateIps = string(m["privateIps"])
        it.availabilityDomain = string(m["availabilityDomain"])
        it.compartmentId = string(m["compartmentId"])
        it.userName = string(m["userName"])
        it.remark = string(m["remark"])
        it.bootVolumeName = string(m["bootVolumeName"])
        it.bootVolumeId = string(m["bootVolumeId"])
        it.createTime = dateString(m["createTime"])
        it.timeCreated = string(m["timeCreated"])
        it.ipv6Addresses = string(m["ipv6Addresses"])
        it.tenancyName = string(m["tenancyName"])
        let vpu = string(m["vpusPerGB"])
        it.vpusPerGB = vpu.isEmpty ? "0" : vpu
        it.cloudType = int(m["cloudType"])
        if it.cloudType == 0 { it.cloudType = 1 }
        it.architecture = string(m["architecture"])
        var cm = string(m["cpuAndMem"])
        if cm.isEmpty || cm == "/" {
            if it.ocpus > 0 || it.memoryInGBs > 0 {
                cm = "\(it.ocpus)C\(it.memoryInGBs)G"
            } else {
                cm = "/"
            }
        }
        it.cpuAndMem = cm
        it.regionName = string(m["regionName"])
        it.regionCode = string(m["regionCode"])
        return it
    }

    static func successMessage(_ data: Data, fallback: String = "成功") -> (ok: Bool, message: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (true, fallback)
        }
        if let status = obj["status"] as? String {
            let msg = string(obj["message"]).isEmpty ? fallback : string(obj["message"])
            return (status.lowercased() == "success", msg)
        }
        if let ok = obj["success"] as? Bool {
            let msg = string(obj["message"]).isEmpty ? (ok ? fallback : "失败") : string(obj["message"])
            return (ok, msg)
        }
        if let code = obj["code"] as? Int {
            let ok = code == 200 || code == 0
            let msg = string(obj["message"]).isEmpty ? (ok ? fallback : "失败") : string(obj["message"])
            return (ok, msg)
        }
        // 无明确字段时视为成功（部分接口只返回 data）
        return (true, string(obj["message"]).isEmpty ? fallback : string(obj["message"]))
    }
}

// MARK: - Sheets

enum InstanceSheet: Identifiable, Equatable {
    case updateName(InstanceItem)
    case updateRemark(InstanceItem)
    case updateConfig(InstanceItem)
    case updateBoot(InstanceItem)
    case updateVpu(InstanceItem)
    case changeIp(InstanceItem)
    case terminate(InstanceItem)
    case embed(title: String, path: String, query: [String: String])

    var id: String {
        switch self {
        case .updateName(let i): return "name-\(i.id)"
        case .updateRemark(let i): return "remark-\(i.id)"
        case .updateConfig(let i): return "cfg-\(i.id)"
        case .updateBoot(let i): return "boot-\(i.id)"
        case .updateVpu(let i): return "vpu-\(i.id)"
        case .changeIp(let i): return "ip-\(i.id)"
        case .terminate(let i): return "term-\(i.id)"
        case .embed(let title, let path, _): return "embed-\(title)-\(path)"
        }
    }
}
