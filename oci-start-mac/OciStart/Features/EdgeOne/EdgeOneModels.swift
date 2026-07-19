import Foundation
import SwiftUI

// MARK: - EdgeOne zones / DNS / acceleration (align `/dns/edgeone/api/*`)

enum EdgeOneMode: String, CaseIterable, Identifiable {
    case dns
    case domain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dns: return "DNS 记录"
        case .domain: return "加速域名"
        }
    }

    var systemImage: String {
        switch self {
        case .dns: return "server.rack"
        case .domain: return "speedometer"
        }
    }
}

struct EoZone: Identifiable, Equatable, Hashable {
    let id: String
    var name: String = ""
    var status: String = ""

    var title: String {
        status.isEmpty ? name : "\(name) (\(status))"
    }
}

struct EoDnsRecord: Identifiable, Equatable {
    let id: String
    var type: String = "A"
    var name: String = ""
    var content: String = ""
    var ttl: Int = 300
    var priority: Int? = nil
}

struct EoAccelDomain: Identifiable, Equatable {
    let id: String
    var domainName: String = ""
    var status: String = ""
    var cname: String = ""
    var http = true
    var https = true

    var protocolLabel: String {
        switch (http, https) {
        case (true, true): return "HTTP/HTTPS"
        case (true, false): return "HTTP"
        case (false, true): return "HTTPS"
        default: return "—"
        }
    }

    var statusTone: StatusTone {
        switch status.lowercased() {
        case "online", "active", "process": return .success
        case "offline", "forbidden", "deleted": return .danger
        case "pending", "init", "stopped": return .warning
        default: return .neutral
        }
    }
}

struct EoDnsForm: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var isEditing = false
    var recordId = ""
    var type = "A"
    var name = ""
    var content = ""
    var ttl = 300
    var priority: String = ""

    static func empty() -> EoDnsForm { EoDnsForm() }

    static func edit(_ r: EoDnsRecord) -> EoDnsForm {
        var f = EoDnsForm()
        f.isEditing = true
        f.recordId = r.id
        f.type = r.type
        f.name = r.name
        f.content = r.content
        f.ttl = r.ttl
        if let p = r.priority { f.priority = "\(p)" }
        return f
    }
}

struct EoConfigForm: Identifiable, Equatable {
    var id: String = "eo-config"
    var enabled = false
    var secretId = ""
    var secretKey = ""
    var region = "ap-beijing"
}

enum EdgeOneJSON {
    static func parseZones(_ data: Data) throws -> [EoZone] {
        let root = try rootOK(data, fallback: "获取域名列表失败")
        let list = (root["data"] as? [[String: Any]]) ?? []
        return list.compactMap { d in
            let id = str(d["id"])
            guard !id.isEmpty else { return nil }
            return EoZone(id: id, name: str(d["name"]), status: str(d["status"]))
        }
    }

    static func parseDnsRecords(_ data: Data) throws -> [EoDnsRecord] {
        let root = try rootOK(data, fallback: "获取 DNS 记录失败")
        let list = (root["data"] as? [[String: Any]]) ?? []
        return list.compactMap { d in
            let id = str(d["id"])
            guard !id.isEmpty else { return nil }
            var r = EoDnsRecord(id: id)
            r.type = str(d["type"]).isEmpty ? "A" : str(d["type"])
            r.name = str(d["name"])
            r.content = str(d["content"])
            r.ttl = int(d["ttl"], fallback: 300)
            if d["priority"] != nil { r.priority = int(d["priority"]) }
            return r
        }
    }

    static func parseAccelDomains(_ data: Data) throws -> [EoAccelDomain] {
        let root = try rootOK(data, fallback: "获取加速域名失败")
        let list = (root["data"] as? [[String: Any]]) ?? []
        return list.compactMap { d in
            let id = str(d["id"])
            let name = str(d["domainName"]).isEmpty ? str(d["name"]) : str(d["domainName"])
            guard !id.isEmpty || !name.isEmpty else { return nil }
            var r = EoAccelDomain(id: id.isEmpty ? name : id)
            r.domainName = name
            r.status = str(d["status"])
            r.cname = str(d["cname"]).isEmpty ? str(d["content"]) : str(d["cname"])
            r.http = bool(d["http"], fallback: true)
            r.https = bool(d["https"], fallback: true)
            return r
        }
    }

    static func parseConfig(_ data: Data) throws -> EoConfigForm {
        let cfg = try KeyConfigJSON.parseConfigs(data)
        var f = EoConfigForm()
        f.enabled = cfg.edgeOne.enabled
        f.secretId = cfg.edgeOne.secretId
        f.secretKey = cfg.edgeOne.secretKey
        f.region = cfg.edgeOne.region
        return f
    }

    static func ensureOK(_ data: Data, fallback: String) throws {
        try KeyConfigJSON.ensureOK(data, fallback: fallback)
    }

    static func parseTestResult(_ data: Data) throws -> String {
        try KeyConfigJSON.parseTestResult(data, fallbackOK: "腾讯云 EdgeOne API 连接成功")
    }

    static func parseSyncMessage(_ data: Data) throws -> String {
        let root = try rootOK(data, fallback: "同步失败")
        let msg = str(root["message"])
        return msg.isEmpty ? "同步完成" : msg
    }

    static func rootOK(_ data: Data, fallback: String) throws -> [String: Any] {
        guard let root = obj(data) else {
            throw APIError.serverMessage(fallback)
        }
        if let success = root["success"] as? Bool, !success {
            throw APIError.serverMessage(str(root["message"]).isEmpty ? fallback : str(root["message"]))
        }
        return root
    }

    static func obj(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func int(_ v: Any?, fallback: Int = 0) -> Int {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let i = Int(s) { return i }
        return fallback
    }

    static func bool(_ v: Any?, fallback: Bool = false) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return fallback
    }

    static let typeOptions: [SelectOption] = CloudflareJSON.typeOptions
    static let ttlOptions: [SelectOption] = [
        SelectOption(id: "60", title: "1 分钟"),
        SelectOption(id: "300", title: "5 分钟"),
        SelectOption(id: "600", title: "10 分钟"),
        SelectOption(id: "1800", title: "30 分钟"),
        SelectOption(id: "3600", title: "1 小时"),
        SelectOption(id: "86400", title: "1 天")
    ]

    static func typeColor(_ type: String) -> Color {
        CloudflareJSON.typeColor(type)
    }

    static func formatTTL(_ ttl: Int) -> String {
        CloudflareJSON.formatTTL(ttl)
    }
}
