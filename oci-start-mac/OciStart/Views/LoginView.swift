import SwiftUI

// MARK: - Underline TextField (matches web login)

struct UnderlineFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var scheme
    var isError: Bool = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        VStack(spacing: 0) {
            configuration
                .font(.system(size: 16))
                .foregroundColor(AppTheme.text(scheme))
                .padding(.bottom, 10)
            Rectangle()
                .fill(isError ? AppTheme.danger : AppTheme.line(scheme))
                .frame(height: 1)
        }
        .background(Color.clear)
    }
}

// MARK: - Login

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var mfaCode = ""
    @State private var isLoading = false
    @State private var isSendingCode = false
    @State private var errorMessage: String?
    @State private var showServerConfig = false
    @State private var appeared = false

    @State private var messageEnabled = false
    @State private var mfaEnabled = false

    // Shake triggers (increment to fire animation)
    @State private var shakeUser = 0
    @State private var shakePass = 0
    @State private var shakeCode = 0
    @State private var shakeMfa = 0
    @State private var heroCry = false

    var needsCode: Bool { messageEnabled || mfaEnabled }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 900
            ZStack {
                AppTheme.loginOuterBg(scheme).ignoresSafeArea()

                Group {
                    if wide {
                        dualPanel
                            .frame(width: min(1100, geo.size.width - 48),
                                   height: min(720, geo.size.height - 48))
                    } else {
                        formOnlyCard
                            .frame(width: min(440, geo.size.width - 32),
                                   height: min(needsCode ? 520 : 440, geo.size.height - 32))
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            Task { await loadConfig() }
        }
        .sheet(isPresented: $showServerConfig) {
            ServerConfigSheet().environmentObject(appState)
        }
    }

    // MARK: Dual panel (wide)

    private var dualPanel: some View {
        HStack(spacing: 0) {
            LoginHeroPanel(isCrying: heroCry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.panel(scheme))

            formColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface(scheme))
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.14), radius: 30, y: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.border(scheme).opacity(0.5), lineWidth: 1)
        )
    }

    private var formOnlyCard: some View {
        formColumn
            .background(AppTheme.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 24, y: 10)
    }

    // MARK: Form column

    private var formColumn: some View {
        VStack(spacing: 0) {
            brandHeader
            formFields
            Spacer(minLength: 8)
            serverFooter
        }
        .padding(.horizontal, 44)
        .padding(.top, 36)
        .padding(.bottom, 20)
    }

    private var brandHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(scheme == .dark ? AppTheme.accent(scheme) : Color(hex: "111827"))
                    .frame(width: 38, height: 38)
                Text("OS")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("OCI-START")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(AppTheme.text(scheme))
                    .tracking(0.4)
                Text("Welcome back")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.muted(scheme))
            }
            Spacer()
        }
        .padding(.bottom, 28)
    }

    private var formFields: some View {
        VStack(spacing: 0) {
            fieldBlock(title: "用户名", shake: shakeUser) {
                TextField("请输入用户名", text: $username)
                    .textFieldStyle(UnderlineFieldStyle())
                    .disabled(isLoading)
            }
            .padding(.bottom, 22)

            fieldBlock(title: "密码", shake: shakePass) {
                SecureField("请输入密码", text: $password)
                    .textFieldStyle(UnderlineFieldStyle())
                    .disabled(isLoading)
            }
            .padding(.bottom, 22)

            if messageEnabled {
                fieldBlock(title: "消息验证码", shake: shakeCode) {
                    HStack(spacing: 10) {
                        TextField("请输入验证码", text: $verificationCode)
                            .textFieldStyle(UnderlineFieldStyle())
                            .disabled(isLoading)
                        Button(action: { Task { await sendCode() } }) {
                            Text(isSendingCode ? "发送中…" : "发送")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.accentButton(scheme))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSendingCode || username.isEmpty)
                        .frame(width: 50)
                    }
                }
                .padding(.bottom, 22)
            }

            if mfaEnabled {
                fieldBlock(title: "MFA 验证码", shake: shakeMfa) {
                    TextField("6 位验证码", text: $mfaCode)
                        .textFieldStyle(UnderlineFieldStyle())
                        .disabled(isLoading)
                }
                .padding(.bottom, 22)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(AppTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: { Task { await doLogin() } }) {
                ZStack {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("登录中…")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                    } else {
                        Text("登 录")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(AppTheme.accentButton(scheme).opacity(isLoading ? 0.7 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .keyboardShortcut(.return)
            .padding(.bottom, 8)
        }
    }

    private func fieldBlock<Content: View>(title: String, shake: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.text(scheme))
            content()
                .shake(trigger: shake)
        }
    }

    private var serverFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "server.rack")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.muted(scheme))
            Text(appState.serverURL)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.muted(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
            Button("更改") { showServerConfig = true }
                .font(.system(size: 11))
                .foregroundColor(AppTheme.accentButton(scheme))
                .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    // MARK: - Actions

    private func loadConfig() async {
        guard let (msg, mfa) = try? await appState.network.fetchLoginConfig(baseURL: appState.serverURL) else { return }
        messageEnabled = msg
        mfaEnabled = mfa
    }

    private func sendCode() async {
        isSendingCode = true
        defer { isSendingCode = false }
        do {
            try await appState.network.sendVerificationCode(baseURL: appState.serverURL, username: username)
            appState.showToast("验证码已发送")
        } catch {
            withAnimation { errorMessage = "发送失败：\(error.localizedDescription)" }
        }
    }

    private func doLogin() async {
        guard !isLoading else { return }

        // Empty-field shake — no error dialog (matches web)
        var hasEmpty = false
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shakeUser += 1
            hasEmpty = true
        }
        if password.isEmpty {
            shakePass += 1
            hasEmpty = true
        }
        if messageEnabled && verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shakeCode += 1
            hasEmpty = true
        }
        if mfaEnabled && mfaCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shakeMfa += 1
            hasEmpty = true
        }
        if hasEmpty { return }

        isLoading = true
        errorMessage = nil
        heroCry = false
        defer { isLoading = false }

        do {
            let vc = messageEnabled && !verificationCode.isEmpty ? verificationCode : nil
            let mc = mfaEnabled && !mfaCode.isEmpty ? mfaCode : nil
            try await appState.login(username: username, password: password,
                                     verificationCode: vc, mfaCode: mc)
        } catch {
            withAnimation {
                errorMessage = error.localizedDescription
                heroCry = true
            }
            // Auto-recover hero after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
                withAnimation { heroCry = false }
            }
        }
    }
}

