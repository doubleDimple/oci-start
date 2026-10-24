import Foundation

// MARK: - Forms (align `/api/system/notifyConfigs`)

struct NotifyTaskForm: Equatable {
    var enabled = false
    var executeHour = 9
    var notificationSecret = ""
    var hasNotificationSecret = false
    var secretMode: NativeSecretMode = .replace
    var enableAccountCheck = false
    var enableBootLog = false
    var enableCostCheck = false
}

struct NotifyTelegramForm: Equatable {
    var enabled = false
    var botToken = ""
    var hasBotToken = false
    var secretMode: NativeSecretMode = .replace
    var chatId = ""
    var chatName = ""
}

struct NotifyProxyForm: Equatable {
    var enabled = false
    var type = "HTTP"
    var host = "127.0.0.1"
    var port = 7890
    var username = ""
    var password = ""
    var hasPassword = false
    var secretMode: NativeSecretMode = .replace
}

struct NotifyBarkForm: Equatable {
    var enabled = false
    var url = ""
    var deviceKey = ""
    var hasDeviceKey = false
    var secretMode: NativeSecretMode = .replace
}

struct NotifyWebhookForm: Equatable {
    var enabled = false
    var webhook = ""
    var hasWebhook = false
    var webhookMode: NativeSecretMode = .replace
    var secret = ""
    var hasSecret = false
    var secretMode: NativeSecretMode = .replace
}

struct NotifyConfigs: Equatable {
    var serverTimeZone = ""
    var task = NotifyTaskForm()
    var telegram = NotifyTelegramForm()
    var proxy = NotifyProxyForm()
    var bark = NotifyBarkForm()
    var dingTalk = NotifyWebhookForm()
    var feishu = NotifyWebhookForm()
}

enum NotifyJSON {
    static func parseConfigs(_ data: Data) throws -> NotifyConfigs {
        guard let root = obj(data) else {
            throw APIError.serverMessage("通知配置解析失败")
        }
        if let success = root["success"] as? Bool, success == false {
            throw APIError.serverMessage(str(root["message"]).isEmpty ? "加载通知配置失败" : str(root["message"]))
        }
        guard root["success"] as? Bool == true, let payload = root["data"] as? [String: Any],
              ["task", "telegram", "proxy", "bark", "dingTalk", "feishu"].allSatisfy({ payload[$0] is [String: Any] }),
              let timeZone = payload["serverTimeZone"] as? String, !timeZone.isEmpty else { throw APIError.invalidResponse }
        var out = NotifyConfigs()
        out.serverTimeZone = timeZone
        if let d = payload["task"] as? [String: Any] {
            guard let enabled = d["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.task.enabled = enabled
            guard let hour = d["executeHour"] as? Int, (0...23).contains(hour) else { throw APIError.invalidResponse }
            out.task.executeHour = hour
            guard let hasNotificationSecret = d["hasNotificationSecret"] as? Bool else { throw APIError.invalidResponse }
            out.task.hasNotificationSecret = hasNotificationSecret
            out.task.secretMode = hasNotificationSecret ? .keep : .replace
            guard let enableAccountCheck = d["enableAccountCheck"] as? Bool else { throw APIError.invalidResponse }
            out.task.enableAccountCheck = enableAccountCheck
            guard let enableBootLog = d["enableBootLog"] as? Bool else { throw APIError.invalidResponse }
            out.task.enableBootLog = enableBootLog
            guard let enableCostCheck = d["enableCostCheck"] as? Bool else { throw APIError.invalidResponse }
            out.task.enableCostCheck = enableCostCheck
        }
        if let d = payload["telegram"] as? [String: Any] {
            guard let enabled = d["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.telegram.enabled = enabled
            guard let hasBotToken = d["hasBotToken"] as? Bool else { throw APIError.invalidResponse }
            out.telegram.hasBotToken = hasBotToken
            out.telegram.secretMode = hasBotToken ? .keep : .replace
            out.telegram.chatId = str(d["chatId"])
            out.telegram.chatName = str(d["chatName"])
        }
        if let d = payload["proxy"] as? [String: Any] {
            guard let enabled = d["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.proxy.enabled = enabled
            let t = str(d["type"]).uppercased()
            out.proxy.type = t.isEmpty ? "HTTP" : t
            out.proxy.host = str(d["host"])
            guard let port = d["port"] as? Int, (1...65535).contains(port) else { throw APIError.invalidResponse }
            out.proxy.port = port
            out.proxy.username = str(d["username"])
            guard let hasPassword = d["hasPassword"] as? Bool else { throw APIError.invalidResponse }
            out.proxy.hasPassword = hasPassword
            out.proxy.secretMode = hasPassword ? .keep : .replace
        }
        if let d = payload["bark"] as? [String: Any] {
            guard let enabled = d["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.bark.enabled = enabled
            out.bark.url = str(d["url"])
            guard let hasDeviceKey = d["hasDeviceKey"] as? Bool else { throw APIError.invalidResponse }
            out.bark.hasDeviceKey = hasDeviceKey
            out.bark.secretMode = hasDeviceKey ? .keep : .replace
        }
        if let d = payload["dingTalk"] as? [String: Any] {
            guard let enabled = d["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.dingTalk.enabled = enabled
            guard let hasWebhook = d["hasWebhook"] as? Bool else { throw APIError.invalidResponse }
            out.dingTalk.hasWebhook = hasWebhook
            out.dingTalk.webhookMode = hasWebhook ? .keep : .replace
            guard let hasSecret = d["hasSecret"] as? Bool else { throw APIError.invalidResponse }
            out.dingTalk.hasSecret = hasSecret
            out.dingTalk.secretMode = hasSecret ? .keep : .replace
        }
        if let d = payload["feishu"] as? [String: Any] {
            guard let enabled = d["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.feishu.enabled = enabled
            guard let hasWebhook = d["hasWebhook"] as? Bool else { throw APIError.invalidResponse }
            out.feishu.hasWebhook = hasWebhook
            out.feishu.webhookMode = hasWebhook ? .keep : .replace
            guard let hasSecret = d["hasSecret"] as? Bool else { throw APIError.invalidResponse }
            out.feishu.hasSecret = hasSecret
            out.feishu.secretMode = hasSecret ? .keep : .replace
        }
        return out
    }

    static func ensureOK(_ data: Data, fallback: String) throws {
        guard String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true else {
            throw APIError.serverMessage(fallback)
        }
    }

    static func parseProxyTest(_ data: Data) throws -> String {
        guard let root = obj(data), let connected = root["success"] as? Bool else { throw APIError.invalidResponse }
        return connected ? "服务器到目标端口可连接。" : "服务器到目标端口未连通。"
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

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return false
    }
}
