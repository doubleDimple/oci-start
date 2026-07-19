import SwiftUI

/// 原生密钥配置（对齐 Web `/system/domainSettings` · `domain_settings.ftl`）。
/// UI 标准：`ModuleSettingsCard` + `EqualHeightCardRow`（同质量管理页）。
struct KeyConfigView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = KeyConfigViewModel()

    private var dark: Bool { appearance.isDarkEffective }
    private let cardMinHeight: CGFloat = 420

    var body: some View {
        PageScaffold(
            title: "密钥配置",
            subtitle: "域名服务商密钥 · Cloudflare / 腾讯云 EdgeOne",
            systemImage: "key.fill",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let err = model.errorText, !err.isEmpty {
                            errorBanner(err)
                        }
                        VStack(spacing: 14) {
                            EqualHeightCardRow(minHeight: cardMinHeight) {
                                cloudflareCard
                            } second: {
                                edgeOneCard
                            }
                            EqualHeightCardRow(minHeight: 200) {
                                tipCard
                            } second: {
                                comingSoonCard
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.isLoading)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reload() }
        }
        .environmentObject(appearance)
    }

    private var toolbar: some View {
        AppButton(
            title: "刷新",
            systemImage: "arrow.clockwise",
            kind: .secondary,
            isLoading: model.isLoading
        ) {
            Task { await model.reload() }
        }
    }

    // MARK: - Cloudflare

    private var cloudflareCard: some View {
        ModuleSettingsCard(
            title: "Cloudflare",
            subtitle: "Global API Key · 域名 DNS 管理",
            systemImage: "cloud",
            accent: Color(hex: "f38020"),
            enabled: $model.cloudflare.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "API Key", required: true) {
                HStack(spacing: 8) {
                    AppTextField(
                        text: $model.cloudflare.apiToken,
                        placeholder: "Cloudflare Global API Key",
                        secure: true,
                        leadingSystemImage: "key"
                    )
                    iconBtn("doc.on.doc", tip: "复制") {
                        model.copy(model.cloudflare.apiToken, label: "API Key")
                    }
                }
            }
            Text("My Profile → API Tokens → Global API Key")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))

            FormFieldRow(label: "账户邮箱", required: true) {
                AppTextField(
                    text: $model.cloudflare.email,
                    placeholder: "Cloudflare 账户邮箱",
                    leadingSystemImage: "envelope"
                )
            }
            Text("与 API Key 配套的账户邮箱，用于身份校验")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
        } footer: {
            HStack(spacing: 8) {
                if model.cloudflare.enabled {
                    StatusBadge(text: "已启用", tone: .success)
                } else {
                    StatusBadge(text: "未启用", tone: .neutral)
                }
                Spacer(minLength: 8)
                AppButton(
                    title: "测试连接",
                    systemImage: "bolt.horizontal.circle",
                    kind: .secondary,
                    isLoading: model.savingKey == "cf-test"
                ) {
                    model.testCloudflare()
                }
                AppButton(
                    title: "保存配置",
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "cf-save"
                ) {
                    model.saveCloudflare()
                }
            }
        }
    }

    // MARK: - EdgeOne

    private var edgeOneCard: some View {
        ModuleSettingsCard(
            title: "腾讯云 EdgeOne",
            subtitle: "SecretId / SecretKey · DNS 与加速域名",
            systemImage: "globe",
            accent: Color(hex: "00b9ff"),
            enabled: $model.edgeOne.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "SecretId", required: true) {
                HStack(spacing: 8) {
                    AppTextField(
                        text: $model.edgeOne.secretId,
                        placeholder: "腾讯云 SecretId",
                        secure: true,
                        leadingSystemImage: "person"
                    )
                    iconBtn("doc.on.doc", tip: "复制") {
                        model.copy(model.edgeOne.secretId, label: "SecretId")
                    }
                }
            }
            Text("访问管理 → API 密钥管理")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))

            FormFieldRow(label: "SecretKey", required: true) {
                HStack(spacing: 8) {
                    AppTextField(
                        text: $model.edgeOne.secretKey,
                        placeholder: "腾讯云 SecretKey",
                        secure: true,
                        leadingSystemImage: "key"
                    )
                    iconBtn("doc.on.doc", tip: "复制") {
                        model.copy(model.edgeOne.secretKey, label: "SecretKey")
                    }
                }
            }
            Text("密钥仅保存在服务端，请妥善保管")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
        } footer: {
            HStack(spacing: 8) {
                if model.edgeOne.enabled {
                    StatusBadge(text: "已启用", tone: .success)
                } else {
                    StatusBadge(text: "未启用", tone: .neutral)
                }
                Spacer(minLength: 8)
                AppButton(
                    title: "测试连接",
                    systemImage: "bolt.horizontal.circle",
                    kind: .secondary,
                    isLoading: model.savingKey == "eo-test"
                ) {
                    model.testEdgeOne()
                }
                AppButton(
                    title: "保存配置",
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "eo-save"
                ) {
                    model.saveEdgeOne()
                }
            }
        }
    }

    // MARK: - Tip / Coming soon

    private var tipCard: some View {
        ModuleSettingsCard(
            title: "使用说明",
            subtitle: "配置后可在 DNS 管理页操作解析",
            systemImage: "lightbulb",
            accent: Color(hex: "9b59b6"),
            enabled: nil,
            minHeight: 200
        ) {
            tipRow(icon: "1.circle.fill", text: "填写并启用服务商密钥，先点「测试连接」确认可用")
            tipRow(icon: "2.circle.fill", text: "保存成功后，前往 Cloudflare / EdgeOne 菜单管理 DNS")
            tipRow(icon: "3.circle.fill", text: "API Key 权限不足时，列表与同步会失败")
        } footer: {
            StatusBadge(text: "安全提示：勿泄露密钥", tone: .warning)
        }
    }

    private var comingSoonCard: some View {
        ModuleSettingsCard(
            title: "更多服务商",
            subtitle: "敬请期待",
            systemImage: "plus.circle",
            accent: Color(hex: "8b949e"),
            enabled: nil,
            minHeight: 200
        ) {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(AppTheme.sidebarText(dark).opacity(0.55))
                Text("后续将支持更多 DNS / CDN 服务商")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } footer: {
            StatusBadge(text: "Coming soon", tone: .neutral)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "9b59b6"))
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(dark ? Color.white.opacity(0.88) : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func iconBtn(_ systemImage: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.sidebarActive)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.sidebarActive.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border(dark).opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(tip)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f85149"))
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reload() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }
}
