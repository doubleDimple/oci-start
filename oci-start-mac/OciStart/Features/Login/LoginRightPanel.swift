import SwiftUI
import AppKit

/// Compact native form using the Vue login spacing and controls.
struct LoginRightPanel: View {
    @EnvironmentObject private var appearance: AppearanceController
    @ObservedObject var model: LoginFormModel
    var dark: Bool
    @ObservedObject var backend: BackendController
    var onLogin: () -> Void
    var onRegister: () -> Void
    var onSendCode: () -> Void
    var onOAuth: (String) -> Void
    var onServerCommit: () -> Void = {}
    var onDeploymentMode: (DeploymentMode) -> Void = { _ in }
    var onForgotPassword: () -> Void = {}
    var onLocale: (AppLocale) -> Void = { _ in }

    private var formReady: Bool {
        guard model.modeActivated else { return false }
        if model.isRemoteServer { return true }
        return backend.isReadyForLogin
    }

    /// Only after user picks「本机使用」and backend is still coming up.
    private var showBootLoading: Bool {
        guard model.isLocalActivated else { return false }
        switch backend.state {
        case .idle, .starting: return true
        default: return false
        }
    }

    private var localBootFailed: String? {
        guard model.isLocalActivated else { return nil }
        if case .failed(let m) = backend.state { return m }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topChipBar
                .padding(.horizontal, 46)
                .padding(.top, 26)
                .padding(.bottom, 18)
            GeometryReader { geo in
                ScrollView(.vertical) {
                    formContent
                        .padding(.horizontal, 46)
                        .padding(.vertical, 22)
                        .frame(maxWidth: 400)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height, alignment: .center)
                }
            }
            Text(model.locale == .enUS
                 ? (model.allowRegister ? "Create an account to get started." : "Need access? Contact your administrator.")
                 : (model.allowRegister ? "还没有账号？可以在上方创建账号。" : "需要访问权限？请联系管理员。"))
                .font(.system(size: 12))
                .foregroundColor(LoginPalette.muted(dark))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .padding(.bottom, 30)
        }
        .background(LoginPalette.card(dark))
        .animation(.easeInOut(duration: 0.2), value: showBootLoading)
        .animation(.easeInOut(duration: 0.2), value: localBootFailed != nil)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand.padding(.bottom, 28)
            deploymentModeSwitcher.padding(.bottom, 22)
            if !model.modeActivated && !model.hasPersistedChoice {
                pickModeHint
            }
            if showBootLoading {
                bootLoadingView
            } else if let message = localBootFailed {
                bootFailedView(message)
            } else if model.modeActivated {
                if model.allowRegister {
                    tabs.padding(.bottom, 22)
                }
                if model.isRemoteServer {
                    serverRow.padding(.bottom, 14)
                }
                statusStrip.padding(.bottom, 14)
                ZStack {
                    Group {
                        if model.tab == .login { loginFields } else { registerFields }
                    }
                    .opacity(model.isLoadingMeta ? 0.45 : 1)
                    .allowsHitTesting(!model.isLoadingMeta)
                    if model.isLoadingMeta {
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                    }
                }
                if let error = model.errorText {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: dark ? "ff7a7a" : "c94a4a"))
                        .padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let info = model.infoText {
                    Text(info)
                        .font(.system(size: 13))
                        .foregroundColor(LoginPalette.muted(dark))
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var bootLoadingView: some View {
        VStack(spacing: 14) {
            ProgressView().progressViewStyle(CircularProgressViewStyle())
            Text(model.locale == .enUS ? "Starting local service…" : "正在启动本机服务…")
                .font(.system(size: 14))
            Text(model.locale == .enUS
                 ? "You can also connect to a remote server."
                 : "也可切换到远程部署，连接已有服务。")
                .font(.system(size: 13))
                .foregroundColor(LoginPalette.muted(dark))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(LoginPalette.text(dark))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func bootFailedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.locale == .enUS ? "Service failed to start" : "服务启动失败",
                  systemImage: "exclamationmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: dark ? "ff7a7a" : "c94a4a"))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(LoginPalette.muted(dark))
                .fixedSize(horizontal: false, vertical: true)
            LoginPillButton(title: model.locale == .enUS ? "Try again" : "重新启动", dark: dark) {
                Task { await backend.start() }
            }
        }
        .padding(.vertical, 20)
    }

    private var pickModeHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LoginPalette.primary(dark))
            Text(model.locale == .enUS
                 ? "First launch: choose Local or Remote. Your choice will be remembered."
                 : "首次使用请选择「本机使用」或「已远程部署」，之后会自动记住")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(LoginPalette.muted(dark))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Top: locale

    private var topChipBar: some View {
        HStack(spacing: 4) {
            Spacer()
            langItem(.zhCN, "中文")
            Text("/")
                .font(.system(size: 12))
                .foregroundColor(LoginPalette.muted(dark))
                .padding(.horizontal, 4)
            langItem(.enUS, "EN")
            Button(action: { appearance.mode = dark ? .light : .dark }) {
                Image(systemName: dark ? "sun.max" : "moon")
                    .font(.system(size: 14))
                    .foregroundColor(LoginPalette.muted(dark))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .help(model.locale == .enUS
                  ? (dark ? "Switch to light appearance" : "Switch to dark appearance")
                  : (dark ? "切换浅色外观" : "切换深色外观"))
            .accessibilityLabel(model.locale == .enUS ? "Toggle appearance" : "切换外观")
            .padding(.leading, 6)
        }
    }

    /// 本机使用 / 已远程部署 — first install must tap; later launches restore last choice.
    private var deploymentModeSwitcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.locale == .enUS ? "Deployment" : "部署方式")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(LoginPalette.text(dark))
                if !model.modeActivated && !model.hasPersistedChoice {
                    Text(model.locale == .enUS ? "required" : "首次必选")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LoginPalette.primary(dark))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LoginPalette.tabActiveBg(dark))
                        .cornerRadius(8)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 4) {
                modeSegment(
                    .local,
                    title: model.locale == .enUS ? "Local" : "本机使用",
                    subtitle: model.locale == .enUS ? "Start backend here" : "启动本地后端"
                )
                modeSegment(
                    .remote,
                    title: model.locale == .enUS ? "Remote" : "已远程部署",
                    subtitle: model.locale == .enUS ? "No local Java" : "不启动本地服务"
                )
            }
        }
    }

    private func modeSegment(_ mode: DeploymentMode, title: String, subtitle: String) -> some View {
        let selected = model.modeActivated && model.deploymentMode == mode
        return Button(action: {
            if model.modeActivated, model.deploymentMode == mode { return }
            onDeploymentMode(mode)
        }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: mode == .local ? "laptopcomputer" : "cloud")
                        .font(.system(size: 11, weight: .semibold))
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(selected ? LoginPalette.tabActiveText(dark) : LoginPalette.text(dark))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(selected ? LoginPalette.tabActiveText(dark).opacity(0.85) : LoginPalette.muted(dark))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? LoginPalette.tabActiveBg(dark) : LoginPalette.chipBg(dark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selected
                            ? LoginPalette.primary(dark).opacity(dark ? 0.45 : 0.2)
                            : LoginPalette.line(dark).opacity(0.6),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(model.isSubmitting || model.isLoadingMeta)
    }

    private func langItem(_ loc: AppLocale, _ title: String) -> some View {
        let active = model.locale == loc
        return Button(action: {
            model.locale = loc
            onLocale(loc)
        }) {
            Text(title)
                .font(.system(size: 13, weight: active ? .medium : .regular))
                .foregroundColor(active ? LoginPalette.text(dark) : LoginPalette.muted(dark))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.locale == .enUS ? "Welcome back" : "欢迎回来")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(LoginPalette.text(dark))
            Text(model.locale == .enUS ? "Sign in to your OCI-START workspace." : "登录你的 OCI-START 工作台。")
                .font(.system(size: 14))
                .foregroundColor(LoginPalette.muted(dark))
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tabBtn(model.locale == .enUS ? "Login" : "登录", selected: model.tab == .login) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    model.tab = .login
                    model.errorText = nil
                }
            }
            tabBtn(model.locale == .enUS ? "Register" : "注册", selected: model.tab == .register) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    model.tab = .register
                    model.errorText = nil
                }
            }
            Spacer()
        }
    }

    private func tabBtn(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundColor(selected ? LoginPalette.tabActiveText(dark) : LoginPalette.text(dark))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selected ? LoginPalette.tabActiveBg(dark) : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Remote server URL + Connect — only visible in remote deployment mode.
    private var serverRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.locale == .enUS ? "Server URL" : "服务器地址")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LoginPalette.text(dark))
            HStack(alignment: .center, spacing: 8) {
                LoginField(
                    title: "",
                    placeholder: "https://your-host:port",
                    text: $model.serverURL,
                    secure: false,
                    dark: dark,
                    enabled: !model.isLoadingMeta,
                    onCommit: onServerCommit
                )
                LoginFieldActionButton(
                    title: model.isLoadingMeta
                        ? (model.locale == .enUS ? "…" : "连接中")
                        : (model.locale == .enUS ? "Connect" : "连接"),
                    loading: model.isLoadingMeta,
                    enabled: !model.serverURL.trimmingCharacters(in: .whitespaces).isEmpty
                        && !model.serverURL.trimmingCharacters(in: .whitespaces).hasSuffix("://"),
                    dark: dark,
                    minWidth: 70,
                    action: onServerCommit
                )
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Compact status (no heavy cards that jump)

    @ViewBuilder
    private var statusStrip: some View {
        if model.modeActivated {
            if model.isRemoteServer {
                if let err = model.metaError, !model.isLoadingMeta {
                    compactStatus(
                        icon: "wifi.exclamationmark",
                        color: Color(hex: "ef4444"),
                        text: model.locale == .enUS ? "Remote unreachable" : "远程服务器不可用",
                        detail: err
                    )
                } else if model.metaLoadedURL != nil, !model.isLoadingMeta {
                    compactStatus(
                        icon: "checkmark.circle.fill",
                        color: Color(hex: "22c55e"),
                        text: model.locale == .enUS ? "Remote ready" : "远程服务器已就绪"
                    )
                } else if !model.isLoadingMeta {
                    compactStatus(
                        icon: "link",
                        color: LoginPalette.muted(dark),
                        text: model.locale == .enUS
                            ? "Enter URL and tap Connect — no local backend"
                            : "填写地址后点「连接」— 不会启动本地后端"
                    )
                }
            } else if model.metaLoadedURL != nil, !model.isLoadingMeta {
                compactStatus(
                    icon: "checkmark.circle.fill",
                    color: Color(hex: "22c55e"),
                    text: model.locale == .enUS ? "Local backend ready" : "本机服务已就绪，请登录"
                )
            }
        }
    }

    private func compactStatus(icon: String, color: Color, text: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LoginPalette.muted(dark))
                Spacer(minLength: 0)
            }
            if let detail = detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "ef4444").opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 2)
        .transition(.opacity)
    }

    // MARK: - Login / Register

    private var loginFields: some View {
        VStack(alignment: .leading, spacing: 17) {
            LoginField(
                title: model.locale == .enUS ? "Username" : "用户名",
                placeholder: model.locale == .enUS ? "Enter username" : "请输入用户名",
                text: $model.username,
                dark: dark,
                enabled: formReady && !model.isLoadingMeta,
                onCommit: onLogin,
                shakeToken: model.shakeUsername
            )
            LoginField(
                title: model.locale == .enUS ? "Password" : "密码",
                placeholder: model.locale == .enUS ? "Enter password" : "请输入密码",
                text: $model.password,
                secure: true,
                dark: dark,
                enabled: formReady && !model.isLoadingMeta,
                onCommit: onLogin,
                shakeToken: model.shakePassword,
                isFocusedOut: $model.passwordFocused
            )

            if model.showVerifyChoice {
                verifyChoice
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if model.showMessageCode {
                messageCodeRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if model.showMfaCode {
                LoginField(
                    title: model.locale == .enUS ? "MFA code" : "MFA 验证码",
                    placeholder: model.locale == .enUS ? "6-digit code" : "6 位动态码",
                    text: $model.mfaCode,
                    dark: dark,
                    enabled: formReady && !model.isLoadingMeta,
                    onCommit: onLogin,
                    shakeToken: model.shakeMfa
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            metaRow
                .padding(.top, 2)
                .padding(.bottom, 6)

            LoginPillButton(
                title: loginButtonTitle,
                loading: model.isSubmitting,
                enabled: model.canAttemptLogin(backendReady: formReady),
                dark: dark,
                action: onLogin
            )

            if model.githubEnabled || model.googleEnabled {
                oauthRow
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.showMessageCode)
        .animation(.easeInOut(duration: 0.22), value: model.showMfaCode)
        .animation(.easeInOut(duration: 0.22), value: model.showVerifyChoice)
        .animation(.easeInOut(duration: 0.22), value: model.githubEnabled || model.googleEnabled)
    }

    private var loginButtonTitle: String {
        if model.isSubmitting {
            return model.locale == .enUS ? "Signing in…" : "登录中…"
        }
        return model.locale == .enUS ? "Sign in" : "登录"
    }

    private var registerFields: some View {
        VStack(alignment: .leading, spacing: 17) {
            LoginField(
                title: model.locale == .enUS ? "Username" : "用户名",
                placeholder: model.locale == .enUS ? "Enter username" : "请输入用户名",
                text: $model.username,
                dark: dark,
                enabled: formReady && !model.isLoadingMeta,
                shakeToken: model.shakeUsername
            )
            LoginField(
                title: model.locale == .enUS ? "Password" : "密码",
                placeholder: model.locale == .enUS ? "Enter password" : "请输入密码",
                text: $model.password,
                secure: true,
                dark: dark,
                enabled: formReady && !model.isLoadingMeta,
                shakeToken: model.shakePassword,
                isFocusedOut: $model.passwordFocused
            )
            LoginField(
                title: model.locale == .enUS ? "Confirm password" : "确认密码",
                placeholder: model.locale == .enUS ? "Repeat password" : "再次输入密码",
                text: $model.confirmPassword,
                secure: true,
                dark: dark,
                enabled: formReady && !model.isLoadingMeta,
                onCommit: onRegister,
                shakeToken: model.shakeConfirm,
                isFocusedOut: $model.passwordFocused
            )
            LoginPillButton(
                title: model.isSubmitting
                    ? (model.locale == .enUS ? "Registering…" : "注册中…")
                    : (model.locale == .enUS ? "Register" : "注册"),
                loading: model.isSubmitting,
                enabled: model.canAttemptRegister(backendReady: formReady),
                dark: dark,
                action: onRegister
            )
            .padding(.top, 8)
        }
    }

    private var verifyChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.locale == .enUS ? "Verification" : "验证方式")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LoginPalette.text(dark))
            HStack(spacing: 8) {
                tabBtn(model.locale == .enUS ? "Message code" : "消息验证码",
                       selected: model.verifyMethod == .message) {
                    model.verifyMethod = .message
                    model.mfaCode = ""
                }
                tabBtn("MFA", selected: model.verifyMethod == .mfa) {
                    model.verifyMethod = .mfa
                    model.verificationCode = ""
                }
                Spacer()
            }
        }
    }

    private var messageCodeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.locale == .enUS ? "Verification code" : "验证码")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LoginPalette.text(dark))
            HStack(alignment: .center, spacing: 8) {
                LoginField(
                    title: "",
                    placeholder: model.locale == .enUS ? "Code" : "消息验证码",
                    text: $model.verificationCode,
                    dark: dark,
                    enabled: formReady && !model.isLoadingMeta,
                    onCommit: onLogin,
                    shakeToken: model.shakeVerify
                )
                LoginFieldActionButton(
                    title: model.codeCountdown > 0
                        ? "\(model.codeCountdown)s"
                        : (model.isSendingCode
                           ? (model.locale == .enUS ? "Sending" : "发送中")
                           : (model.locale == .enUS ? "Send code" : "发送验证码")),
                    loading: model.isSendingCode,
                    enabled: formReady
                        && !model.isLoadingMeta
                        && model.codeCountdown == 0
                        && !model.username.trimmingCharacters(in: .whitespaces).isEmpty,
                    dark: dark,
                    minWidth: 100,
                    action: onSendCode
                )
            }
        }
        .padding(.bottom, 6)
    }

    private var metaRow: some View {
        HStack {
            Button(action: { model.rememberMe.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: model.rememberMe ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundColor(model.rememberMe ? LoginPalette.primary(dark) : LoginPalette.muted(dark))
                    Text(model.locale == .enUS ? "Remember me" : "记住我")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(LoginPalette.text(dark))
                }
            }
            .buttonStyle(PlainButtonStyle())
            Spacer()
            Button(action: onForgotPassword) {
                Text(model.locale == .enUS ? "Forgot password?" : "忘记密码？")
                    .font(.system(size: 14))
                    .foregroundColor(LoginPalette.muted(dark))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var oauthRow: some View {
        HStack(spacing: 16) {
            if model.githubEnabled {
                LoginPillButton(title: "GitHub", dark: dark, secondary: true) {
                    onOAuth("github")
                }
            }
            if model.googleEnabled {
                LoginPillButton(title: "Google", dark: dark, secondary: true) {
                    onOAuth("google")
                }
            }
        }
    }
}
