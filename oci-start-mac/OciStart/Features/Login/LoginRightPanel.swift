import SwiftUI
import AppKit

/// Right form panel — structure mirrors web `.form-panel .login-card`.
struct LoginRightPanel: View {
    @ObservedObject var model: LoginFormModel
    var dark: Bool
    @ObservedObject var backend: BackendController
    var onLogin: () -> Void
    var onRegister: () -> Void
    var onSendCode: () -> Void
    var onOAuth: (String) -> Void
    var onServerCommit: () -> Void = {}
    var onForgotPassword: () -> Void = {}
    var onLocale: (AppLocale) -> Void = { _ in }

    private var formReady: Bool {
        if model.isRemoteServer { return true }
        return backend.isReadyForLogin
    }

    /// Local backend still starting — full panel becomes a minimal spinner.
    private var showBootLoading: Bool {
        guard !model.isRemoteServer else { return false }
        switch backend.state {
        case .idle, .starting: return true
        default: return false
        }
    }

    private var localBootFailed: String? {
        guard !model.isRemoteServer else { return nil }
        if case .failed(let m) = backend.state { return m }
        return nil
    }

    var body: some View {
        ZStack {
            if showBootLoading {
                bootLoadingView
                    .transition(.opacity)
            } else if let fail = localBootFailed {
                bootFailedView(fail)
                    .transition(.opacity)
            } else {
                formScroll
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.28), value: showBootLoading)
        .animation(.easeInOut(duration: 0.28), value: localBootFailed != nil)
        .background(Color.clear)
    }

    // MARK: - Minimal boot states

