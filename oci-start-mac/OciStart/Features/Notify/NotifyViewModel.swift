import Foundation
import Combine

@MainActor
final class NotifyViewModel: ObservableObject {
    @Published var task = NotifyTaskForm()
    @Published var telegram = NotifyTelegramForm()
    @Published var proxy = NotifyProxyForm()
    @Published var bark = NotifyBarkForm()
    @Published var dingTalk = NotifyWebhookForm()
    @Published var feishu = NotifyWebhookForm()
    @Published private(set) var serverTimeZone = ""
    @Published private(set) var isLoading = false
    @Published private(set) var savingKey: String?
    @Published private(set) var errorText: String?
    @Published private(set) var notice: String?
    @Published private(set) var loaded = false
    @Published private(set) var loadFailed = false
    @Published private(set) var requiresReview = false
    private let session: AppSession
    private var service: NotifyService { NotifyService(baseURL: session.serverURL) }
    private var baseline: NotifyConfigs?
    private var generation = 0
    private var active = false
    var canMutate: Bool { loaded && !loadFailed && !isLoading && savingKey == nil && !requiresReview }
    var hourOptions: [SelectOption] { (0...23).map { SelectOption(id: "\($0)", title: String(format: "%02d:00", $0)) } }
    var proxyTypeOptions: [SelectOption] { ["HTTP", "SOCKS5"].map { SelectOption(id: $0, title: $0) } }

