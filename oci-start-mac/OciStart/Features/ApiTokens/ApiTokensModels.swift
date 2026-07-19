import Foundation

struct ApiTokenForm: Equatable {
    var tokenName = ""
    var expirationDays = 30
    var description = ""
    var allowSwaggerAccess = true
}

struct ApiTokenStatus: Equatable {
    var enabled = false
    var tokenName = ""
    var hasToken = false
    var description = ""
    var tokenValue = ""
    var expirationDays = 30
    var expiresAt = ""
    var createdAt = ""
    var daysUntilExpiration = 0
    var isExpired = false
}

struct ApiTokenGenerateResult: Equatable {
    var tokenValue = ""
    var expiresAt = ""
    var daysUntilExpiration = 0
    var tokenName = ""
}

enum ApiTokensJSON {
    static func parseConfigs(_ data: Data) throws -> (form: ApiTokenForm, status: ApiTokenStatus) {
        guard let root = obj(data) else {
            throw APIError.serverMessage("Token 配置解析失败")
        }
        if let success = root["success"] as? Bool, success == false {
            throw APIError.serverMessage(str(root["message"]).isEmpty ? "加载 Token 配置失败" : str(root["message"]))
        }
        let payload = (root["data"] as? [String: Any]) ?? root
        var form = ApiTokenForm()
        var status = ApiTokenStatus()

        if let c = payload["config"] as? [String: Any] {
            form.tokenName = str(c["tokenName"])
            form.expirationDays = int(c["expirationDays"], fallback: 30)
            if ![7, 30, 90, 180, 365].contains(form.expirationDays) {
                form.expirationDays = 30
            }
            form.description = str(c["description"])
            form.allowSwaggerAccess = bool(c["allowSwaggerAccess"], fallback: true)
            status.tokenValue = str(c["tokenValue"])
            status.expirationDays = form.expirationDays
        }

        if let s = payload["status"] as? [String: Any] {
            status.enabled = bool(s["enabled"])
            status.tokenName = str(s["tokenName"])
            status.hasToken = bool(s["hasToken"])
            status.description = str(s["description"])
            status.expiresAt = formatTime(s["expiresAt"])
            status.createdAt = formatTime(s["createdAt"])
            status.daysUntilExpiration = int(s["daysUntilExpiration"])
            status.isExpired = bool(s["isExpired"])
            if form.tokenName.isEmpty {
                form.tokenName = status.tokenName
            }
            if form.description.isEmpty {
                form.description = status.description
            }
        }

        return (form, status)
    }

    static func parseGenerate(_ data: Data) throws -> ApiTokenGenerateResult {
        guard let root = obj(data) else {
            throw APIError.serverMessage("生成 Token 响应解析失败")
        }
        // 可能直接是 ApiTokenResponse，或包在 data 里
        let d = (root["data"] as? [String: Any]) ?? root
        var r = ApiTokenGenerateResult()
        r.tokenValue = str(d["tokenValue"])
        r.tokenName = str(d["tokenName"])
        r.expiresAt = formatTime(d["expiresAt"])
        r.daysUntilExpiration = int(d["daysUntilExpiration"])
        if r.tokenValue.isEmpty {
            throw APIError.serverMessage(str(root["message"]).isEmpty ? "生成 Token 失败" : str(root["message"]))
        }
        return r
    }

    static func ensureOK(_ data: Data, fallback: String) throws {
        if data.isEmpty { return }
        if let root = obj(data) {
            if let success = root["success"] as? Bool, !success {
                throw APIError.serverMessage(str(root["message"]).isEmpty ? fallback : str(root["message"]))
            }
        }
    }

    static func formatTime(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let arr = v as? [Any] {
            // LocalDateTime array [y,m,d,h,mi,s]
            let nums = arr.compactMap { ($0 as? NSNumber)?.intValue ?? Int("\($0)") }
            if nums.count >= 3 {
                let y = nums[0], m = nums[1], d = nums[2]
                let h = nums.count > 3 ? nums[3] : 0
                let mi = nums.count > 4 ? nums[4] : 0
                let s = nums.count > 5 ? nums[5] : 0
                return String(format: "%04d-%02d-%02d %02d:%02d:%02d", y, m, d, h, mi, s)
            }
        }
        return str(v)
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
}
