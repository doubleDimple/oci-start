import Foundation

struct AiTenantOption: Identifiable, Equatable {
    var id: String = ""
    var name: String = ""
}

struct AiAvailableModel: Identifiable, Equatable {
    var id: String = ""
    var name: String = ""
    var provider: String = ""
    var tenantId: String = ""
    var description: String = ""
}

struct AiConfigItem: Identifiable, Equatable {
    var id: Int64 = 0
    var tenantId: String = ""
    var modelId: String = ""
    var modelName: String = ""
    var provider: String = ""
    var enabled: Bool = true
    var userName: String = ""
    var region: String = ""
}

enum AiModelsJSON {
    static func string(_ any: Any?) -> String {
        guard let any = any else { return "" }
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if any is NSNull { return "" }
        return "\(any)"
    }

    static func int64(_ any: Any?) -> Int64 {
        if let n = any as? Int64 { return n }
        if let n = any as? Int { return Int64(n) }
        if let n = any as? NSNumber { return n.int64Value }
        if let s = any as? String, let v = Int64(s) { return v }
        return 0
    }

    static func bool(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        if let s = any as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return false
    }

    static func parseTenants(_ data: Data) -> [AiTenantOption] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.map { m in
            var t = AiTenantOption()
            t.id = string(m["id"])
            t.name = string(m["name"])
            return t
        }
    }

    static func parseModels(_ data: Data) -> [AiAvailableModel] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.map { m in
            var it = AiAvailableModel()
            it.id = string(m["id"])
            it.name = string(m["name"]).isEmpty ? string(m["displayName"]) : string(m["name"])
            it.provider = string(m["provider"]).isEmpty ? "OCI" : string(m["provider"])
            it.tenantId = string(m["tenantId"])
            it.description = string(m["description"])
            return it
        }
    }

    static func parseConfigs(_ data: Data) -> [AiConfigItem] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.map { m in
            var it = AiConfigItem()
            it.id = int64(m["id"])
            it.tenantId = string(m["tenantId"])
            it.modelId = string(m["modelId"])
            it.modelName = string(m["modelName"])
            it.provider = string(m["provider"])
            it.enabled = bool(m["enabled"])
            it.userName = string(m["userName"])
            it.region = string(m["region"])
            return it
        }
    }
}