    private var bootLoadingView: some View {
        VStack(spacing: 0) {
            topChipBar
                .padding(.horizontal, 56)
                .padding(.top, 48)
            Spacer(minLength: 0)
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.55)
            Spacer(minLength: 0)
            // Balance top chrome so spinner sits optical center
            Color.clear.frame(height: 48 + 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bootFailedView(_ message: String) -> some View {
        VStack(spacing: 0) {
            topChipBar
                .padding(.horizontal, 56)
                .padding(.top, 48)
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color(hex: "f59e0b"))
                Text(model.locale == .enUS ? "Service failed to start" : "服务启动失败")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(LoginPalette.text(dark))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(LoginPalette.muted(dark))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(.horizontal, 56)
            Spacer(minLength: 0)
            Color.clear.frame(height: 48 + 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Form

    private var formScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topChipBar
                    .padding(.bottom, 28)

                brand
                    .padding(.bottom, 34)

                if model.allowRegister {
                    tabs
                        .padding(.bottom, 26)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if model.showServer {
                    serverRow
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                statusStrip
                    .padding(.bottom, 14)

                ZStack {
                    Group {
                        if model.tab == .login {
                            loginFields
                        } else {
                            registerFields
                        }
                    }
                    .opacity(model.isLoadingMeta ? 0.45 : 1)
                    .allowsHitTesting(!model.isLoadingMeta)
                    .animation(.easeOut(duration: 0.2), value: model.isLoadingMeta)

                    if model.isLoadingMeta {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.05)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: model.isLoadingMeta)

                if let e = model.errorText {
                    Text(e)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "ef4444"))
                        .padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                if let info = model.infoText {
                    Text(info)
                        .font(.system(size: 13))
                        .foregroundColor(LoginPalette.muted(dark))
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 48)
            .padding(.bottom, 40)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.easeInOut(duration: 0.22), value: model.showServer)
            .animation(.easeInOut(duration: 0.22), value: model.allowRegister)
            .animation(.easeInOut(duration: 0.22), value: model.tab)
            .animation(.easeInOut(duration: 0.2), value: model.errorText)
            .animation(.easeInOut(duration: 0.2), value: model.infoText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top: locale + server

    private var topChipBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                langItem(.zhCN, "中文")
                Text("|")
                    .font(.system(size: 12))
                    .foregroundColor(LoginPalette.line(dark))
                    .padding(.horizontal, 6)
                langItem(.enUS, "English")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(LoginPalette.chipBg(dark))
            .cornerRadius(999)
            .shadow(color: Color.black.opacity(dark ? 0.3 : 0.08), radius: 10, y: 4)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    model.showServer.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LoginPalette.muted(dark))
                    Text(model.showServer
                         ? (model.locale == .enUS ? "Hide server" : "收起服务器")
                         : (model.locale == .enUS ? "Server" : "服务器"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(LoginPalette.muted(dark))
                    if model.isRemoteServer {
                        Circle()
                            .fill(Color(hex: "22c55e"))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LoginPalette.chipBg(dark))
                .cornerRadius(999)
                .shadow(color: Color.black.opacity(dark ? 0.3 : 0.08), radius: 10, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func langItem(_ loc: AppLocale, _ title: String) -> some View {
        let active = model.locale == loc
        return Button(action: {
            model.locale = loc
            onLocale(loc)
        }) {
            Text(title)
                .font(.system(size: 13, weight: active ? .bold : .regular))
                .foregroundColor(active ? LoginPalette.text(dark) : LoginPalette.muted(dark))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var brand: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LoginPalette.primary(dark))
                    .frame(width: 38, height: 38)
                Text("OS")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .tracking(0.4)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("OCI-START")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(LoginPalette.text(dark))
                    .tracking(0.2)
                Text(model.locale == .enUS ? "Welcome back" : "欢迎回来")
                    .font(.system(size: 13))
                    .foregroundColor(LoginPalette.muted(dark))
                    .tracking(0.2)
            }
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
                .font(.system(size: 14, weight: selected ? .bold : .medium))
                .foregroundColor(selected ? LoginPalette.tabActiveText(dark) : LoginPalette.text(dark))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selected ? LoginPalette.tabActiveBg(dark) : Color.clear)
                .cornerRadius(999)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Server URL + Connect — title shared, field and button same box height.
    private var serverRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.locale == .enUS ? "Server" : "服务器地址")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(LoginPalette.text(dark))
            HStack(alignment: .center, spacing: 12) {
                LoginField(
                    title: "",
                    placeholder: "http://localhost:9856",
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
                    enabled: !model.serverURL.trimmingCharacters(in: .whitespaces).isEmpty,
                    dark: dark,
                    minWidth: 96,
                    action: onServerCommit
                )
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Compact status (no heavy cards that jump)

    @ViewBuilder
    private var statusStrip: some View {
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
                        ? "Tap Connect to load login options"
                        : "填写地址后点「连接」加载登录配置"
                )
            }
            // loading: spinner overlay on form — no extra strip
        } else if model.metaLoadedURL != nil, !model.isLoadingMeta {
            compactStatus(
                icon: "checkmark.circle.fill",
                color: Color(hex: "22c55e"),
                text: model.locale == .enUS ? "Ready to sign in" : "服务已就绪，请登录"
            )
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
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "ef4444").opacity(0.85))
                    .lineLimit(2)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 2)
        .transition(.opacity)
    }

    // MARK: - Login / Register

    private var loginFields: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                .padding(.bottom, 14)

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
        VStack(alignment: .leading, spacing: 18) {
            LoginField(
                title: model.locale == .enUS ? "Username" : "用户名",
                placeholder: "请输入用户名",
                text: $model.username,
                dark: dark,
                enabled: formReady && !model.isLoadingMeta,
                shakeToken: model.shakeUsername
            )
            LoginField(
                title: model.locale == .enUS ? "Password" : "密码",
                placeholder: "请输入密码",
                text: $model.password,
                secure: true,
                dark: dark,
                enabled: formReady && !model.isLoadingMeta,
                shakeToken: model.shakePassword,
                isFocusedOut: $model.passwordFocused
            )
            LoginField(
                title: model.locale == .enUS ? "Confirm password" : "确认密码",
                placeholder: "再次输入密码",
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
                .font(.system(size: 15, weight: .heavy))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(LoginPalette.text(dark))
            HStack(alignment: .center, spacing: 12) {
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
                    minWidth: 118,
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
                        .font(.system(size: 14, weight: .bold))
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