// MARK: - Hero panel (native SwiftUI, web-inspired characters)

struct LoginHeroPanel: View {
    var isCrying: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var blink = false

    var body: some View {
        ZStack {
            // Soft blobs
            Circle()
                .fill(Color(hex: "5B3DF6").opacity(scheme == .dark ? 0.18 : 0.12))
                .frame(width: 220, height: 220)
                .offset(x: -80, y: -100)
            Circle()
                .fill(Color(hex: "FF7A3B").opacity(scheme == .dark ? 0.14 : 0.10))
                .frame(width: 180, height: 180)
                .offset(x: 100, y: 80)

            VStack(spacing: 18) {
                HStack(alignment: .bottom, spacing: 14) {
                    heroCapsule(color: Color(hex: "5B3DF6"), width: 72, height: 120, smile: true)
                    heroCapsule(color: Color(hex: "111827"), width: 48, height: 100, smile: false, lightEyes: true)
                    heroCapsule(color: Color(hex: "F4C21A"), width: 64, height: 110, smile: true)
                }
                heroBlob
                Text("oci-start")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(AppTheme.muted(scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.surface(scheme).opacity(0.7)))
            }
            .scaleEffect(isCrying ? 0.98 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isCrying)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.12).delay(2.4).repeatForever(autoreverses: true)) {
                blink = true
            }
        }
    }

    private func heroCapsule(color: Color, width: CGFloat, height: CGFloat, smile: Bool, lightEyes: Bool = false) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.35, style: .continuous)
                .fill(color)
                .frame(width: width, height: height)
            VStack(spacing: 8) {
                HStack(spacing: width * 0.12) {
                    eye(size: width * 0.18, light: lightEyes)
                    eye(size: width * 0.18, light: lightEyes)
                }
                mouth(width: width * 0.42, light: lightEyes)
            }
            .offset(y: -height * 0.08)
        }
    }

    private var heroBlob: some View {
        ZStack {
            Capsule()
                .fill(Color(hex: "FF7A3B"))
                .frame(width: 160, height: 70)
            VStack(spacing: 6) {
                HStack(spacing: 16) {
                    eye(size: 14, light: false)
                    eye(size: 14, light: false)
                }
                mouth(width: 36, light: false)
            }
        }
    }

    private func eye(size: CGFloat, light: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: size, height: blink ? size * 0.15 : size)
            if !blink {
                Circle()
                    .fill(Color(hex: "111827"))
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(y: isCrying ? size * 0.18 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isCrying)
    }

    private func mouth(width: CGFloat, light: Bool) -> some View {
        Group {
            if isCrying {
                // Frown
                Capsule()
                    .stroke(light ? Color.white.opacity(0.85) : Color(hex: "111827"), lineWidth: 3)
                    .frame(width: width, height: 10)
                    .rotationEffect(.degrees(180))
                    .clipShape(Rectangle().offset(y: -4))
            } else {
                Capsule()
                    .fill(light ? Color.white.opacity(0.55) : Color(hex: "111827"))
                    .frame(width: width, height: 4)
            }
        }
    }
}

// MARK: - Server config sheet

struct ServerConfigSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.colorScheme) private var scheme
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服务器地址")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(AppTheme.text(scheme))
            TextField("http://host:9856", text: $url)
                .textFieldStyle(.roundedBorder)
            Text("本地部署默认端口 9856。内嵌后端启动后为 http://localhost:9856")
                .font(.caption)
                .foregroundColor(AppTheme.muted(scheme))
            HStack {
                Spacer()
                Button("取消") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.escape)
                    .foregroundColor(AppTheme.muted(scheme))
                Button("保存") { save() }
                    .buttonStyle(ProminentButton())
                    .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { url = appState.serverURL }
    }

    private func save() {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { appState.serverURL = t }
        presentationMode.wrappedValue.dismiss()
    }
}
