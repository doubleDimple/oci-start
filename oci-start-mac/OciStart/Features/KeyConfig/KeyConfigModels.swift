import Foundation

// MARK: - Domain provider credentials (align `/api/system/domainProviderConfigs`)

struct CloudflareKeyConfig: Equatable {
    var enabled = false
    var apiToken = ""
    var email = ""
    var zoneId = ""
}

struct EdgeOneKeyConfig: Equatable {
    var enabled = false
    var secretId = ""
    var secretKey = ""
    var region = "ap-beijing"
}

struct DomainProviderConfigs: Equatable {
    var cloudflare = CloudflareKeyConfig()
    var edgeOne = EdgeOneKeyConfig()
}

enum KeyConfigJSON {
    static func parseConfigs(_ data: Data) throws -> DomainProviderConfigs {
        guard let root = obj(data) else {
            throw APIError.serverMessage("密钥配置解析失败")
        }
        if let success = root["success"] as? Bool, success == false {
            throw APIError.serverMessage(str(root["message"]).isEmpty ? "加载密钥配置失败" : str(root["message"]))
        }
        let payload = (root["data"] as? [String: Any]) ?? root
        var out = DomainProviderConfigs()
        if let d = payload["cloudflare"] as? [String: Any] {
            out.cloudflare.enabled = bool(d["enabled"])
            out.cloudflare.apiToken = str(d["apiToken"])
            out.cloudflare.email = str(d["email"])
            out.cloudflare.zoneId = str(d["zoneId"])
        }
        if let d = payload["edgeOne"] as? [String: Any] {
            out.edgeOne.enabled = bool(d["enabled"])
            out.edgeOne.secretId = str(d["secretId"])
            out.edgeOne.secretKey = str(d["secretKey"])
            let region = str(d["region"])
            out.edgeOne.region = region.isEmpty ? "ap-beijing" : region
        }
        return out
    }

    static func ensureOK(_ data: Data, fallback: String) throws {
        if data.isEmpty { return }
        if let root = obj(data) {
            if let success = root["success"] as? Bool, !success {
                throw APIError.serverMessage(str(root["message"]).isEmpty ? fallback : str(root["message"]))
            }
            if let ok = root["ok"] as? Bool, !ok {
                throw APIError.serverMessage(str(root["message"]).isEmpty ? fallback : str(root["message"]))
            }
        }
    }

    /// Test connection body: `{ success, message }` (HTTP 200 even on fail).
    static func parseTestResult(_ data: Data, fallbackOK: String) throws -> String {
        if data.isEmpty { return fallbackOK }
        guard let root = obj(data) else { return fallbackOK }
        let msg = str(root["message"])
        if let success = root["success"] as? Bool {
            if !success {
                throw APIError.serverMessage(msg.isEmpty ? "连接测试失败" : msg)
            }
            return msg.isEmpty ? fallbackOK : msg
        }
        if let connected = root["connected"] as? Bool {
            if !connected {
                throw APIError.serverMessage(msg.isEmpty ? "连接测试失败" : msg)
            }
            return msg.isEmpty ? fallbackOK : msg
        }
        return msg.isEmpty ? fallbackOK : msg
    }

    static func obj(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return false
    }
}
