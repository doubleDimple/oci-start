import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            Picker("", selection: $selectedTab) {
                Text("Telegram").tag(0)
                Text("钉钉").tag(1)
                Text("Bark").tag(2)
                Text("飞书").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(16)

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: TelegramConfigPanel()
                    case 1: DingTalkConfigPanel()
                    case 2: BarkConfigPanel()
                    default: FeishuConfigPanel()
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("通知设置")
    }
}

// MARK: - Telegram

struct TelegramConfigPanel: View {
    @EnvironmentObject var appState: AppState
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
                Button(isSaving ? "保存中…" : "保存配置") {
                    Task { await save() }
                }
                .buttonStyle(ProminentButton())
                .disabled(isSaving || !enabled)

                Button(isTesting ? "测试中…" : "发送测试消息") {
                    Task { await test() }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || botToken.isEmpty)
            }
        }
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
    @State private var enabled = false
    @State private var accessToken = ""
    @State private var secret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用钉钉通知", isOn: $enabled)
            ConfigField(label: "Webhook Token", placeholder: "输入 Access Token", text: $accessToken)
                .disabled(!enabled)
            ConfigField(label: "加签密钥", placeholder: "输入 Secret（选填）", text: $secret)
                .disabled(!enabled)
            HStack {
                Button("保存配置") {
                    Task { await save() }
                }
                .buttonStyle(ProminentButton()).disabled(!enabled)
            }
        }
    }

    private func save() async {
        do {
            let url = try appState.network.makeURL("\(appState.serverURL)/api/system/updateDingTalkConfig")
            let r: ActionResponse = try await appState.network.post(url, body: [
                "enabled": enabled ? "true" : "false",
                "accessToken": accessToken,
                "secret": secret
            ])
            appState.showToast(r.message ?? "已保存")
        } catch { appState.errorMessage = error.localizedDescription }
    }
}

// MARK: - Bark

struct BarkConfigPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var enabled = false
    @State private var barkKey = ""
    @State private var sound = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用 Bark 通知", isOn: $enabled)
            ConfigField(label: "Bark Key", placeholder: "输入 Bark Key", text: $barkKey)
                .disabled(!enabled)
            ConfigField(label: "提示音", placeholder: "默认留空", text: $sound)
                .disabled(!enabled)
            HStack {
                Button("保存配置") {
                    Task { await save() }
                }
                .buttonStyle(ProminentButton()).disabled(!enabled)
            }
        }
    }

    private func save() async {
        do {
            let url = try appState.network.makeURL("\(appState.serverURL)/api/system/updateBarkConfig")
            let r: ActionResponse = try await appState.network.post(url, body: [
                "enabled": enabled ? "true" : "false",
                "barkKey": barkKey,
                "sound": sound
            ])
            appState.showToast(r.message ?? "已保存")
        } catch { appState.errorMessage = error.localizedDescription }
    }
}

// MARK: - Feishu

struct FeishuConfigPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var enabled = false
    @State private var webhook = ""
    @State private var secret = ""
    @State private var isSaving = false
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("启用飞书通知", isOn: $enabled)
            ConfigField(label: "Webhook 地址", placeholder: "输入 Webhook URL", text: $webhook)
                .disabled(!enabled)
            ConfigField(label: "签名密钥", placeholder: "输入 Secret（选填）", text: $secret)
                .disabled(!enabled)
            HStack(spacing: 12) {
                Button(isSaving ? "保存中…" : "保存配置") {
                    Task { await save() }
                }
                .buttonStyle(ProminentButton())
                .disabled(isSaving || !enabled)

                Button(isTesting ? "测试中…" : "发送测试消息") {
                    Task { await test() }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || webhook.isEmpty)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let url = try appState.network.makeURL("\(appState.serverURL)/api/system/updateFeishuConfig")
            let r: ActionResponse = try await appState.network.post(url, body: [
                "enabled": enabled ? "true" : "false",
                "webhook": webhook,
                "secret":  secret
            ])
            appState.showToast(r.message ?? "已保存")
        } catch { appState.errorMessage = error.localizedDescription }
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let url = try appState.network.makeURL("\(appState.serverURL)/api/system/testFeishu")
            let r: ActionResponse = try await appState.network.post(url, body: [:] as [String: String])
            appState.showToast(r.message ?? "测试消息已发送")
        } catch { appState.errorMessage = error.localizedDescription }
    }
}

// MARK: - Shared

struct ConfigField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
