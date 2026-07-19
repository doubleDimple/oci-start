import SwiftUI
import AppKit

/// 原生安全管理（对齐 Web `/system/settings` · `system_settings.ftl`）。
/// 布局遵循质量管理页 UI 标准：`ModuleSettingsCard` + `EqualHeightCardRow`。
struct SecuritySettingsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = SecuritySettingsViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    private let cardMinHeight: CGFloat = 500

    var body: some View {
        PageScaffold(
            title: "安全管理",
            subtitle: "账号安全 · OAuth · MFA · Turnstile · 频道通知",
            systemImage: "slider.horizontal.3",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let err = model.errorText, !err.isEmpty {
                            errorBanner(err)
                        }
                        VStack(spacing: 14) {
                            EqualHeightCardRow(minHeight: cardMinHeight) {
                                accountCard
                            } second: {
                                githubCard
                            }
                            EqualHeightCardRow(minHeight: cardMinHeight) {
                                googleCard
                            } second: {
                                mfaCard
                            }
                            EqualHeightCardRow(minHeight: cardMinHeight) {
                                turnstileCard
                            } second: {
                                channelCard
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

    // MARK: - Account

    private var accountCard: some View {
        ModuleSettingsCard(
            title: "账号安全",
            subtitle: "用户名 / 密码 / 站点 Logo",
            systemImage: "lock.shield",
            accent: Color(hex: "4a9eff"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "当前用户") {
                AppTextField(text: .constant(model.currentUsername), placeholder: "—")
                    .disabled(true)
                    .opacity(0.85)
            }
            FormFieldRow(label: "Logo") {
                HStack(spacing: 8) {
                    AppTextField(text: $model.siteLogoName, placeholder: "OCI-START")
                    AppButton(
                        title: "保存",
                        systemImage: "checkmark",
                        kind: .secondary,
                        isLoading: model.savingKey == "logo"
                    ) {
                        model.saveLogo()
                    }
                }
            }
            FormFieldRow(label: "当前密码", required: true) {
                AppTextField(
                    text: $model.currentPassword,
                    placeholder: "验证当前密码",
                    secure: true,
                    leadingSystemImage: "key"
                )
            }
            FormFieldRow(label: "新用户名") {
                AppTextField(
                    text: $model.newUsername,
                    placeholder: "留空则不修改",
                    leadingSystemImage: "person"
                )
            }
            FormFieldRow(label: "新密码") {
                AppTextField(
                    text: $model.newPassword,
                    placeholder: "留空则不修改",
                    secure: true,
                    leadingSystemImage: "lock"
                )
            }
            FormFieldRow(label: "确认新密码") {
                AppTextField(
                    text: $model.confirmPassword,
                    placeholder: "再次输入新密码",
                    secure: true,
                    leadingSystemImage: "lock"
                )
            }
        } footer: {
            AppButton(
                title: "保存修改",
                systemImage: "square.and.arrow.down",
                kind: .primary,
                isLoading: model.savingKey == "account"
            ) {
                model.updateAccount()
            }
        }
    }

    // MARK: - GitHub

    private var githubCard: some View {
        ModuleSettingsCard(
            title: "GitHub 登录",
            subtitle: "OAuth 第三方登录",
            systemImage: "chevron.left.slash.chevron.right",
            accent: Color(hex: "adbac7"),
            enabled: $model.github.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "GitHub 用户名") {
                HStack(spacing: 8) {
                    AppTextField(
                        text: $model.github.username,
                        placeholder: "GitHub 用户名",
                        leadingSystemImage: "person.crop.circle"
                    )
                    AppButton(
                        title: "获取 ID",
                        systemImage: "magnifyingglass",
                        kind: .secondary,
                        isLoading: model.savingKey == "githubFetch"
                    ) {
                        model.fetchGithubId()
                    }
                }
            }
            FormFieldRow(label: "GitHub ID") {
                AppTextField(text: $model.github.githubId, placeholder: "自动获取")
                    .disabled(true)
                    .opacity(0.9)
            }
            FormFieldRow(label: "Client ID", required: true) {
                AppTextField(text: $model.github.clientId, placeholder: "OAuth App Client ID")
            }
            FormFieldRow(label: "Client Secret", required: true) {
                AppTextField(text: $model.github.clientSecret, placeholder: "Client Secret", secure: true)
            }
            FormFieldRow(label: "回调地址", required: true) {
                AppTextField(
                    text: $model.github.redirectUri,
                    placeholder: "http(s)://your-domain/api/github/callback"
                )
            }
        } footer: {
            AppButton(
                title: "保存配置",
                systemImage: "square.and.arrow.down",
                kind: .primary,
                isLoading: model.savingKey == "github"
            ) {
                model.saveGithub()
            }
        }
    }

    // MARK: - Google

    private var googleCard: some View {
        ModuleSettingsCard(
            title: "Google 登录",
            subtitle: "Google OAuth 登录",
            systemImage: "g.circle",
            accent: Color(hex: "4285f4"),
            enabled: $model.google.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "Google 邮箱", required: true) {
                AppTextField(
                    text: $model.google.email,
                    placeholder: "允许登录的 Google 邮箱",
                    leadingSystemImage: "envelope"
                )
            }
            FormFieldRow(label: "Client ID", required: true) {
                AppTextField(text: $model.google.clientId, placeholder: "Google Client ID")
            }
            FormFieldRow(label: "Client Secret", required: true) {
                AppTextField(text: $model.google.clientSecret, placeholder: "Client Secret", secure: true)
            }
            FormFieldRow(label: "回调地址", required: true) {
                AppTextField(
                    text: $model.google.redirectUri,
                    placeholder: "http(s)://your-domain/api/google/callback"
                )
            }
        } footer: {
            AppButton(
                title: "保存配置",
                systemImage: "square.and.arrow.down",
                kind: .primary,
                isLoading: model.savingKey == "google"
            ) {
                model.saveGoogle()
            }
        }
    }

    // MARK: - MFA

    private var mfaCard: some View {
        ModuleSettingsCard(
            title: "MFA 验证",
            subtitle: "TOTP 多因子认证",
            systemImage: "iphone",
            accent: Color(hex: "1abc9c"),
            enabled: $model.mfa.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "应用名称") {
                AppTextField(
                    text: $model.mfa.issuer,
                    placeholder: "认证器中显示的名称"
                )
            }
            if !model.mfa.secretKey.isEmpty {
                if let img = SecuritySettingsJSON.qrImage(from: model.mfa.qrCodeBase64) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 120, height: 120)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.border(dark), lineWidth: 1)
                            )
                        VStack(alignment: .leading, spacing: 6) {
                            Text("扫码绑定")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                            Text("使用 Google Authenticator 等应用扫码")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.sidebarText(dark))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
                FormFieldRow(label: "MFA 密钥") {
                    HStack(spacing: 8) {
                        AppTextField(text: .constant(model.mfa.secretKey), placeholder: "—")
                            .disabled(true)
                        AppButton(
                            title: "复制",
                            systemImage: "doc.on.doc",
                            kind: .secondary
                        ) {
                            model.copyMfaSecret()
                        }
                    }
                }
                FormFieldRow(label: "验证码") {
                    HStack(spacing: 8) {
                        AppTextField(
                            text: Binding(
                                get: { model.mfa.verifyCode },
                                set: { model.setMfaVerifyCode($0) }
                            ),
                            placeholder: "6 位数字",
                            leadingSystemImage: "number",
                            onCommit: { model.verifyMfa() }
                        )
                        AppButton(
                            title: "验证",
                            systemImage: "checkmark",
                            kind: .secondary,
                            isLoading: model.savingKey == "mfaVerify"
                        ) {
                            model.verifyMfa()
                        }
                    }
                }
            } else {
                Text("保存启用后将生成二维码与密钥")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: "保存",
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "mfa"
                ) {
                    model.saveMfa()
                }
                AppButton(
                    title: "重新生成",
                    systemImage: "arrow.clockwise",
                    kind: .secondary,
                    isLoading: model.savingKey == "mfaRegen"
                ) {
                    model.regenerateMfa()
                }
                if !model.mfa.secretKey.isEmpty {
                    AppButton(
                        title: "删除",
                        systemImage: "trash",
                        kind: .danger,
                        isLoading: model.savingKey == "mfaDelete"
                    ) {
                        model.deleteMfa()
                    }
                }
            }
        }
    }

    // MARK: - Turnstile

    private var turnstileCard: some View {
        ModuleSettingsCard(
            title: "Cloudflare Turnstile",
            subtitle: "登录人机验证",
            systemImage: "shield.lefthalf.fill",
            accent: Color(hex: "f0881a"),
            enabled: $model.turnstile.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "Site Key") {
                AppTextField(text: $model.turnstile.siteKey, placeholder: "公开 Site Key")
            }
            FormFieldRow(label: "Secret Key") {
                AppTextField(
                    text: $model.turnstile.secretKey,
                    placeholder: "服务端 Secret Key",
                    secure: true
                )
            }
        } footer: {
            AppButton(
                title: "保存配置",
                systemImage: "square.and.arrow.down",
                kind: .primary,
                isLoading: model.savingKey == "turnstile"
            ) {
                model.saveTurnstile()
            }
        }
    }

    // MARK: - Channel notify

    private var channelCard: some View {
        ModuleSettingsCard(
            title: "开机频道通知",
            subtitle: "匿名上报机型与区域",
            systemImage: "antenna.radiowaves.left.and.right",
            accent: Color(hex: "9b59b6"),
            enabled: $model.channelNotifyEnabled,
            minHeight: cardMinHeight
        ) {
            Text("开启后，抢机成功会向公共频道上报实例类型与区域，不含账号与 IP 等隐私信息。")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
                .fixedSize(horizontal: false, vertical: true)
            Text("采集：机型、区域。不采集：租户、密钥、IP、用户名。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark).opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            AppButton(
                title: "保存配置",
                systemImage: "square.and.arrow.down",
                kind: .primary,
                isLoading: model.savingKey == "channel"
            ) {
                model.saveChannelNotify()
            }
        }
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
