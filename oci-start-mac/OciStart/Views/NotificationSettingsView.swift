import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var selectedTab = 0
    @State private var loading = false
    @State private var configs = NotifyConfigsBundle()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Telegram").tag(0)
                Text("钉钉").tag(1)
                Text("Bark").tag(2)
                Text("飞书").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(16)

            Divider()

            if loading {
                PageLoadingView(message: "加载通知配置…")
            } else {
                ScrollView {
                    Group {
                        switch selectedTab {
                        case 0:
                            TelegramConfigPanel(initial: configs.telegram)
                        case 1:
                            DingTalkConfigPanel(initial: configs.dingTalk)
                        case 2:
                            BarkConfigPanel(initial: configs.bark)
                        default:
                            FeishuConfigPanel(initial: configs.feishu)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("通知管理")
        .onAppear { Task { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            configs = try await appState.network.getNotifyConfigs(baseURL: appState.serverURL)
        } catch {
            // 旧后端无此接口时不阻断；表单保持空
            print("notifyConfigs load failed: \(error)")
        }
    }
}

// MARK: - Telegram

struct TelegramConfigPanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme
    var initial: TelegramNotifyConfig?

    @State private var enabled = false
    @State private var botToken = ""
    @State private var chatId = ""
    @State private var isSaving = false
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用 Telegram 通知", isOn: $enabled)
            ConfigField(label: "Bot Token", placeholder: "输入 Bot Token", text: $botToken)
                .disabled(!enabled)
            ConfigField(label: "Chat ID", placeholder: "输入 Chat ID", text: $chatId)
                .disabled(!enabled)
            HStack(spacing: 12) {
                Button(isSaving ? "保存中…" : "保存配置") { Task { await save() } }
                    .buttonStyle(ProminentButton())
                    .disabled(isSaving || !enabled)
                Button(isTesting ? "测试中…" : "发送测试消息") { Task { await test() } }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || botToken.isEmpty)
            }
        }
        .onAppear { applyInitial() }
        .onChange(of: initial?.botToken) { _ in applyInitial() }
    }

    private func applyInitial() {
        guard let c = initial else { return }
        enabled = c.enabled ?? false
        botToken = c.botToken ?? ""
        chatId = c.chatId ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let r = try await appState.network.updateTelegramConfig(
                baseURL: appState.serverURL, enabled: enabled, botToken: botToken, chatId: chatId)
            appState.showToast(r.message ?? "已保存")
        } catch { appState.errorMessage = error.localizedDescription }
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let r = try await appState.network.testTelegram(baseURL: appState.serverURL)
            appState.showToast(r.message ?? "测试消息已发送")
        } catch { appState.errorMessage = error.localizedDescription }
    }
}

// MARK: - DingTalk

struct DingTalkConfigPanel: View {
    @EnvironmentObject var appState: AppState
    var initial: DingTalkNotifyConfig?

    @State private var enabled = false
    @State private var webhook = ""
    @State private var secret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用钉钉通知", isOn: $enabled)
            ConfigField(label: "Webhook", placeholder: "钉钉机器人 Webhook", text: $webhook)
                .disabled(!enabled)
            ConfigField(label: "加签密钥", placeholder: "Secret（选填）", text: $secret)
                .disabled(!enabled)
            HStack {
                Button("保存配置") { Task { await save() } }
                    .buttonStyle(ProminentButton()).disabled(!enabled)
            }
        }
        .onAppear { applyInitial() }
        .onChange(of: initial?.webhook) { _ in applyInitial() }
    }

    private func applyInitial() {
        guard let c = initial else { return }
        enabled = c.enabled ?? false
        webhook = c.webhook ?? ""
        secret = c.secret ?? ""
    }

    private func save() async {
        do {
            struct Body: Encodable { let enabled: Bool; let webhook: String; let secret: String }
            let url = try appState.network.makeURL("\(appState.serverURL)/api/system/updateDingTalkConfig")
            let r = try await appState.network.postJSONAction(
                url, body: Body(enabled: enabled, webhook: webhook, secret: secret))
            appState.showToast(r.message ?? "已保存")
        } catch { appState.errorMessage = error.localizedDescription }
    }
}

// MARK: - Bark

struct BarkConfigPanel: View {
    @EnvironmentObject var appState: AppState
    var initial: BarkNotifyConfig?

    @State private var enabled = false
    @State private var url = ""
    @State private var deviceKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用 Bark 通知", isOn: $enabled)
            ConfigField(label: "Bark URL", placeholder: "https://api.day.app", text: $url)
                .disabled(!enabled)
            ConfigField(label: "Device Key", placeholder: "设备 Key", text: $deviceKey)
                .disabled(!enabled)
            HStack {
                Button("保存配置") { Task { await save() } }
                    .buttonStyle(ProminentButton()).disabled(!enabled)
            }
        }
        .onAppear { applyInitial() }
        .onChange(of: initial?.deviceKey) { _ in applyInitial() }
    }

    private func applyInitial() {
        guard let c = initial else { return }
        enabled = c.enabled ?? false
        url = c.url ?? ""
        deviceKey = c.deviceKey ?? ""
    }

    private func save() async {
        do {
            struct Body: Encodable { let enabled: Bool; let url: String; let deviceKey: String }
            let endpoint = try appState.network.makeURL("\(appState.serverURL)/api/system/updateBarkConfig")
            let r = try await appState.network.postJSONAction(
                endpoint, body: Body(enabled: enabled, url: url, deviceKey: deviceKey))
            appState.showToast(r.message ?? "已保存")
        } catch { appState.errorMessage = error.localizedDescription }
    }
}

// MARK: - Feishu

struct FeishuConfigPanel: View {
    @EnvironmentObject var appState: AppState
    var initial: FeishuNotifyConfig?

    @State private var enabled = false
    @State private var webhook = ""
    @State private var secret = ""
    @State private var isSaving = false
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用飞书通知", isOn: $enabled)
            ConfigField(label: "Webhook 地址", placeholder: "Webhook URL", text: $webhook)
                .disabled(!enabled)
            ConfigField(label: "签名密钥", placeholder: "Secret（选填）", text: $secret)
                .disabled(!enabled)
            HStack(spacing: 12) {
                Button(isSaving ? "保存中…" : "保存配置") { Task { await save() } }
                    .buttonStyle(ProminentButton())
                    .disabled(isSaving || !enabled)
                Button(isTesting ? "测试中…" : "发送测试消息") { Task { await test() } }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || webhook.isEmpty)
            }
        }
        .onAppear { applyInitial() }
        .onChange(of: initial?.webhook) { _ in applyInitial() }
    }

    private func applyInitial() {
        guard let c = initial else { return }
        enabled = c.enabled ?? false
        webhook = c.webhook ?? ""
        secret = c.secret ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            struct Body: Encodable { let enabled: Bool; let webhook: String; let secret: String }
            let url = try appState.network.makeURL("\(appState.serverURL)/api/system/updateFeishuConfig")
            let r = try await appState.network.postJSONAction(
                url, body: Body(enabled: enabled, webhook: webhook, secret: secret))
            appState.showToast(r.message ?? "已保存")
        } catch { appState.errorMessage = error.localizedDescription }
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let url = try appState.network.makeURL("\(appState.serverURL)/api/system/testFeishu")
            let _: ActionResponse = try await appState.network.post(url, body: [:])
            appState.showToast("测试消息已发送")
        } catch { appState.errorMessage = error.localizedDescription }
    }
}

// MARK: - Shared

struct ConfigField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundColor(AppTheme.muted(scheme))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