    init(session: AppSession = .shared) { self.session = session }
    func start() { active = true; Task { @MainActor in await reload() } }
    func stop() { active = false; generation += 1; clearSecrets() }
    var hasUnsavedChanges: Bool {
        guard let saved = baseline else { return false }
        return task != saved.task || telegram != saved.telegram || proxy != saved.proxy || bark != saved.bark
            || dingTalk != saved.dingTalk || feishu != saved.feishu
    }
    func canLeave() -> Bool {
        guard savingKey == nil else { AppAlert.info(title: "请求正在提交", message: "请等待当前操作完成。"); return false }
        guard hasUnsavedChanges || requiresReview else { return true }
        return AppAlert.confirm(title: "离开通知设置", message: requiresReview
            ? "操作结果尚未确认。离开后请核对配置及消息接收端的实际结果，避免重复发送。"
            : "存在未保存的修改，离开将丢弃这些修改。", confirmTitle: "离开", cancelTitle: "继续编辑")
    }
    func requestReload() { if canLeave() { Task { @MainActor in await reload() } } }
    func reload() async {
        guard savingKey == nil else { return }
        generation += 1
        let current = generation
        isLoading = true
        defer { if generation == current { isLoading = false } }
        do {
            let saved = try await service.fetchConfigs()
            guard active, current == generation else { return }
            task = saved.task; telegram = saved.telegram; proxy = saved.proxy; bark = saved.bark
            dingTalk = saved.dingTalk; feishu = saved.feishu; serverTimeZone = saved.serverTimeZone
            baseline = saved; loaded = true; loadFailed = false; requiresReview = false; errorText = nil
        } catch {
            if active, current == generation {
                loadFailed = true
                errorText = "通知配置读取未完成，请确认服务端已更新后重试。"
            }
        }
    }
    private func clearSecrets() {
        task.notificationSecret = ""; telegram.botToken = ""; proxy.password = ""; bark.deviceKey = ""
        dingTalk.webhook = ""; dingTalk.secret = ""; feishu.webhook = ""; feishu.secret = ""
    }
    private func validation(_ work: () throws -> Void) -> Bool {
        guard canMutate else { return false }
        do { try work(); return true }
        catch { errorText = error.localizedDescription; return false }
    }
    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw APIError.serverMessage(message) }
    }
    private func validURL(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme ?? ""), url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else { return false }
        return value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !value.contains("\\")
    }
    private func validateProxy(_ value: NotifyProxyForm, testing: Bool = false) throws {
        try require(["HTTP", "SOCKS5"].contains(value.type), "代理类型应为 HTTP 或 SOCKS5。")
        try require((1...65535).contains(value.port), "端口范围应为 1–65535。")
        try require((!value.enabled && !testing) || !value.host.isEmpty, "请输入代理主机。")
        try require(value.host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && !value.host.contains("://") && !value.host.contains(where: { "/?#@\\".contains($0) }), "代理主机不能包含协议、路径或空格。")
        if !testing { try value.secretMode.validate(value.password, hasSaved: value.hasPassword, required: false) }
    }
    private func validateWebhook(_ value: NotifyWebhookForm, ding: Bool) throws {
        try value.webhookMode.validate(value.webhook, hasSaved: value.hasWebhook, required: value.enabled)
        try value.secretMode.validate(value.secret, hasSaved: value.hasSecret, required: ding && value.enabled)
        let url = value.webhookMode.payload(value.webhook).trimmingCharacters(in: .whitespacesAndNewlines)
        try require(validURL(url), "请输入有效 HTTP(S) Webhook 地址。")
        if ding, !url.isEmpty {
            let parsed = URL(string: url)
            try require(parsed?.scheme == "https" && parsed?.host == "oapi.dingtalk.com" && parsed?.path == "/robot/send", "请输入钉钉官方机器人 Webhook 地址。")
        }
    }

    func saveTask() {
        guard validation({
            try require((0...23).contains(task.executeHour), "执行小时应为 0–23。")
            try task.secretMode.validate(task.notificationSecret, hasSaved: task.hasNotificationSecret, required: false)
        }) else { return }
        let value = task
        save("task", clears: value.secretMode == .clear) { try await self.service.updateTask(value) }
    }
    func saveTelegram() {
        telegram.chatId = telegram.chatId.trimmingCharacters(in: .whitespacesAndNewlines)
        telegram.chatName = telegram.chatName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validation({
            try telegram.secretMode.validate(telegram.botToken, hasSaved: telegram.hasBotToken, required: telegram.enabled)
            try require(!telegram.enabled || !telegram.chatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "启用 Telegram 时需要 Chat ID。")
        }) else { return }
        let value = telegram
        save("telegram", clears: value.secretMode == .clear) { try await self.service.updateTelegram(value) }
    }
    func saveProxy() {
        proxy.host = proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        proxy.username = proxy.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validation({ try validateProxy(proxy) }) else { return }
        let value = proxy
        save("proxy", clears: value.secretMode == .clear) { try await self.service.updateProxy(value) }
    }
    func saveBark() {
        bark.url = bark.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validation({
            try bark.secretMode.validate(bark.deviceKey, hasSaved: bark.hasDeviceKey, required: bark.enabled)
            try require(validURL(bark.url) && (!bark.enabled || !bark.url.isEmpty), "请输入有效 Bark 服务 URL。")
        }) else { return }
        let value = bark
        save("bark", clears: value.secretMode == .clear) { try await self.service.updateBark(value) }
    }
    func saveDingTalk() {
        guard validation({ try validateWebhook(dingTalk, ding: true) }) else { return }
        let value = dingTalk
        save("dingTalk", clears: value.webhookMode == .clear || value.secretMode == .clear) { try await self.service.updateDingTalk(value) }
    }
    func saveFeishu() {
        guard validation({ try validateWebhook(feishu, ding: false) }) else { return }
        let value = feishu
        save("feishu", clears: value.webhookMode == .clear || value.secretMode == .clear) { try await self.service.updateFeishu(value) }
    }
    private func save(_ key: String, clears: Bool, _ work: @escaping () async throws -> Void) {
        guard AppAlert.confirm(title: "保存通知配置", message: "保存当前分区的设置。" + (clears ? "已选择的密钥将从服务器清除。" : "")) else { return }
        perform(key, saving: true, success: "保存请求已完成，请核对重新读取的配置。", work)
    }
    func testTelegram() { test("telegram", ready: baseline?.telegram.hasBotToken == true && !(baseline?.telegram.chatId.isEmpty ?? true)) { try await self.service.testTelegram() } }
    func testBark() { test("bark", ready: baseline?.bark.hasDeviceKey == true && !(baseline?.bark.url.isEmpty ?? true)) { try await self.service.testBark() } }
    func testDingTalk() { test("dingTalk", ready: baseline?.dingTalk.hasWebhook == true && baseline?.dingTalk.hasSecret == true) { try await self.service.testDingTalk() } }
    func testFeishu() { test("feishu", ready: baseline?.feishu.hasWebhook == true) { try await self.service.testFeishu() } }
    private func test(_ key: String, ready: Bool, _ work: @escaping () async throws -> Void) {
        guard canMutate else { return }
        guard !hasUnsavedChanges, ready else { errorText = "请先保存完整配置，再发送测试消息。"; return }
        guard AppAlert.confirm(title: "发送测试消息", message: "服务器将使用已保存的 \(key) 配置真实发送一条消息，停用的渠道也会发送。请在接收端确认结果。", confirmTitle: "发送") else { return }
        perform(key + "Test", saving: false, success: "测试发送请求已完成，请在接收端确认消息；当前渠道启用状态未改变。", work)
    }
    func testProxy() {
        guard validation({ try validateProxy(proxy, testing: true) }),
              AppAlert.confirm(title: "检测代理端口", message: "服务器将连接 \(proxy.host):\(proxy.port) 检查 TCP 端口可用性，不验证代理认证，也不会保存配置。") else { return }
        let value = proxy
        savingKey = "proxyTest"
        Task { @MainActor in
            do { notice = try await service.testProxy(value); errorText = nil }
            catch { errorText = "端口检测未完成，请重试。" }
            savingKey = nil
        }
    }
    func startBot() {
        guard canMutate, !hasUnsavedChanges, baseline?.telegram.enabled == true, baseline?.telegram.hasBotToken == true,
              !(baseline?.telegram.chatId.isEmpty ?? true), AppAlert.confirm(title: "重新注册 Telegram 机器人", message: "使用已保存的 Telegram 和代理配置重新注册机器人会话。请在 Telegram 中检查实际可用性。") else { return }
        perform("bot", saving: false, success: "重新注册请求已完成，请在 Telegram 中确认机器人可用。") { try await self.service.startBot() }
    }
    private func perform(_ key: String, saving: Bool, success: String, _ work: @escaping () async throws -> Void) {
        guard canMutate else { return }
        savingKey = key; errorText = nil; notice = nil
        Task { @MainActor in
            do {
                try await work()
                clearSecrets(); savingKey = nil
                guard active else { return }
                if saving { requiresReview = true; await reload() }
                notice = success
            } catch {
                clearSecrets(); savingKey = nil
                guard active else { return }
                requiresReview = true
                errorText = "操作结果未确认。请核对服务器配置或消息接收端的实际结果，再重新读取配置后继续。"
            }
        }
    }
}
