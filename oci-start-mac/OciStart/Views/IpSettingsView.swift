import SwiftUI

/// Native IP quality check settings (Web: /system/ipSettings)
struct IpSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var loading = false
    @State private var checkEnabled = false
    @State private var checkInterval = 6
    @State private var telecom = OperatorVpsFormState(type: "telecom", title: "电信 VPS")
    @State private var unicom = OperatorVpsFormState(type: "unicom", title: "联通 VPS")
    @State private var mobile = OperatorVpsFormState(type: "mobile", title: "移动 VPS")
    @State private var savingCheck = false

    var body: some View {
        Group {
            if loading {
                PageLoadingView(message: "加载质量检测配置…")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ipCheckCard
                        OperatorVpsCard(state: $telecom)
                        OperatorVpsCard(state: $unicom)
                        OperatorVpsCard(state: $mobile)
                    }
                    .padding(24)
                }
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("质量检测")
        .toolbar {
            ToolbarItem {
                if loading || savingCheck { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: { Task { await load() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { Task { await load() } }
    }

    private var ipCheckCard: some View {
        GroupBox(label: Label("IP 质量检测", systemImage: "checkmark.shield")) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("启用定期检测", isOn: $checkEnabled)
                HStack {
                    Text("检测间隔")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppTheme.muted(scheme))
                    Picker("", selection: $checkInterval) {
                        ForEach(1...24, id: \.self) { h in
                            Text("\(h) 小时").tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                    Spacer()
                }
                Text("按设定间隔检测实例公网 IP 质量（需配置运营商探测 VPS）")
                    .font(.caption)
                    .foregroundColor(AppTheme.muted(scheme))
                Button(savingCheck ? "保存中…" : "保存检测配置") {
                    Task { await saveIpCheck() }
                }
                .buttonStyle(ProminentButton())
                .disabled(savingCheck)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let b = try await appState.network.getIpSettingsConfigs(baseURL: appState.serverURL)
            checkEnabled = b.ipCheck?.enabled ?? false
            checkInterval = b.ipCheck?.checkInterval ?? 6
            if checkInterval < 1 || checkInterval > 24 { checkInterval = 6 }
            telecom.apply(b.telecom)
            unicom.apply(b.unicom)
            mobile.apply(b.mobile)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func saveIpCheck() async {
        savingCheck = true
        defer { savingCheck = false }
        do {
            let r = try await appState.network.updateIpCheckConfig(
                baseURL: appState.serverURL, enabled: checkEnabled, checkInterval: checkInterval)
            if r.success == false {
                appState.errorMessage = r.message ?? "保存失败"
            } else {
                appState.showToast(r.message ?? "检测配置已保存")
            }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Operator VPS form state

struct OperatorVpsFormState {
    let type: String
    let title: String
    var enabled = false
    var serverIp = ""
    var username = "root"
    var password = ""
    var sshPort = "22"
    var saving = false
    var testing = false

    mutating func apply(_ c: OperatorVpsConfig?) {
        guard let c = c else { return }
        enabled = c.enabled ?? false
        serverIp = c.serverIp ?? ""
        username = c.username ?? "root"
        password = c.password ?? ""
        sshPort = "\(c.sshPort ?? 22)"
    }
}

struct OperatorVpsCard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @Binding var state: OperatorVpsFormState

    var body: some View {
        GroupBox(label: Label(state.title, systemImage: "server.rack")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用", isOn: $state.enabled)
                ConfigField(label: "服务器地址", placeholder: "IP 或域名", text: $state.serverIp)
                    .disabled(!state.enabled)
                HStack(spacing: 12) {
                    ConfigField(label: "SSH 用户", placeholder: "root", text: $state.username)
                        .disabled(!state.enabled)
                    ConfigField(label: "SSH 端口", placeholder: "22", text: $state.sshPort)
                        .disabled(!state.enabled)
                        .frame(maxWidth: 120)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH 密码")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppTheme.muted(scheme))
                    SecureField("SSH 密码", text: $state.password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!state.enabled)
                }
                HStack(spacing: 12) {
                    Button(state.testing ? "测试中…" : "测试连接") {
                        Task { await test() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.testing || state.serverIp.isEmpty)

                    Button(state.saving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .buttonStyle(ProminentButton())
                    .disabled(state.saving)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() async {
        let port = Int(state.sshPort) ?? 22
        if state.enabled {
            guard !state.serverIp.isEmpty, !state.username.isEmpty, !state.password.isEmpty else {
                appState.errorMessage = "启用时请填写地址、用户名和密码"
                return
            }
        }
        state.saving = true
        defer { state.saving = false }
        do {
            let r = try await appState.network.saveOperatorVpsConfig(
                baseURL: appState.serverURL,
                type: state.type,
                enabled: state.enabled,
                serverIp: state.serverIp,
                username: state.username,
                sshPort: port,
                password: state.password)
            if r.success == false {
                appState.errorMessage = r.message ?? "保存失败"
            } else {
                appState.showToast("\(state.title) 已保存")
            }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func test() async {
        let port = Int(state.sshPort) ?? 22
        guard !state.serverIp.isEmpty, !state.username.isEmpty, !state.password.isEmpty else {
            appState.errorMessage = "请先填写完整 SSH 信息"
            return
        }
        state.testing = true
        defer { state.testing = false }
        do {
            let r = try await appState.network.testOperatorVpsConnection(
                baseURL: appState.serverURL,
                type: state.type,
                serverIp: state.serverIp,
                username: state.username,
                sshPort: port,
                password: state.password)
            if r.success == false {
                appState.errorMessage = r.message ?? "连接失败"
            } else {
                appState.showToast(r.message ?? "SSH 连接成功")
            }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
