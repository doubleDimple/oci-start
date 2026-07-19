import Foundation
import SwiftUI

// MARK: - Zones & DNS records (align `/dns/cloudflare/api/*`)

struct CfZone: Identifiable, Equatable, Hashable {
    let id: String
    var name: String = ""
    var status: String = ""

    var title: String {
        status.isEmpty ? name : "\(name) (\(status))"
    }
}

struct CfDnsRecord: Identifiable, Equatable {
    let id: String
    var type: String = "A"
    var name: String = ""
    var content: String = ""
    var ttl: Int = 1
    var proxied: Bool = false
    var priority: Int? = nil
}

struct CfDnsForm: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var isEditing = false
    var recordId = ""
    var type = "A"
    var name = ""
    var content = ""
    var ttl = 1
    var proxied = false

    static func empty() -> CfDnsForm {
        CfDnsForm()
    }

    static func edit(_ r: CfDnsRecord) -> CfDnsForm {
        var f = CfDnsForm()
        f.isEditing = true
        f.recordId = r.id
        f.type = r.type
        f.name = r.name
        f.content = r.content
        f.ttl = r.ttl
        f.proxied = r.proxied
        return f
    }
}

struct CfConfigForm: Identifiable, Equatable {
    var id: String = "cf-config"
    var enabled = false
    var apiToken = ""
    var email = ""
}

enum CloudflareJSON {
    static func parseZones(_ data: Data) throws -> [CfZone] {
        let root = try rootOK(data, fallback: "获取域名列表失败")
        let list = (root["data"] as? [[String: Any]]) ?? []
        return list.compactMap { d in
            let id = str(d["id"])
            guard !id.isEmpty else { return nil }
            return CfZone(id: id, name: str(d["name"]), status: str(d["status"]))
        }
    }

    static func parseRecordsPage(_ data: Data) throws -> (items: [CfDnsRecord], total: Int64, pages: Int) {
        let root = try rootOK(data, fallback: "获取 DNS 记录失败")
        let payload = (root["data"] as? [String: Any]) ?? [:]
        let content = (payload["content"] as? [[String: Any]]) ?? []
        let items = content.compactMap(parseRecord)
        let total = int64(payload["totalElements"], fallback: Int64(items.count))
        let pages = int(payload["totalPages"], fallback: max(1, items.isEmpty ? 0 : 1))
        return (items, total, pages)
    }

    static func parseRecord(_ d: [String: Any]) -> CfDnsRecord? {
        let id = str(d["id"])
        guard !id.isEmpty else { return nil }
        var r = CfDnsRecord(id: id)
        r.type = str(d["type"]).isEmpty ? "A" : str(d["type"])
        r.name = str(d["name"])
        r.content = str(d["content"])
        r.ttl = int(d["ttl"], fallback: 1)
        r.proxied = bool(d["proxied"])
        if d["priority"] != nil {
            r.priority = int(d["priority"])
        }
        return r
    }

    static func parseConfig(_ data: Data) throws -> CfConfigForm {
        let cfg = try KeyConfigJSON.parseConfigs(data)
        var f = CfConfigForm()
        f.enabled = cfg.cloudflare.enabled
        f.apiToken = cfg.cloudflare.apiToken
        f.email = cfg.cloudflare.email
        return f
    }

    static func ensureOK(_ data: Data, fallback: String) throws {
        try KeyConfigJSON.ensureOK(data, fallback: fallback)
    }

    static func parseTestResult(_ data: Data) throws -> String {
        try KeyConfigJSON.parseTestResult(data, fallbackOK: "Cloudflare API 连接成功")
    }

    static func parseSyncMessage(_ data: Data) throws -> String {
        let root = try rootOK(data, fallback: "同步失败")
        let msg = str(root["message"])
        if !msg.isEmpty { return msg }
        if let d = root["data"] as? [String: Any] {
            let count = str(d["syncCount"])
            if !count.isEmpty { return "同步完成，共处理 \(count) 条记录" }
        }
        return "同步完成"
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

    static func int64(_ v: Any?, fallback: Int64 = 0) -> Int64 {
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String, let i = Int64(s) { return i }
        return fallback
    }

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return false
    }

    // MARK: - Display helpers

    static let typeOptions: [SelectOption] = [
        SelectOption(id: "A", title: "A · IPv4"),
        SelectOption(id: "AAAA", title: "AAAA · IPv6"),
        SelectOption(id: "CNAME", title: "CNAME"),
        SelectOption(id: "MX", title: "MX"),
        SelectOption(id: "TXT", title: "TXT"),
        SelectOption(id: "NS", title: "NS")
    ]

    static let ttlOptions: [SelectOption] = [
        SelectOption(id: "1", title: "自动"),
        SelectOption(id: "300", title: "5 分钟"),
        SelectOption(id: "600", title: "10 分钟"),
        SelectOption(id: "1800", title: "30 分钟"),
        SelectOption(id: "3600", title: "1 小时"),
        SelectOption(id: "7200", title: "2 小时"),
        SelectOption(id: "18000", title: "5 小时"),
        SelectOption(id: "43200", title: "12 小时"),
        SelectOption(id: "86400", title: "1 天")
    ]

    static func typeColor(_ type: String) -> Color {
        switch type.uppercased() {
        case "A": return Color(hex: "43b581")
        case "AAAA": return Color(hex: "1abc9c")
        case "CNAME": return Color(hex: "7289da")
        case "TXT": return Color(hex: "faa61a")
        case "MX": return Color(hex: "f38020")
        case "NS": return Color(hex: "99aab5")
        default: return Color(hex: "58a6ff")
        }
    }

    static func formatTTL(_ ttl: Int) -> String {
        switch ttl {
        case 1: return "自动"
        case 300: return "5m"
        case 600: return "10m"
        case 1800: return "30m"
        case 3600: return "1h"
        case 7200: return "2h"
        case 18000: return "5h"
        case 43200: return "12h"
        case 86400: return "1d"
        default: return "\(ttl)s"
        }
    }
}
