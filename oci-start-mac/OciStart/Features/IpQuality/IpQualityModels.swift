import Foundation

// MARK: - DTOs (align `/api/system/ipSettingsConfigs`)

struct IpCheckConfigDTO: Equatable {
    var enabled: Bool = false
    var checkInterval: Int = 1
}

struct VPSConfigDTO: Equatable {
    var type: String = ""
    var enabled: Bool = false
    var serverIp: String = ""
    var username: String = "root"
    var password: String = ""
    var sshPort: Int = 22
}

struct IpQualityConfigs: Equatable {
    var ipCheck: IpCheckConfigDTO = IpCheckConfigDTO()
    var telecom: VPSConfigDTO = VPSConfigDTO(type: "telecom")
    var unicom: VPSConfigDTO = VPSConfigDTO(type: "unicom")
    var mobile: VPSConfigDTO = VPSConfigDTO(type: "mobile")
}

enum IpCarrier: String, CaseIterable, Identifiable {
    case telecom
    case unicom
    case mobile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .telecom: return "电信 VPS"
        case .unicom: return "联通 VPS"
        case .mobile: return "移动 VPS"
        }
    }

    var subtitle: String {
        switch self {
        case .telecom: return "China Telecom · SSH 探测节点"
        case .unicom: return "China Unicom · SSH 探测节点"
        case .mobile: return "China Mobile · SSH 探测节点"
        }
    }

    var systemImage: String {
        switch self {
        case .telecom: return "antenna.radiowaves.left.and.right"
        case .unicom: return "network"
        case .mobile: return "iphone.radiowaves.left.and.right"
        }
    }
}

enum IpQualityJSON {
    static func parseConfigs(_ data: Data) throws -> IpQualityConfigs {
        guard let root = obj(data) else {
            throw APIError.serverMessage("配置解析失败")
        }
        let payload = (root["data"] as? [String: Any]) ?? root
        if let success = root["success"] as? Bool, success == false {
            throw APIError.serverMessage((root["message"] as? String) ?? "加载配置失败")
        }
        var out = IpQualityConfigs()
        if let d = payload["ipCheck"] as? [String: Any] {
            out.ipCheck.enabled = bool(d["enabled"])
            out.ipCheck.checkInterval = max(1, min(24, int(d["checkInterval"], fallback: 1)))
        }
        out.telecom = parseVPS(payload["telecom"] as? [String: Any], type: "telecom")
        out.unicom = parseVPS(payload["unicom"] as? [String: Any], type: "unicom")
        out.mobile = parseVPS(payload["mobile"] as? [String: Any], type: "mobile")
        return out
    }

    static func parseVPS(_ d: [String: Any]?, type: String) -> VPSConfigDTO {
        var v = VPSConfigDTO(type: type)
        guard let d = d else { return v }
        v.enabled = bool(d["enabled"])
        v.serverIp = str(d["serverIp"])
        v.username = str(d["username"]).isEmpty ? "root" : str(d["username"])
        v.password = str(d["password"])
        v.sshPort = int(d["sshPort"], fallback: 22)
        if v.sshPort <= 0 { v.sshPort = 22 }
        return v
    }

    static func ensureOK(_ data: Data, fallback: String) throws {
        if data.isEmpty { return }
        if let root = obj(data) {
            if let success = root["success"] as? Bool {
                if !success {
                    throw APIError.serverMessage((root["message"] as? String) ?? fallback)
                }
                return
            }
            if let ok = root["ok"] as? Bool, !ok {
                throw APIError.serverMessage((root["message"] as? String) ?? fallback)
            }
        }
    }

    static func parseTestResult(_ data: Data) throws -> String {
        if data.isEmpty { return "连接成功" }
        guard let root = obj(data) else { return "连接成功" }
        if let success = root["success"] as? Bool {
            let msg = str(root["message"]).isEmpty
                ? (success ? "SSH 连接成功" : "SSH 连接失败")
                : str(root["message"])
            if !success { throw APIError.serverMessage(msg) }
            return msg
        }
        return "连接成功"
    }

    // MARK: helpers

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

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return false
    }
}
