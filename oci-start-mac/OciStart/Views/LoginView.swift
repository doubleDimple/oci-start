import SwiftUI

// MARK: - Underline TextField style (matches web login_user.css)
struct UnderlineFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var scheme
    func _body(configuration: TextField<Self._Label>) -> some View {
        VStack(spacing: 0) {
            configuration
                .font(.system(size: 16))
                .foregroundColor(scheme == .dark ? Color(hex: "cdd9e5") : Color(hex: "111827"))
                .padding(.bottom, 10)
            Rectangle()
                .fill(scheme == .dark ? Color(hex: "31363d") : Color(hex: "D1D5DB"))
                .frame(height: 1)
        }
        .background(Color.clear)
    }
}

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

    @State private var messageEnabled = false
    @State private var mfaEnabled = false

    var needsCode: Bool { messageEnabled || mfaEnabled }

    // Colors matching the web
    private var bgColor: Color { scheme == .dark ? Color(hex: "1a1d21") : Color(hex: "ECEEF2") }
    private var cardColor: Color { scheme == .dark ? Color(hex: "22262b") : Color.white }
    private var textColor: Color { scheme == .dark ? Color(hex: "cdd9e5") : Color(hex: "111827") }
    private var mutedColor: Color { scheme == .dark ? Color(hex: "768390") : Color(hex: "6B7280") }
    private var accentBtnBg: Color { scheme == .dark ? Color(hex: "4d9eff") : Color(hex: "111827") }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Brand ──
                HStack(alignment: .center, spacing: 12) {
                    // Badge
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(scheme == .dark ? Color(hex: "4d9eff") : Color(hex: "111827"))
                            .frame(width: 38, height: 38)
                        Text("OS")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OCI-START")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(textColor)
                            .tracking(0.4)
                        Text("Welcome back")
                            .font(.system(size: 12))
                            .foregroundColor(mutedColor)
                    }
                    Spacer()
                }
                .padding(.top, 32)
                .padding(.bottom, 28)
                .padding(.horizontal, 44)

                // ── Form ──
                VStack(spacing: 0) {
                    // Username
                    VStack(alignment: .leading, spacing: 10) {
                        Text("用户名")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textColor)
                        TextField("请输入用户名", text: $username)
                            .textFieldStyle(UnderlineFieldStyle())
                            .disabled(isLoading)
                    }
                    .padding(.bottom, 22)

                    // Password
                    VStack(alignment: .leading, spacing: 10) {
                        Text("密码")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textColor)
                        SecureField("请输入密码", text: $password)
                            .textFieldStyle(UnderlineFieldStyle())
                            .disabled(isLoading)
                    }
                    .padding(.bottom, 22)

                    // Message verification code
                    if messageEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("消息验证码")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(textColor)
                            HStack(spacing: 10) {
                                TextField("请输入验证码", text: $verificationCode)
                                    .textFieldStyle(UnderlineFieldStyle())
                                    .disabled(isLoading)
                                Button(action: { Task { await sendCode() } }) {
                                    Text(isSendingCode ? "发送中…" : "发送")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(accentBtnBg)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSendingCode || username.isEmpty)
                                .frame(width: 50)
                            }
                        }
                        .padding(.bottom, 22)
                    }

                    // MFA code
                    if mfaEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MFA 验证码")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(textColor)
                            TextField("6 位验证码", text: $mfaCode)
                                .textFieldStyle(UnderlineFieldStyle())
                                .disabled(isLoading)
                        }
                        .padding(.bottom, 22)
                    }

                    // Error
                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                    }

                    // Login button
                    Button(action: { Task { await doLogin() } }) {
                        ZStack {
                            Capsule().fill(accentBtnBg)
                            if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.7)
                                        .colorScheme(.dark)
                                    Text("登录中…").foregroundColor(.white)
                                        .font(.system(size: 15, weight: .semibold))
                                }
                            } else {
                                Text("登 录").foregroundColor(.white)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || username.isEmpty || password.isEmpty)
                    .keyboardShortcut(.return)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 44)

                Spacer()

                // ── Footer: server URL ──
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 10))
                        .foregroundColor(mutedColor)
                    Text(appState.serverURL)
                        .font(.system(size: 11))
                        .foregroundColor(mutedColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("更改") { showServerConfig = true }
                        .font(.system(size: 11))
                        .foregroundColor(accentBtnBg)
                        .buttonStyle(.plain)
                }
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 440, height: needsCode ? 480 : 400)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 30, y: 10)
        .sheet(isPresented: $showServerConfig) {
            ServerConfigSheet().environmentObject(appState)
        }
        .onAppear { Task { await loadConfig() } }
    }

    // MARK: - Actions

    private func loadConfig() async {
        guard let (msg, mfa) = try? await appState.network.fetchLoginConfig(baseURL: appState.serverURL) else { return }
        messageEnabled = msg
        mfaEnabled     = mfa
    }

    private func sendCode() async {
        isSendingCode = true
        defer { isSendingCode = false }
        do {
            try await appState.network.sendVerificationCode(baseURL: appState.serverURL, username: username)
            appState.showToast("验证码已发送")
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
        }
    }

    private func doLogin() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let vc = messageEnabled && !verificationCode.isEmpty ? verificationCode : nil
            let mc = mfaEnabled     && !mfaCode.isEmpty          ? mfaCode          : nil
            try await appState.login(username: username, password: password,
                                     verificationCode: vc, mfaCode: mc)
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Server config sheet

struct ServerConfigSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.colorScheme) private var scheme
    @State private var url = ""

    private var textColor: Color { scheme == .dark ? Color(hex: "cdd9e5") : Color(hex: "111827") }
    private var mutedColor: Color { scheme == .dark ? Color(hex: "768390") : Color(hex: "6B7280") }
    private var accentBtnBg: Color { scheme == .dark ? Color(hex: "4d9eff") : Color(hex: "111827") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服务器地址")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(textColor)
            TextField("http://host:9856", text: $url)
                .textFieldStyle(.roundedBorder)
            Text("本地部署默认端口 9856，例如：http://192.168.1.10:9856")
                .font(.caption)
                .foregroundColor(mutedColor)
            HStack {
                Spacer()
                Button("取消") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.escape)
                    .foregroundColor(mutedColor)
                Button("保存") { save() }
                    .buttonStyle(ProminentButton())
                    .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { url = appState.serverURL }
    }

    private func save() {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { appState.serverURL = t }
        presentationMode.wrappedValue.dismiss()
    }
}

