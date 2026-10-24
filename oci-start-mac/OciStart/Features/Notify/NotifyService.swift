import Foundation

/// Network layer for Web `/system/notifySettings` · `/api/system/notifyConfigs`.
struct NotifyService {
    let baseURL: String
    private let client = APIClient.shared

    func fetchConfigs() async throws -> NotifyConfigs {
        let url = try client.makeURL(baseURL, path: "/api/system/notifyConfigs", query: ["redacted": "true"])
        let raw = try await client.getJSON(url)
        return try NotifyJSON.parseConfigs(raw)
    }

    func updateTask(_ form: NotifyTaskForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateTaskConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "executeHour": form.executeHour,
            "notificationSecret": form.secretMode.payload(form.notificationSecret).trimmingCharacters(in: .whitespacesAndNewlines),
            "keepNotificationSecret": form.secretMode == .keep,
            "clearNotificationSecret": form.secretMode == .clear,
            "enableAccountCheck": form.enableAccountCheck,
            "enableBootLog": form.enableBootLog,
            "enableCostCheck": form.enableCostCheck
        ])
        try NotifyJSON.ensureOK(raw, fallback: "保存定时任务失败")
    }

    func updateTelegram(_ form: NotifyTelegramForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateTelegramConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "keepBotToken": form.secretMode == .keep,
            "botToken": form.secretMode.payload(form.botToken),
            "chatId": form.chatId.trimmingCharacters(in: .whitespacesAndNewlines),
            "chatName": form.chatName.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        try NotifyJSON.ensureOK(raw, fallback: "保存 Telegram 配置失败")
    }

    func testTelegram() async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/testTgTalk")
        let raw = try await client.postJSON(url, body: [:])
        try NotifyJSON.ensureOK(raw, fallback: "Telegram 测试发送失败")
    }

    func updateProxy(_ form: NotifyProxyForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateProxyConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "type": form.type,
            "host": form.host.trimmingCharacters(in: .whitespacesAndNewlines),
            "port": form.port,
            "username": form.username.trimmingCharacters(in: .whitespacesAndNewlines),
            "keepPassword": form.secretMode == .keep,
            "password": form.secretMode.payload(form.password)
        ])
        try NotifyJSON.ensureOK(raw, fallback: "保存 Telegram 代理失败")
    }

    func testProxy(_ form: NotifyProxyForm) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/system/testProxyConnection")
        let raw = try await client.postJSON(url, body: ["type": form.type, "host": form.host.trimmingCharacters(in: .whitespacesAndNewlines), "port": form.port])
        return try NotifyJSON.parseProxyTest(raw)
    }

    func startBot() async throws {
        let url = try client.makeURL(baseURL, path: "/system/startTgRobot")
        let raw = try await client.postJSON(url, body: nil)
        try NotifyJSON.ensureOK(raw, fallback: "机器人重新注册结果未确认")
    }

    func updateBark(_ form: NotifyBarkForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateBarkConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "url": form.url.trimmingCharacters(in: .whitespacesAndNewlines),
            "keepDeviceKey": form.secretMode == .keep,
            "deviceKey": form.secretMode.payload(form.deviceKey)
        ])
        try NotifyJSON.ensureOK(raw, fallback: "保存 Bark 配置失败")
    }

    func testBark() async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/testBark")
        let raw = try await client.postJSON(url, body: [:])
        try NotifyJSON.ensureOK(raw, fallback: "Bark 测试发送失败")
    }

    func updateDingTalk(_ form: NotifyWebhookForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateDingTalkConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "keepWebhook": form.webhookMode == .keep,
            "webhook": form.webhookMode.payload(form.webhook).trimmingCharacters(in: .whitespacesAndNewlines),
            "keepSecret": form.secretMode == .keep,
            "secret": form.secretMode.payload(form.secret)
        ])
        try NotifyJSON.ensureOK(raw, fallback: "保存钉钉配置失败")
    }

    func testDingTalk() async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/testDingTalk")
        let raw = try await client.postJSON(url, body: [:])
        try NotifyJSON.ensureOK(raw, fallback: "钉钉测试发送失败")
    }

    func updateFeishu(_ form: NotifyWebhookForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateFeishuConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "keepWebhook": form.webhookMode == .keep,
            "webhook": form.webhookMode.payload(form.webhook).trimmingCharacters(in: .whitespacesAndNewlines),
            "keepSecret": form.secretMode == .keep,
            "secret": form.secretMode.payload(form.secret)
        ])
        try NotifyJSON.ensureOK(raw, fallback: "保存飞书配置失败")
    }

    func testFeishu() async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/testFeishu")
        let raw = try await client.postJSON(url, body: [:])
        try NotifyJSON.ensureOK(raw, fallback: "飞书测试发送失败")
    }
}
