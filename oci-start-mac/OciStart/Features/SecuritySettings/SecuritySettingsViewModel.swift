import Foundation
import Combine
import AppKit

/// ViewModel for Web `/system/settings` (安全管理).
@MainActor
final class SecuritySettingsViewModel: ObservableObject {

    @Published var currentUsername: String = ""
    @Published var siteLogoName: String = "OCI-START"
    @Published var currentPassword: String = ""
    @Published var newUsername: String = ""
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""

    @Published var github = GithubOAuthForm()
    @Published var google = GoogleOAuthForm()
    @Published var mfa = MfaForm()
    @Published var turnstile = TurnstileForm()
    @Published var channelNotifyEnabled = false

    @Published private(set) var isLoading = false
    @Published private(set) var savingKey: String?
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: SecuritySettingsService { SecuritySettingsService(baseURL: session.serverURL) }

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task { await reload() }
    }

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let snap = try await service.fetchConfigs()
            apply(snap)
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(_ snap: SecuritySettingsSnapshot) {
        currentUsername = snap.currentUsername
        siteLogoName = snap.siteLogoName
        github = snap.github
        google = snap.google
        mfa = snap.mfa
        turnstile = snap.turnstile
        channelNotifyEnabled = snap.channelNotifyEnabled
        currentPassword = ""
        newUsername = ""
        newPassword = ""
        confirmPassword = ""
        if !snap.siteLogoName.isEmpty {
            session.applySiteName(snap.siteLogoName)
        }
        if !snap.currentUsername.isEmpty {
            session.applyRemoteUsername(snap.currentUsername)
        }
    }

    // MARK: - Account

    func saveLogo() {
        Task { await performSaveLogo() }
    }

    private func performSaveLogo() async {
        let name = siteLogoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ToastCenter.shared.error("Logo 名称不能为空")
            return
        }
        guard AppAlert.confirm(title: "保存 Logo", message: "将站点 Logo 名称更新为「\(name)」？") else { return }
        savingKey = "logo"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateLogoName(name)
            }
            session.applySiteName(name)
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Keep MFA verify field to at most 6 digits (align Web input filter).
    func setMfaVerifyCode(_ raw: String) {
        let digits = raw.filter { $0.isNumber }
        mfa.verifyCode = String(digits.prefix(6))
    }

    func copyMfaSecret() {
        let key = mfa.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            ToastCenter.shared.error("暂无 MFA 密钥可复制")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(key, forType: .string)
        AppAlert.info(title: "已复制", message: "MFA 密钥已复制到剪贴板")
    }

    func updateAccount() {
        Task { await performUpdateAccount() }
    }

    private func performUpdateAccount() async {
        let cur = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let nu = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let np = newPassword
        let cp = confirmPassword

        guard !cur.isEmpty else {
            ToastCenter.shared.error("请输入当前密码")
            return
        }
        guard !nu.isEmpty || !np.isEmpty else {
            ToastCenter.shared.error("请至少修改用户名或密码")
            return
        }
        if !np.isEmpty, np != cp {
            ToastCenter.shared.error("两次输入的新密码不一致")
            return
        }
        guard AppAlert.confirm(title: "确认更新", message: "确定保存账号安全修改？") else { return }

        savingKey = "account"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateAccount(
                    currentPassword: cur,
                    newUsername: nu.isEmpty ? nil : nu,
                    newPassword: np.isEmpty ? nil : np
                )
            }
            if !np.isEmpty {
                AppAlert.info(title: "密码已更新", message: "请使用新密码重新登录")
                await session.logout()
            } else {
                if !nu.isEmpty {
                    session.applyRemoteUsername(nu)
                    currentUsername = nu
                }
                newUsername = ""
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - GitHub

    func fetchGithubId() {
        Task { await performFetchGithubId() }
    }

    private func performFetchGithubId() async {
        let name = github.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ToastCenter.shared.error("请输入 GitHub 用户名")
            return
        }
        savingKey = "githubFetch"
        defer { savingKey = nil }
        do {
            let result = try await LoadingHUD.shared.during {
                try await service.fetchGithubUserId(username: name)
            }
            github.githubId = result.id
            github.username = result.login
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func saveGithub() {
        Task { await performSaveGithub() }
    }

    private func performSaveGithub() async {
        if github.githubId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ToastCenter.shared.error("请先获取 GitHub ID")
            return
        }
        if github.clientId.isEmpty || github.clientSecret.isEmpty || github.redirectUri.isEmpty {
            ToastCenter.shared.error("请填写 Client ID / Secret / 回调地址")
            return
        }
        guard AppAlert.confirm(title: "确认更新", message: "保存 GitHub 登录配置？") else { return }
        savingKey = "github"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateGithub(github)
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Google

    func saveGoogle() {
        Task { await performSaveGoogle() }
    }

    private func performSaveGoogle() async {
        if google.enabled, google.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ToastCenter.shared.error("启用时请填写 Google 邮箱")
            return
        }
        if google.clientId.isEmpty || google.clientSecret.isEmpty || google.redirectUri.isEmpty {
            ToastCenter.shared.error("请填写 Client ID / Secret / 回调地址")
            return
        }
        guard AppAlert.confirm(title: "确认更新", message: "保存 Google 登录配置？") else { return }
        savingKey = "google"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateGoogle(google)
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - MFA

    func saveMfa() {
        Task { await performSaveMfa() }
    }

    private func performSaveMfa() async {
        let tip = mfa.enabled ? "启用后登录将要求二次验证" : "关闭后将不再要求 MFA"
        guard AppAlert.confirm(title: "确认更新 MFA", message: tip) else { return }
        savingKey = "mfa"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateMfa(enabled: mfa.enabled, issuer: mfa.issuer)
            }
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func regenerateMfa() {
        Task { await performRegenerateMfa() }
    }

    private func performRegenerateMfa() async {
        guard AppAlert.confirm(
            title: "重新生成密钥",
            message: "旧密钥将失效，需要在验证器中重新扫码绑定"
        ) else { return }
        savingKey = "mfaRegen"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.regenerateMfaSecret()
            }
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func deleteMfa() {
        Task { await performDeleteMfa() }
    }

    private func performDeleteMfa() async {
        guard AppAlert.confirm(
            title: "删除 MFA",
            message: "将完全移除多因子认证配置，建议谨慎操作",
            confirmTitle: "删除",
            style: .critical
        ) else { return }
        savingKey = "mfaDelete"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.deleteMfaConfig()
            }
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func verifyMfa() {
        Task { await performVerifyMfa() }
    }

    private func performVerifyMfa() async {
        let code = mfa.verifyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            ToastCenter.shared.error("请输入 6 位验证码")
            return
        }
        guard code.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
            ToastCenter.shared.error("验证码格式错误，请输入 6 位数字")
            return
        }
        savingKey = "mfaVerify"
        defer { savingKey = nil }
        do {
            let msg = try await LoadingHUD.shared.during {
                try await service.verifyMfaCode(code)
            }
            mfa.verifyCode = ""
            AppAlert.info(title: "验证成功", message: msg)
        } catch {
            mfa.verifyCode = ""
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Turnstile / Channel

    func saveTurnstile() {
        Task { await performSaveTurnstile() }
    }

    private func performSaveTurnstile() async {
        if turnstile.enabled,
           turnstile.siteKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || turnstile.secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ToastCenter.shared.error("启用时请填写 Site Key 与 Secret Key")
            return
        }
        guard AppAlert.confirm(title: "确认更新", message: "保存 Turnstile 人机验证配置？") else { return }
        savingKey = "turnstile"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateTurnstile(turnstile)
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func saveChannelNotify() {
        Task { await performSaveChannelNotify() }
    }

    private func performSaveChannelNotify() async {
        let tip = channelNotifyEnabled
            ? "开启后将向频道上报开机成功事件（仅机型/区域）"
            : "关闭后将不再上报频道通知"
        guard AppAlert.confirm(title: "确认更新", message: tip) else { return }
        savingKey = "channel"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateChannelNotify(enabled: channelNotifyEnabled)
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
