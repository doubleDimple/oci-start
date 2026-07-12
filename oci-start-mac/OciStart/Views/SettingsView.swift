import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("连接").tag(0)
                Text("账户安全").tag(1)
                Text("关于").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(16)

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: ConnectionPanel()
                    case 1: SecurityPanel()
                    default: AboutPanel()
                    }
                }
                .padding(24)
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("安全管理")
    }
}

// MARK: - Connection

struct ConnectionPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var serverURL = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("服务器地址", systemImage: "network")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("http://host:9856", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                        Button("保存") { save() }
                            .buttonStyle(.bordered)
                            .disabled(serverURL.trimmingCharacters(in: .whitespaces) == appState.serverURL)
                    }
                    Text("修改后需要重新登录。格式示例：http://192.168.1.10:9856")
                        .font(.caption).foregroundColor(.secondary)
                    if saved {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundColor(.green)
                    }
                }
                .padding(8)
            }

            GroupBox(label: Label("账户", systemImage: "person.circle")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前服务：\(appState.serverURL)")
                        .font(.callout).foregroundColor(.secondary)
                    Button("退出登录") { Task { await appState.logout() } }
                        .foregroundColor(.red)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { serverURL = appState.serverURL }
    }

    private func save() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appState.serverURL = trimmed
        withAnimation { saved = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { saved = false }
        }
    }
}

// MARK: - Security

struct SecurityPanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("修改密码", systemImage: "lock.rotation")) {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("当前密码", text: $oldPassword).textFieldStyle(.roundedBorder)
                    SecureField("新密码", text: $newPassword).textFieldStyle(.roundedBorder)
                    SecureField("确认新密码", text: $confirmPassword).textFieldStyle(.roundedBorder)

                    if let err = errorText {
                        Text(err).font(.caption).foregroundColor(AppTheme.danger)
                    }

                    Button(isSaving ? "保存中…" : "修改密码") {
                        Task { await changePassword() }
                    }
                    .buttonStyle(ProminentButton())
                    .disabled(isSaving || oldPassword.isEmpty || newPassword.isEmpty)
                }
                .padding(8)
            }
        }
    }

    private func changePassword() async {
        errorText = nil
        guard newPassword == confirmPassword else {
            errorText = "两次密码不一致"
            return
        }
        guard newPassword.count >= 6 else {
            errorText = "新密码至少 6 位"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let r = try await appState.network.updatePassword(
                baseURL: appState.serverURL, oldPassword: oldPassword, newPassword: newPassword)
            // 服务端常返回空 body；postJSONAction 记 success=true
            if r.success != false {
                appState.showToast("密码修改成功，请重新登录")
                oldPassword = ""; newPassword = ""; confirmPassword = ""
                await appState.logout()
            } else {
                errorText = r.message ?? "修改失败"
            }
        } catch { errorText = error.localizedDescription }
    }
}

// MARK: - About

struct AboutPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("关于", systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("应用名称", "OCI Start macOS Client")
                    infoRow("版本", "1.0.0")
                    infoRow("最低系统", "macOS 11.7.11+")
                    infoRow("开发语言", "Swift 5.9 + SwiftUI")
                    infoRow("项目", "oci-start")
                }
                .padding(8)
            }
            GroupBox(label: Label("打包", systemImage: "shippingbox")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本地：`./build-dmg.sh`（默认 ad-hoc 签名）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("对外：Developer ID + notarytool 公证，见 README「签名与公证」")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("数据目录：~/Library/Application Support/OciStart/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
            Text(v)
        }
        .font(.callout)
    }
}
