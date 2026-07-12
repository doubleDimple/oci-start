import SwiftUI

/// Native domain provider credentials (Web: /system/domainSettings)
struct DomainSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var loading = false
    @State private var cfEnabled = false
    @State private var cfToken = ""
    @State private var cfEmail = ""
    @State private var cfSaving = false
    @State private var cfTesting = false

    @State private var eoEnabled = false
    @State private var eoSecretId = ""
    @State private var eoSecretKey = ""
    @State private var eoRegion = "ap-beijing"
    @State private var eoSaving = false
    @State private var eoTesting = false

    var body: some View {
        Group {
            if loading {
                PageLoadingView(message: "加载密钥配置…")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        cloudflareCard
                        edgeOneCard
                        Text("密钥用于 Cloudflare / EdgeOne DNS 管理，请妥善保管。")
                            .font(.caption)
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    .padding(24)
                }
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("密钥配置")
        .toolbar {
            ToolbarItem {
                if loading { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: { Task { await load() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { Task { await load() } }
    }

    private var cloudflareCard: some View {
        GroupBox(label: Label("Cloudflare", systemImage: "cloud")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("启用", isOn: $cfEnabled)
                    Spacer()
                    statusPill(on: cfEnabled && !cfToken.isEmpty)
                }
                secretField(label: "API Key / Token", text: $cfToken, enabled: cfEnabled)
                ConfigField(label: "账户邮箱", placeholder: "Cloudflare 账户邮箱", text: $cfEmail)
                    .disabled(!cfEnabled)
                Text("在 Cloudflare 控制台 → My Profile → API Tokens 创建")
                    .font(.caption2)
                    .foregroundColor(AppTheme.muted(scheme))
                HStack(spacing: 12) {
                    Button(cfTesting ? "测试中…" : "测试连接") { Task { await testCF() } }
                        .buttonStyle(.bordered)
                        .disabled(cfTesting || cfToken.isEmpty)
                    Button(cfSaving ? "保存中…" : "保存") { Task { await saveCF() } }
                        .buttonStyle(ProminentButton())
                        .disabled(cfSaving)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var edgeOneCard: some View {
        GroupBox(label: Label("腾讯云 EdgeOne", systemImage: "globe")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("启用", isOn: $eoEnabled)
                    Spacer()
                    statusPill(on: eoEnabled && !eoSecretId.isEmpty && !eoSecretKey.isEmpty)
                }
                secretField(label: "SecretId", text: $eoSecretId, enabled: eoEnabled)
                secretField(label: "SecretKey", text: $eoSecretKey, enabled: eoEnabled)
                ConfigField(label: "地域", placeholder: "ap-beijing", text: $eoRegion)
                    .disabled(!eoEnabled)
                Text("在腾讯云访问管理 → API 密钥管理 获取")
                    .font(.caption2)
                    .foregroundColor(AppTheme.muted(scheme))
                HStack(spacing: 12) {
                    Button(eoTesting ? "测试中…" : "测试连接") { Task { await testEO() } }
                        .buttonStyle(.bordered)
                        .disabled(eoTesting || eoSecretId.isEmpty || eoSecretKey.isEmpty)
                    Button(eoSaving ? "保存中…" : "保存") { Task { await saveEO() } }
                        .buttonStyle(ProminentButton())
                        .disabled(eoSaving)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func secretField(label: String, text: Binding<String>, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.muted(scheme))
            SecureField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(!enabled)
        }
    }

    private func statusPill(on: Bool) -> some View {
        Text(on ? "已配置" : "未连接")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((on ? Color.green : Color.gray).opacity(0.18))
            .foregroundColor(on ? .green : .secondary)
            .cornerRadius(6)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let b = try await appState.network.getDomainProviderConfigs(baseURL: appState.serverURL)
            cfEnabled = b.cloudflare?.enabled ?? false
            cfToken = b.cloudflare?.apiToken ?? ""
            cfEmail = b.cloudflare?.email ?? ""
            eoEnabled = b.edgeOne?.enabled ?? false
            eoSecretId = b.edgeOne?.secretId ?? ""
            eoSecretKey = b.edgeOne?.secretKey ?? ""
            eoRegion = b.edgeOne?.region ?? "ap-beijing"
            if eoRegion.isEmpty { eoRegion = "ap-beijing" }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func saveCF() async {
        if cfEnabled && (cfToken.isEmpty || cfEmail.isEmpty) {
            appState.errorMessage = "启用时请填写 API Key 与邮箱"
            return
        }
        cfSaving = true
        defer { cfSaving = false }
        do {
            let r = try await appState.network.updateCloudflareConfig(
                baseURL: appState.serverURL, enabled: cfEnabled,
                apiToken: cfToken, email: cfEmail)
            if r.success == false {
                appState.errorMessage = r.message ?? "保存失败"
            } else {
                appState.showToast("Cloudflare 配置已保存")
            }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func testCF() async {
        cfTesting = true
        defer { cfTesting = false }
        do {
            let r = try await appState.network.testCloudflareConfig(
                baseURL: appState.serverURL, enabled: true,
                apiToken: cfToken, email: cfEmail)
            if r.success == false {
                appState.errorMessage = r.message ?? "连接失败"
            } else {
                appState.showToast(r.message ?? "Cloudflare 连接成功")
            }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func saveEO() async {
        if eoEnabled && (eoSecretId.isEmpty || eoSecretKey.isEmpty) {
            appState.errorMessage = "启用时请填写 SecretId 与 SecretKey"
            return
        }
        eoSaving = true
        defer { eoSaving = false }
        do {
            let r = try await appState.network.updateEdgeOneConfig(
                baseURL: appState.serverURL, enabled: eoEnabled,
                secretId: eoSecretId, secretKey: eoSecretKey, region: eoRegion)
            if r.success == false {
                appState.errorMessage = r.message ?? "保存失败"
            } else {
                appState.showToast("EdgeOne 配置已保存")
            }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func testEO() async {
        eoTesting = true
        defer { eoTesting = false }
        do {
            let r = try await appState.network.testEdgeOneConfig(
                baseURL: appState.serverURL, enabled: true,
                secretId: eoSecretId, secretKey: eoSecretKey, region: eoRegion)
            if r.success == false {
                appState.errorMessage = r.message ?? "连接失败"
            } else {
                appState.showToast(r.message ?? "EdgeOne 连接成功")
            }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
