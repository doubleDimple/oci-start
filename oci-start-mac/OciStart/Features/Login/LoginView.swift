import SwiftUI
import AppKit

/// Full Web-parity login page (`login_user.ftl` auth-shell + aurora).
struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var backend: BackendController
    @EnvironmentObject private var appearance: AppearanceController

    @StateObject private var model = LoginFormModel()
    @State private var countdownTask: Task<Void, Never>?
    @State private var resetCountdownTask: Task<Void, Never>?

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        ZStack {
            auroraBackground

            GeometryReader { geo in
                let w = min(1240, max(920, geo.size.width - 48))
                let h = min(760, max(640, geo.size.height - 48))

                HStack(spacing: 0) {
                    LoginHeroView(
                        dark: dark,
                        crying: model.cryHero,
                        shyMode: model.passwordFocused
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Rectangle()
                        .fill(LoginPalette.divider(dark))
                        .frame(width: 1)

                    LoginRightPanel(
                        model: model,
                        dark: dark,
                        backend: backend,
                        onLogin: { Task { await doLogin() } },
                        onRegister: { Task { await doRegister() } },
                        onSendCode: { Task { await doSendCode() } },
                        onOAuth: { provider in Task { await doOAuth(provider) } },
                        onServerCommit: { applyServerAndLoadMeta() },
                        onForgotPassword: { model.openForgotPassword() },
                        onLocale: { loc in
                            UserDefaults.standard.set(loc.rawValue, forKey: "appLocale")
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: w, height: h)
                .background(LoginPalette.shellFill(dark))
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(LoginPalette.shellBorder(dark), lineWidth: 1)
                )
                .cornerRadius(26)
                .shadow(color: Color.black.opacity(dark ? 0.55 : 0.14), radius: 30, y: 16)
                .frame(width: geo.size.width, height: geo.size.height)
            }

            if model.showForgotPassword {
                LoginForgotPasswordSheet(
                    model: model,
                    dark: dark,
                    onClose: { model.closeForgotPassword() },
                    onSendCode: { Task { await doResetSendCode() } },
                    onNext: { Task { await doResetNext() } },
                    onBack: {
                        if model.resetStep > 1 {
                            model.resetStep -= 1
                            model.resetMessage = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: model.showForgotPassword)
        .onAppear {
            model.serverURL = session.serverURL
            if !session.username.isEmpty { model.username = session.username }
            if let raw = UserDefaults.standard.string(forKey: "appLocale"),
               let loc = AppLocale(rawValue: raw) {
                model.locale = loc
            }
            if model.isRemoteServer || backend.isReadyForLogin {
                Task { await loadMeta(force: false) }
            }
        }
        .onReceive(backend.$state) { state in
            if case .ready = state, !model.isRemoteServer {
                Task { await loadMeta(force: false) }
            }
        }
        .onDisappear {
            countdownTask?.cancel()
            resetCountdownTask?.cancel()
        }
    }

    // MARK: - Aurora

    private var auroraBackground: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: dark
                    ? [Color(hex: "12151a"), Color(hex: "1a1d21"), Color(hex: "151820")]
                    : [Color(hex: "eef1f6"), Color(hex: "e8ecf3"), Color(hex: "eef2f8")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(hex: dark ? "4d9eff" : "6366f1").opacity(dark ? 0.35 : 0.40))
                .frame(width: 560, height: 560)
                .blur(radius: 64)
                .offset(x: -280, y: -220)
            Circle()
                .fill(Color(hex: dark ? "8b5cf6" : "0ea5e9").opacity(dark ? 0.32 : 0.36))
                .frame(width: 480, height: 480)
                .blur(radius: 64)
                .offset(x: 320, y: -40)
            Circle()
                .fill(Color(hex: dark ? "38bdf8" : "a78bfa").opacity(dark ? 0.22 : 0.28))
                .frame(width: 620, height: 620)
                .blur(radius: 70)
                .offset(x: -40, y: 320)
            Circle()
                .fill(Color(hex: dark ? "22d3ee" : "3b82f6").opacity(dark ? 0.16 : 0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 50)
                .offset(x: 80, y: 40)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.black.opacity(dark ? 0.45 : 0.08)
                ]),
                center: .center,
                startRadius: 80,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Meta

    private func loadMeta(force: Bool) async {
        let raw = await MainActor.run { model.serverURL }
        await MainActor.run { session.serverURL = raw }
        let target = session.serverURL

        if AppSession.isLocalServerURL(target), !backend.isReadyForLogin {
            return
        }

        let skip = await MainActor.run { () -> Bool in
            !force && model.metaLoadedURL == target && !model.isLoadingMeta
        }
        if skip { return }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                model.isLoadingMeta = true
                model.metaError = nil
                model.infoText = nil
                model.errorText = nil
            }
        }

        do {
            let meta = try await session.fetchLoginPageMeta()
            let factors = await session.fetchLoginFactors()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.28)) {
                    model.allowRegister = meta.allowRegister
                    model.githubEnabled = meta.githubEnabled
                    model.googleEnabled = meta.googleEnabled
                    model.messageEnabled = factors.messageEnabled
                    model.mfaEnabled = factors.mfaEnabled
                    if factors.messageEnabled && !factors.mfaEnabled {
                        model.verifyMethod = .message
                    } else if factors.mfaEnabled && !factors.messageEnabled {
                        model.verifyMethod = .mfa
                    }
                    model.metaLoadedURL = target
                    model.isLoadingMeta = false
                    if model.isRemoteServer {
                        model.infoText = model.locale == .enUS ? "Remote server connected" : "已连接远程服务器"
                    }
                }
            }
        } catch {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) {
                    model.isLoadingMeta = false
                    model.metaLoadedURL = nil
                    model.metaError = error.localizedDescription
                    model.allowRegister = false
                    model.githubEnabled = false
                    model.googleEnabled = false
                    model.messageEnabled = false
                    model.mfaEnabled = false
                    if model.isRemoteServer {
                        model.errorText = (model.locale == .enUS ? "Cannot reach server: " : "无法连接远程服务器：")
                            + error.localizedDescription
                    }
                }
            }
        }
    }

    func applyServerAndLoadMeta() {
        // Normalize URL immediately so remote/local mode flips smoothly.
        let raw = model.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            model.serverURL = raw
            session.serverURL = raw
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            model.errorText = nil
            model.infoText = nil
        }
        Task { await loadMeta(force: true) }
    }

    // MARK: - Login / Register

    private func doLogin() async {
        let remote = await MainActor.run { model.isRemoteServer }
        if !remote && !backend.isReadyForLogin {
            await MainActor.run {
                model.errorText = model.locale == .enUS
                    ? "Backend is not ready yet"
                    : "后端尚未就绪，请稍候再试"
            }
            return
        }

        let valid = await MainActor.run { model.validateLoginFields() }
        if !valid {
            return
        }

        await MainActor.run {
            model.errorText = nil
            model.infoText = nil
            model.isSubmitting = true
            model.cryHero = false
            session.serverURL = model.serverURL
        }

        let user = await MainActor.run {
            model.username.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        let pass = await MainActor.run { model.password }
        let remember = await MainActor.run { model.rememberMe }
        let vCode: String? = await MainActor.run {
            if model.showMessageCode && !model.verificationCode.isEmpty {
                return model.verificationCode
            }
            return nil
        }
        let mCode: String? = await MainActor.run {
            if model.showMfaCode && !model.mfaCode.isEmpty {
                return model.mfaCode
            }
            return nil
        }

        do {
            try await session.login(
                username: user,
                password: pass,
                verificationCode: vCode,
                mfaCode: mCode,
                rememberMe: remember
            )
            await MainActor.run { model.isSubmitting = false }
        } catch {
            await MainActor.run {
                model.errorText = error.localizedDescription
                model.isSubmitting = false
                model.cryHero = true
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { model.cryHero = false }
        }
    }

    private func doRegister() async {
        let valid = await MainActor.run { model.validateRegisterFields() }
        if !valid { return }

        await MainActor.run {
            model.errorText = nil
            model.isSubmitting = true
            session.serverURL = model.serverURL
        }
        let pass = await MainActor.run { model.password }
        let confirm = await MainActor.run { model.confirmPassword }
        guard pass == confirm else {
            await MainActor.run {
                model.errorText = model.locale == .enUS
                    ? "Passwords do not match"
                    : "两次输入的密码不一致"
                model.shakeConfirm += 1
                model.shakePassword += 1
                model.isSubmitting = false
            }
            return
        }
        do {
            try await session.registerFirstUser(
                username: model.username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: pass
            )
            await MainActor.run { model.isSubmitting = false }
        } catch {
            await MainActor.run {
                model.errorText = error.localizedDescription
                model.isSubmitting = false
            }
        }
    }

    private func doSendCode() async {
        let user = await MainActor.run {
            model.username.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !user.isEmpty else {
            await MainActor.run {
                model.shakeUsername += 1
                model.errorText = model.locale == .enUS ? "Enter username first" : "请先输入用户名"
            }
            return
        }
        await MainActor.run {
            model.isSendingCode = true
            model.errorText = nil
            model.infoText = nil
            session.serverURL = model.serverURL
        }
        do {
            try await session.sendLoginCode(username: user)
            await MainActor.run {
                model.isSendingCode = false
                model.infoText = model.locale == .enUS ? "Code sent" : "验证码已发送"
                model.codeCountdown = 60
            }
            countdownTask?.cancel()
            countdownTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let next = await MainActor.run { () -> Int in
                        model.codeCountdown = max(0, model.codeCountdown - 1)
                        return model.codeCountdown
                    }
                    if next == 0 { break }
                }
            }
        } catch {
            await MainActor.run {
                model.isSendingCode = false
                model.errorText = error.localizedDescription
            }
        }
    }

    private func doOAuth(_ provider: String) async {
        await MainActor.run {
            model.errorText = nil
            session.serverURL = model.serverURL
        }
        do {
            let url = try await APIClient.shared.oauthLoginURL(baseURL: session.serverURL, provider: provider)
            await MainActor.run {
                NSWorkspace.shared.open(url)
                model.infoText = model.locale == .enUS
                    ? "Opened \(provider) in browser — finish login there"
                    : "已在浏览器打开 \(provider) 登录，完成后回到客户端"
            }
        } catch {
            await MainActor.run {
                model.errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Forgot password

    private func doResetSendCode() async {
        let user = await MainActor.run {
            model.resetUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !user.isEmpty else {
            await MainActor.run {
                model.resetMessage = model.locale == .enUS ? "Enter username" : "请输入用户名"
                model.resetMessageIsError = true
            }
            return
        }
        await MainActor.run {
            model.resetSendingCode = true
            model.resetMessage = nil
            session.serverURL = model.serverURL
        }
        do {
            try await APIClient.shared.sendResetCode(baseURL: session.serverURL, username: user)
            await MainActor.run {
                model.resetSendingCode = false
                model.resetMessage = model.locale == .enUS
                    ? "Code sent to your device"
                    : "验证码已发送到您的设备"
                model.resetMessageIsError = false
                model.resetCodeCountdown = 60
            }
            resetCountdownTask?.cancel()
            resetCountdownTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let next = await MainActor.run { () -> Int in
                        model.resetCodeCountdown = max(0, model.resetCodeCountdown - 1)
                        return model.resetCodeCountdown
                    }
                    if next == 0 { break }
                }
            }
        } catch {
            await MainActor.run {
                model.resetSendingCode = false
                model.resetMessage = error.localizedDescription
                model.resetMessageIsError = true
            }
        }
    }

    private func doResetNext() async {
        let step = await MainActor.run { model.resetStep }
        if step == 1 {
            await verifyResetIdentity()
        } else if step == 2 {
            await executePasswordReset()
        }
    }

    private func verifyResetIdentity() async {
        let user = await MainActor.run {
            model.resetUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let code = await MainActor.run {
            model.resetCode.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !user.isEmpty else {
            await MainActor.run {
                model.resetMessage = "请输入用户名"
                model.resetMessageIsError = true
            }
            return
        }
        guard !code.isEmpty else {
            await MainActor.run {
                model.resetMessage = "请输入验证码"
                model.resetMessageIsError = true
            }
            return
        }
        await MainActor.run {
            model.resetBusy = true
            model.resetMessage = nil
            session.serverURL = model.serverURL
        }
        do {
            let token = try await APIClient.shared.verifyResetCode(
                baseURL: session.serverURL,
                username: user,
                verificationCode: code
            )
            await MainActor.run {
                model.resetToken = token
                model.resetStep = 2
                model.resetBusy = false
                model.resetMessage = "身份验证成功"
                model.resetMessageIsError = false
            }
        } catch {
            await MainActor.run {
                model.resetBusy = false
                model.resetMessage = error.localizedDescription
                model.resetMessageIsError = true
            }
        }
    }

    private func executePasswordReset() async {
        let user = await MainActor.run {
            model.resetUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let token = await MainActor.run { model.resetToken }
        guard let token = token, !token.isEmpty else {
            await MainActor.run {
                model.resetMessage = "验证已失效，请重新开始"
                model.resetMessageIsError = true
                model.resetStep = 1
            }
            return
        }
        await MainActor.run {
            model.resetBusy = true
            model.resetMessage = nil
        }
        do {
            let msg = try await APIClient.shared.resetPassword(
                baseURL: session.serverURL,
                username: user,
                resetToken: token
            )
            await MainActor.run {
                model.resetStep = 3
                model.resetBusy = false
                model.resetToken = nil
                model.resetSuccessDetail = msg
                model.resetMessage = nil
                model.username = user
            }
        } catch {
            await MainActor.run {
                model.resetBusy = false
                model.resetMessage = error.localizedDescription
                model.resetMessageIsError = true
            }
        }
    }
}
