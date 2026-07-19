import Foundation

/// Network layer for Web `/system/notifySettings` · `/api/system/notifyConfigs`.
struct NotifyService {
    let baseURL: String
    private let client = APIClient.shared

    func fetchConfigs() async throws -> NotifyConfigs {
        let url = try client.makeURL(baseURL, path: "/api/system/notifyConfigs")
        let raw = try await client.getJSON(url)
        return try NotifyJSON.parseConfigs(raw)
    }

    func updateTask(_ form: NotifyTaskForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateTaskConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "executeHour": form.executeHour,
            // 通知密钥已废弃，保存时固定清空
            "notificationSecret": "",
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
            "botToken": form.botToken,
            "chatId": form.chatId,
            "chatName": form.chatName
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
            "host": form.host,
            "port": form.port,
            "username": form.username,
            "password": form.password
        ])
        try NotifyJSON.ensureOK(raw, fallback: "保存 Telegram 代理失败")
    }

    func testProxy(_ form: NotifyProxyForm) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/system/testProxyConnection")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "type": form.type,
            "host": form.host,
            "port": form.port,
            "username": form.username,
            "password": form.password
        ])
        return try NotifyJSON.parseProxyTest(raw)
    }

    func updateBark(_ form: NotifyBarkForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateBarkConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "url": form.url,
            "deviceKey": form.deviceKey
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
            "webhook": form.webhook,
            "secret": form.secret
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
            "webhook": form.webhook,
            "secret": form.secret
        ])
        try NotifyJSON.ensureOK(raw, fallback: "保存飞书配置失败")
    }

    func testFeishu() async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/testFeishu")
        let raw = try await client.postJSON(url, body: [:])
        try NotifyJSON.ensureOK(raw, fallback: "飞书测试发送失败")
    }
}
