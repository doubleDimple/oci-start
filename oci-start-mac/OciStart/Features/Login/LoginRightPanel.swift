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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topChipBar
                    .padding(.bottom, 28)

                brand
                    .padding(.bottom, 34)

                if model.allowRegister {
                    tabs
                        .padding(.bottom, 26)
                        .disabled(!formReady)
                        .opacity(formReady ? 1 : 0.5)
                }

                if model.showServer {
                    serverRow
                        .padding(.bottom, 8)
                }

                backendStatusBanner
                    .padding(.bottom, 18)

                if model.tab == .login {
                    loginFields
                } else {
                    registerFields
                }

                if let e = model.errorText {
                    Text(e)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "ef4444"))
                        .padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let info = model.infoText {
                    Text(info)
                        .font(.system(size: 13))
                        .foregroundColor(LoginPalette.muted(dark))
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 48)
            .padding(.bottom, 40)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Top: locale (web) + server

    private var topChipBar: some View {
        HStack(spacing: 10) {
            // Language selector — web `.lang-selector`
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

            Button(action: { withAnimation(.easeOut(duration: 0.15)) { model.showServer.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LoginPalette.muted(dark))
                    Text(model.showServer ? "收起服务器" : "服务器")
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
                model.tab = .login
                model.errorText = nil
            }
            tabBtn(model.locale == .enUS ? "Register" : "注册", selected: model.tab == .register) {
                model.tab = .register
                model.errorText = nil
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

    private var serverRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            LoginField(
                title: model.locale == .enUS ? "Server" : "服务器地址",
                placeholder: "http://localhost:9856",
                text: $model.serverURL,
                secure: false,
                dark: dark,
                enabled: true,
                onCommit: onServerCommit
            )
            Button(action: onServerCommit) {
                HStack(spacing: 6) {
                    if model.isLoadingMeta {
                        ProgressView().scaleEffect(0.65)
                    }
                    Text(model.isLoadingMeta
                         ? (model.locale == .enUS ? "…" : "连接中")
                         : (model.locale == .enUS ? "Connect" : "连接"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(LoginPalette.text(dark))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(LoginPalette.oauthBg(dark))
                .cornerRadius(999)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(LoginPalette.oauthBorder(dark), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(model.isLoadingMeta || model.serverURL.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.bottom, 18)
        }
    }

    // MARK: - Status banners

    @ViewBuilder
    private var backendStatusBanner: some View {
        if model.isRemoteServer {
            remoteStatusBanner
        } else {
            localBackendBanner
        }
    }

    @ViewBuilder
    private var remoteStatusBanner: some View {
        if model.isLoadingMeta {
            statusCard(loading: true,
                       title: "正在连接远程服务器…",
                       sub: "加载登录配置（注册 / MFA / OAuth）")
        } else if let err = model.metaError {
            errorCard(title: "远程服务器不可用", detail: err)
        } else if model.metaLoadedURL != nil {
            okLine("远程服务器已就绪，请登录")
        } else {
            okLine("已填写远程地址，请点「连接」加载登录配置", icon: "link", green: false)
        }
    }

    @ViewBuilder
    private var localBackendBanner: some View {
        switch backend.state {
        case .idle, .starting:
            statusCard(loading: true,
                       title: "正在初始化服务…",
                       sub: "服务就绪后即可输入用户名和密码")
        case .failed(let m):
            errorCard(title: "服务启动失败", detail: m)
        case .ready:
            if model.isLoadingMeta {
                okLine("正在加载登录配置…", icon: nil, green: false, loading: true)
            } else {
                okLine("服务已就绪，请登录")
            }
        }
    }

    private func statusCard(loading: Bool, title: String, sub: String) -> some View {
        HStack(spacing: 10) {
            if loading {
                ProgressView().scaleEffect(0.75).frame(width: 16, height: 16)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LoginPalette.text(dark))
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(LoginPalette.muted(dark))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LoginPalette.primary(dark).opacity(dark ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LoginPalette.primary(dark).opacity(0.25), lineWidth: 1)
        )
    }

    private func errorCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "ef4444"))
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "ef4444").opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "ef4444").opacity(0.1))
        .cornerRadius(12)
    }

    private func okLine(_ text: String, icon: String? = "checkmark.circle.fill", green: Bool = true, loading: Bool = false) -> some View {
        HStack(spacing: 8) {
            if loading {
                ProgressView().scaleEffect(0.7)
            } else if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(green ? Color(hex: "22c55e") : LoginPalette.muted(dark))
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(LoginPalette.muted(dark))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Login / Register

    private var loginFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            LoginField(
                title: model.locale == .enUS ? "Username" : "用户名",
                placeholder: formReady
                    ? (model.locale == .enUS ? "Enter username" : "请输入用户名")
                    : (model.locale == .enUS ? "Waiting…" : "等待后端启动…"),
                text: $model.username,
                dark: dark,
                enabled: formReady,
                onCommit: onLogin,
                shakeToken: model.shakeUsername
            )
            LoginField(
                title: model.locale == .enUS ? "Password" : "密码",
                placeholder: formReady
                    ? (model.locale == .enUS ? "Enter password" : "请输入密码")
                    : (model.locale == .enUS ? "Waiting…" : "等待后端启动…"),
                text: $model.password,
                secure: true,
                dark: dark,
                enabled: formReady,
                onCommit: onLogin,
                shakeToken: model.shakePassword,
                isFocusedOut: $model.passwordFocused
            )

            if model.showVerifyChoice {
                verifyChoice
                    .disabled(!formReady)
                    .opacity(formReady ? 1 : 0.45)
            }
            if model.showMessageCode { messageCodeRow }
            if model.showMfaCode {
                LoginField(
                    title: model.locale == .enUS ? "MFA code" : "MFA 验证码",
                    placeholder: model.locale == .enUS ? "6-digit code" : "6 位动态码",
                    text: $model.mfaCode,
                    dark: dark,
                    enabled: formReady,
                    onCommit: onLogin,
                    shakeToken: model.shakeMfa
                )
            }

            metaRow
                .padding(.top, 2)
                .padding(.bottom, 14)
                .disabled(!formReady)
                .opacity(formReady ? 1 : 0.45)

            LoginPillButton(
                title: loginButtonTitle,
                loading: model.isSubmitting || waitingForReady,
                enabled: model.canAttemptLogin(backendReady: formReady),
                dark: dark,
                action: onLogin
            )

            if model.githubEnabled || model.googleEnabled {
                oauthRow
                    .padding(.top, 14)
                    .disabled(!formReady)
                    .opacity(formReady ? 1 : 0.45)
            }
        }
    }

    private var waitingForReady: Bool {
        if model.isRemoteServer { return model.isLoadingMeta }
        switch backend.state {
        case .idle, .starting: return true
        default: return model.isLoadingMeta
        }
    }

    private var loginButtonTitle: String {
        if model.isSubmitting {
            return model.locale == .enUS ? "Signing in…" : "登录中…"
        }
        if model.isRemoteServer && model.isLoadingMeta {
            return model.locale == .enUS ? "Connecting…" : "连接远程中…"
        }
        if !formReady {
            return model.locale == .enUS ? "Waiting…" : "等待后端…"
        }
        if model.isLoadingMeta {
            return model.locale == .enUS ? "Loading…" : "加载配置…"
        }
        return model.locale == .enUS ? "Sign in" : "登录"
    }

    private var registerFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            LoginField(
                title: model.locale == .enUS ? "Username" : "用户名",
                placeholder: formReady ? "请输入用户名" : "等待后端启动…",
                text: $model.username,
                dark: dark,
                enabled: formReady,
                shakeToken: model.shakeUsername
            )
            LoginField(
                title: model.locale == .enUS ? "Password" : "密码",
                placeholder: formReady ? "请输入密码" : "等待后端启动…",
                text: $model.password,
                secure: true,
                dark: dark,
                enabled: formReady,
                shakeToken: model.shakePassword,
                isFocusedOut: $model.passwordFocused
            )
            LoginField(
                title: model.locale == .enUS ? "Confirm password" : "确认密码",
                placeholder: formReady ? "再次输入密码" : "等待后端启动…",
                text: $model.confirmPassword,
                secure: true,
                dark: dark,
                enabled: formReady,
                onCommit: onRegister,
                shakeToken: model.shakeConfirm,
                isFocusedOut: $model.passwordFocused
            )
            LoginPillButton(
                title: model.isSubmitting
                    ? (model.locale == .enUS ? "Registering…" : "注册中…")
                    : (formReady
                       ? (model.locale == .enUS ? "Register" : "注册")
                       : (model.locale == .enUS ? "Waiting…" : "等待后端…")),
                loading: model.isSubmitting || waitingForReady,
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
        VStack(alignment: .leading, spacing: 10) {
            Text(model.locale == .enUS ? "Verification code" : "验证码")
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(LoginPalette.text(dark))
            HStack(alignment: .center, spacing: 12) {
                LoginField(
                    title: "",
                    placeholder: model.locale == .enUS ? "Code" : "消息验证码",
                    text: $model.verificationCode,
                    dark: dark,
                    enabled: formReady,
                    onCommit: onLogin,
                    shakeToken: model.shakeVerify
                )
                Button(action: onSendCode) {
                    Text(model.codeCountdown > 0
                         ? "\(model.codeCountdown)s"
                         : (model.isSendingCode
                            ? (model.locale == .enUS ? "Sending" : "发送中")
                            : (model.locale == .enUS ? "Send code" : "发送验证码")))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(LoginPalette.text(dark))
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(LoginPalette.oauthBg(dark))
                        .cornerRadius(999)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999)
                                .stroke(LoginPalette.oauthBorder(dark), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!formReady || model.isSendingCode || model.codeCountdown > 0 || model.username.isEmpty)
            }
            .disabled(!formReady)
            .opacity(formReady ? 1 : 0.45)
        }
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
            .onHover { _ in }
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
