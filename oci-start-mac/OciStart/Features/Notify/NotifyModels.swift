import Foundation

// MARK: - Forms (align `/api/system/notifyConfigs`)

struct NotifyTaskForm: Equatable {
    var enabled = false
    var executeHour = 9
    var notificationSecret = ""
    var enableAccountCheck = false
    var enableBootLog = false
    var enableCostCheck = false
}

struct NotifyTelegramForm: Equatable {
    var enabled = false
    var botToken = ""
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
}

struct NotifyBarkForm: Equatable {
    var enabled = false
    var url = ""
    var deviceKey = ""
}

struct NotifyWebhookForm: Equatable {
    var enabled = false
    var webhook = ""
    var secret = ""
}

struct NotifyConfigs: Equatable {
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
        let payload = (root["data"] as? [String: Any]) ?? root
        var out = NotifyConfigs()
        if let d = payload["task"] as? [String: Any] {
            out.task.enabled = bool(d["enabled"])
            out.task.executeHour = max(0, min(23, int(d["executeHour"], fallback: 9)))
            out.task.notificationSecret = str(d["notificationSecret"])
            out.task.enableAccountCheck = bool(d["enableAccountCheck"])
            out.task.enableBootLog = bool(d["enableBootLog"])
            out.task.enableCostCheck = bool(d["enableCostCheck"])
        }
        if let d = payload["telegram"] as? [String: Any] {
            out.telegram.enabled = bool(d["enabled"])
            out.telegram.botToken = str(d["botToken"])
            out.telegram.chatId = str(d["chatId"])
            out.telegram.chatName = str(d["chatName"])
        }
        if let d = payload["proxy"] as? [String: Any] {
            out.proxy.enabled = bool(d["enabled"])
            let t = str(d["type"]).uppercased()
            out.proxy.type = t.isEmpty ? "HTTP" : t
            out.proxy.host = str(d["host"]).isEmpty ? "127.0.0.1" : str(d["host"])
            out.proxy.port = int(d["port"], fallback: 7890)
            out.proxy.username = str(d["username"])
            out.proxy.password = str(d["password"])
        }
        if let d = payload["bark"] as? [String: Any] {
            out.bark.enabled = bool(d["enabled"])
            out.bark.url = str(d["url"])
            out.bark.deviceKey = str(d["deviceKey"])
        }
        if let d = payload["dingTalk"] as? [String: Any] {
            out.dingTalk.enabled = bool(d["enabled"])
            out.dingTalk.webhook = str(d["webhook"])
            out.dingTalk.secret = str(d["secret"])
        }
        if let d = payload["feishu"] as? [String: Any] {
            out.feishu.enabled = bool(d["enabled"])
            out.feishu.webhook = str(d["webhook"])
            out.feishu.secret = str(d["secret"])
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

    static func parseProxyTest(_ data: Data) throws -> String {
        guard let root = obj(data) else { return "测试完成" }
        let success = bool(root["success"])
        let msg = str(root["message"]).isEmpty
            ? (success ? "代理连接测试成功" : "代理连接测试失败")
            : str(root["message"])
        if !success { throw APIError.serverMessage(msg) }
        return msg
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
