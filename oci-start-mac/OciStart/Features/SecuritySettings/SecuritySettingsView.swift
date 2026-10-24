import SwiftUI
import AppKit

/// 原生安全管理（对齐 Web `/system/settings` · `system_settings.ftl`）。
/// Sections and the active editor follow the current Vue security workspace.
struct SecuritySettingsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = SecuritySettingsViewModel()
    @EnvironmentObject private var navigation: NavigationState
    @ObservedObject private var language = LanguageManager.shared
    @State private var active = "account"
    @State private var guardID = UUID()

    private var dark: Bool { appearance.isDarkEffective }

    private let cardMinHeight: CGFloat = 500

    var body: some View {
        NativeSettingsWorkspace(sections: [
            ("account", language.text("账号与站点", "Account and site")),
            ("github", "GitHub"), ("google", "Google"), ("mfa", "MFA"),
            ("turnstile", "Turnstile"), ("channel", language.text("频道通知", "Channel notifications"))
        ], selection: Binding(get: { active }, set: { next in
            guard next != active, model.canLeave() else { return }
            active = next
            model.hideMfa()
            if model.hasUnsavedChanges || model.requiresReview { Task { await model.reload() } }
        }), disabled: model.savingKey != nil || model.isLoading, toolbar: {
            HStack {
                if let notice = model.notice { Text(notice).font(.system(size: AppTheme.secondarySize)) }
                Spacer()
                AppButton(title: language.text("刷新配置", "Refresh settings"), systemImage: "arrow.clockwise",
                          kind: .secondary, isLoading: model.isLoading, enabled: model.savingKey == nil) { model.requestReload() }
            }
        }, content: {
            VStack(alignment: .leading, spacing: 12) {
                if let error = model.errorText { errorBanner(error) }
                Group {
                    switch active {
                    case "github": githubCard
                    case "google": googleCard
                    case "mfa": mfaCard
                    case "turnstile": turnstileCard
                    case "channel": channelCard
                    default: accountCard
                    }
                }
                .disabled(!model.canMutate)
            }
        })
        .onAppear { navigation.setLeaveGuard(owner: guardID) { model.canLeave() }; model.start() }
        .onDisappear { model.stop(); navigation.removeLeaveGuard(owner: guardID) }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in model.requestReload() }
    }

    // MARK: - Account

    private var accountCard: some View {
        NativeSettingsPanel(
            title: language.text("账号安全", "Account security"),
            subtitle: language.text("用户名 / 密码 / 站点 Logo", "Username / password / site name"),
            systemImage: "lock.shield",
            accent: Color(hex: "4a9eff"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: language.text("当前用户", "Current user")) {
                AppTextField(text: .constant(model.currentUsername), placeholder: "—")
                    .disabled(true)
                    .opacity(0.85)
            }
            FormFieldRow(label: "Logo") {
                HStack(spacing: 8) {
                    AppTextField(text: $model.siteLogoName, placeholder: "OCI-START")
                    AppButton(
                        title: language.text("保存", "Save"),
                        systemImage: "checkmark",
                        kind: .secondary,
                        isLoading: model.savingKey == "logo"
                    ) {
                        model.saveLogo()
                    }
                }
            }
            FormFieldRow(label: language.text("当前密码", "Current password"), required: true) {
                AppTextField(
                    text: $model.currentPassword,
                    placeholder: "验证当前密码",
                    secure: true,
                    leadingSystemImage: "key"
                )
            }
            FormFieldRow(label: language.text("新用户名", "New username")) {
                AppTextField(
                    text: $model.newUsername,
                    placeholder: "留空则不修改",
                    leadingSystemImage: "person"
                )
            }
            FormFieldRow(label: language.text("新密码", "New password")) {
                AppTextField(
                    text: $model.newPassword,
                    placeholder: "留空则不修改",
                    secure: true,
                    leadingSystemImage: "lock"
                )
            }
            FormFieldRow(label: language.text("确认新密码", "Confirm password")) {
                AppTextField(
                    text: $model.confirmPassword,
                    placeholder: "再次输入新密码",
                    secure: true,
                    leadingSystemImage: "lock"
                )
            }
        } footer: {
            AppButton(
                title: language.text("保存修改", "Update account"),
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
        NativeSettingsPanel(
            title: language.text("GitHub 登录", "GitHub login"),
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
            NativeSecretEditor(title: "Client Secret", hasSaved: model.github.hasClientSecret,
                               mode: $model.github.secretMode, value: $model.github.clientSecret, required: model.github.enabled)
            FormFieldRow(label: language.text("回调地址", "Callback URL"), required: true) {
                AppTextField(
                    text: $model.github.redirectUri,
                    placeholder: "http(s)://your-domain/api/github/callback"
                )
            }
        } footer: {
            AppButton(
                title: language.text("保存配置", "Save settings"),
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
        NativeSettingsPanel(
            title: language.text("Google 登录", "Google login"),
            subtitle: "Google OAuth 登录",
            systemImage: "g.circle",
            accent: Color(hex: "4285f4"),
            enabled: $model.google.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: language.text("Google 邮箱", "Google email"), required: true) {
                AppTextField(
                    text: $model.google.email,
                    placeholder: "允许登录的 Google 邮箱",
                    leadingSystemImage: "envelope"
                )
            }
            FormFieldRow(label: "Client ID", required: true) {
                AppTextField(text: $model.google.clientId, placeholder: "Google Client ID")
            }
            NativeSecretEditor(title: "Client Secret", hasSaved: model.google.hasClientSecret,
                               mode: $model.google.secretMode, value: $model.google.clientSecret, required: model.google.enabled)
            FormFieldRow(label: language.text("回调地址", "Callback URL"), required: true) {
                AppTextField(
                    text: $model.google.redirectUri,
                    placeholder: "http(s)://your-domain/api/google/callback"
                )
            }
        } footer: {
            AppButton(
                title: language.text("保存配置", "Save settings"),
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
        NativeSettingsPanel(
            title: language.text("MFA 验证", "MFA authentication"),
            subtitle: "TOTP 多因子认证",
            systemImage: "iphone",
            accent: Color(hex: "1abc9c"),
            enabled: $model.mfa.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: language.text("应用名称", "Issuer")) {
                AppTextField(
                    text: $model.mfa.issuer,
                    placeholder: "认证器中显示的名称"
                )
            }
            if model.mfa.hasSecretKey {
                HStack(spacing: 10) {
                    Text(language.text("已配置 MFA 设置密钥", "MFA setup secret configured"))
                        .font(.system(size: AppTheme.secondarySize))
                    if model.mfa.secretKey.isEmpty {
                        AppButton(title: language.text("显示设置资料", "Reveal setup details"), kind: .secondary) { model.revealMfa() }
                    } else {
                        AppButton(title: language.text("隐藏设置资料", "Hide setup details"), kind: .secondary) { model.hideMfa() }
                    }
                }
            }
            if model.mfa.hasSecretKey && model.mfa.secretKey.isEmpty {
                FormFieldRow(label: language.text("验证码", "Verification code")) {
                    HStack {
                        AppTextField(text: Binding(get: { model.mfa.verifyCode }, set: { model.setMfaVerifyCode($0) }),
                                     placeholder: language.text("6 位数字", "Six digits"), onCommit: { model.verifyMfa() })
                        AppButton(title: language.text("验证", "Verify"), kind: .secondary) { model.verifyMfa() }
                    }
                }
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary(dark))
                            Text("使用 Google Authenticator 等应用扫码")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary(dark))
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
                            title: language.text("复制", "Copy"),
                            systemImage: "doc.on.doc",
                            kind: .secondary
                        ) {
                            model.copyMfaSecret()
                        }
                    }
                }
                FormFieldRow(label: language.text("验证码", "Verification code")) {
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
                            title: language.text("验证", "Verify"),
                            systemImage: "checkmark",
                            kind: .secondary,
                            isLoading: model.savingKey == "mfaVerify"
                        ) {
                            model.verifyMfa()
                        }
                    }
                }
            } else if !model.mfa.hasSecretKey {
                Text(language.text("请生成设置密钥，再完成验证器设置。", "Generate a setup secret, then configure your authenticator."))
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(dark))
            }
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: language.text("保存", "Save"),
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "mfa"
                ) {
                    model.saveMfa()
                }
                AppButton(
                    title: language.text("重新生成", "Regenerate"),
                    systemImage: "arrow.clockwise",
                    kind: .secondary,
                    isLoading: model.savingKey == "mfaRegen"
                ) {
                    model.regenerateMfa()
                }
                if model.mfa.hasSecretKey || model.mfa.enabled {
                    AppButton(
                        title: language.text("删除", "Delete"),
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
        NativeSettingsPanel(
            title: "Cloudflare Turnstile",
            subtitle: language.text("登录人机验证", "Login challenge"),
            systemImage: "shield.lefthalf.fill",
            accent: Color(hex: "f0881a"),
            enabled: $model.turnstile.enabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "Site Key") {
                AppTextField(text: $model.turnstile.siteKey, placeholder: "公开 Site Key")
            }
            NativeSecretEditor(title: "Secret Key", hasSaved: model.turnstile.hasSecretKey,
                               mode: $model.turnstile.secretMode, value: $model.turnstile.secretKey, required: model.turnstile.enabled)
        } footer: {
            AppButton(
                title: language.text("保存配置", "Save settings"),
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
        NativeSettingsPanel(
            title: language.text("开机频道通知", "Launch channel notifications"),
            subtitle: "匿名上报机型与区域",
            systemImage: "antenna.radiowaves.left.and.right",
            accent: Color(hex: "9b59b6"),
            enabled: $model.channelNotifyEnabled,
            minHeight: cardMinHeight
        ) {
            Text("开启后，抢机成功会向公共频道上报实例类型与区域，不含账号与 IP 等隐私信息。")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(dark))
                .fixedSize(horizontal: false, vertical: true)
            Text("采集：机型、区域。不采集：租户、密钥、IP、用户名。")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(dark))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            AppButton(
                title: language.text("保存配置", "Save settings"),
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
            Text(text).font(.system(size: 14))
            Spacer()
            Button(language.text("重新读取并核对", "Reload and review")) { model.requestReload() }
                .disabled(model.savingKey != nil || model.isLoading)
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }
}


/// Shared layout for native security and notification settings: a section list and one editor.
struct NativeSettingsWorkspace<Toolbar: View, Content: View>: View {
    let sections: [(String, String)]
    @Binding var selection: String
    var disabled = false
    let toolbar: Toolbar
    let content: Content
    @EnvironmentObject private var appearance: AppearanceController
    init(sections: [(String, String)], selection: Binding<String>, disabled: Bool,
         @ViewBuilder toolbar: () -> Toolbar, @ViewBuilder content: () -> Content) {
        self.sections = sections; _selection = selection; self.disabled = disabled
        self.toolbar = toolbar(); self.content = content()
    }
    private var dark: Bool { appearance.isDarkEffective }
    var body: some View {
        VStack(spacing: 14) {
            toolbar
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(sections, id: \.0) { section in
                        Button(action: { selection = section.0 }) {
                            Text(section.1)
                                .font(.system(size: AppTheme.bodySize, weight: selection == section.0 ? .semibold : .regular))
                                .foregroundColor(selection == section.0 ? AppTheme.brand(dark) : AppTheme.textPrimary(dark))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(selection == section.0 ? AppTheme.brand(dark).opacity(0.09) : Color.clear)
                                .cornerRadius(10)
                                .contentShape(Rectangle())
                        }.buttonStyle(PlainButtonStyle()).disabled(disabled)
                    }
                }
                .padding(8)
                .frame(width: 180)
                .background(AppTheme.cardBg(dark)).cornerRadius(AppTheme.cardRadius)
                ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(AppTheme.pagePadding)
        .foregroundColor(AppTheme.textPrimary(dark))
        .background(AppTheme.pageBg(dark))
    }
}

struct NativeSettingsPanel<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let enabled: Binding<Bool>?
    let content: Content
    let footer: Footer
    @EnvironmentObject private var appearance: AppearanceController
    @ObservedObject private var language = LanguageManager.shared
    init(title: String, subtitle: String, systemImage: String, accent: Color,
         enabled: Binding<Bool>?, minHeight: CGFloat,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title; self.subtitle = subtitle; self.enabled = enabled
        self.content = content(); self.footer = footer()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: AppTheme.sectionSize, weight: .semibold))
                    Text(subtitle).font(.system(size: AppTheme.secondarySize))
                }
                Spacer()
                if let enabled = enabled {
                    Toggle(language.text("启用", "Enabled"), isOn: enabled).toggleStyle(SwitchToggleStyle())
                }
            }
            content
            Divider()
            HStack { Spacer(); footer }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg(appearance.isDarkEffective))
        .cornerRadius(AppTheme.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.border(appearance.isDarkEffective), lineWidth: 1))
    }
}
