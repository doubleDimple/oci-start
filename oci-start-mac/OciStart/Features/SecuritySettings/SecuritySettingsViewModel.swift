import Foundation
import Combine
import AppKit

@MainActor
final class SecuritySettingsViewModel: ObservableObject {
    @Published var currentUsername = ""
    @Published var siteLogoName = "OCI-START"
    @Published var currentPassword = ""
    @Published var newUsername = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var github = GithubOAuthForm()
    @Published var google = GoogleOAuthForm()
    @Published var mfa = MfaForm()
    @Published var turnstile = TurnstileForm()
    @Published var channelNotifyEnabled = false
    @Published private(set) var isLoading = false
    @Published private(set) var savingKey: String?
    @Published private(set) var errorText: String?
    @Published private(set) var notice: String?
    @Published private(set) var loaded = false
    @Published private(set) var loadFailed = false
    @Published private(set) var requiresReview = false
    private let session: AppSession
    private var service: SecuritySettingsService { SecuritySettingsService(baseURL: session.serverURL) }
    private var baseline: SecuritySettingsSnapshot?
    private var generation = 0
    private var active = false
    var canMutate: Bool { loaded && !loadFailed && !isLoading && savingKey == nil && !requiresReview }

    init(session: AppSession = .shared) { self.session = session }
    func start() { active = true; Task { @MainActor in await reload() } }
    func stop() { active = false; generation += 1; clearSecrets() }

    var hasUnsavedChanges: Bool {
        guard let baseline = baseline else { return false }
        var currentMfa = mfa
        currentMfa.secretKey = ""; currentMfa.qrCodeBase64 = ""; currentMfa.verifyCode = ""
        return siteLogoName != baseline.siteLogoName || github != baseline.github || google != baseline.google
            || currentMfa != baseline.mfa || turnstile != baseline.turnstile || channelNotifyEnabled != baseline.channelNotifyEnabled
            || !currentPassword.isEmpty || !newUsername.isEmpty || !newPassword.isEmpty || !confirmPassword.isEmpty
    }

    func canLeave() -> Bool {
        guard savingKey == nil else {
            AppAlert.info(title: "请求正在提交", message: "请等待当前操作完成。")
            return false
        }
        guard hasUnsavedChanges || requiresReview else { return true }
        return AppAlert.confirm(title: "离开安全设置", message: requiresReview
            ? "操作结果尚未确认。离开后请重新读取并核对服务器实际配置，避免重复提交。"
            : "存在未保存的修改，离开将丢弃这些修改。", confirmTitle: "离开", cancelTitle: "继续编辑")
    }

    func requestReload() { if canLeave() { Task { @MainActor in await reload() } } }
    func reload() async {
        guard savingKey == nil else { return }
        generation += 1
        let current = generation
        isLoading = true
        defer { if generation == current { isLoading = false } }
        do {
            let snapshot = try await service.fetchConfigs()
            guard active, current == generation else { return }
            currentUsername = snapshot.currentUsername; siteLogoName = snapshot.siteLogoName
            github = snapshot.github; google = snapshot.google; mfa = snapshot.mfa
            turnstile = snapshot.turnstile; channelNotifyEnabled = snapshot.channelNotifyEnabled
            clearAccount()
            baseline = snapshot
            loaded = true; loadFailed = false; requiresReview = false; errorText = nil
            session.applySiteName(snapshot.siteLogoName)
            session.applyRemoteUsername(snapshot.currentUsername)
        } catch {
            if active, generation == current {
                loadFailed = true
                errorText = "配置读取未完成，请确认服务端已更新后重试。"
            }
        }
    }

    func clearAccount() { currentPassword = ""; newUsername = ""; newPassword = ""; confirmPassword = "" }
    func hideMfa() { mfa.secretKey = ""; mfa.qrCodeBase64 = ""; mfa.verifyCode = "" }
    private func clearSecrets() {
        clearAccount(); github.clientSecret = ""; google.clientSecret = ""; turnstile.secretKey = ""; hideMfa()
    }
    func setMfaVerifyCode(_ raw: String) { mfa.verifyCode = String(raw.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
    func copyMfaSecret() {
        guard !mfa.secretKey.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mfa.secretKey, forType: .string)
    }

    private func validation(_ work: () throws -> Void) -> Bool {
        guard canMutate else { return false }
        do { try work(); return true }
        catch { errorText = error.localizedDescription; return false }
    }
    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw APIError.serverMessage(message) }
    }
    private func validCallback(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme ?? ""), url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else { return false }
        return value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !value.contains("\\")
    }

    func saveLogo() {
        let name = siteLogoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validation({ try require(!name.isEmpty && name.count <= 15, "站点名称应为 1–15 个字符。") }) else { return }
        submit("logo", confirmation: "将站点名称修改为「\(name)」。") { try await self.service.updateLogoName(name) }
    }

    func updateAccount() {
        let current = currentPassword, username = newUsername.trimmingCharacters(in: .whitespacesAndNewlines), password = newPassword
        guard validation({
            try require(!current.isEmpty, "请输入当前密码。")
            try require(!username.isEmpty || !password.isEmpty, "请至少修改用户名或密码。")
            try require(password.isEmpty || (!password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password == confirmPassword), "请检查新密码与确认密码。")
        }), AppAlert.confirm(title: "更新账号", message: "修改用户名或密码会注销原账号会话，之后需要使用新信息登录。") else { return }
        savingKey = "account"
        Task { @MainActor in
            do {
                let relogin = try await service.updateAccount(currentPassword: current, newUsername: username, newPassword: password)
                savingKey = nil; clearAccount()
                guard active else { return }
                if relogin { session.forceLogout() }
                else { savingKey = nil; await reload() }
            } catch {
                savingKey = nil; clearAccount()
                requiresReview = true
                errorText = "账号更新结果未确认，请使用可能更新后的账号信息重新登录核对。"
            }
        }
    }

    func fetchGithubId() {
        guard canMutate else { return }
        let name = github.username.trimmingCharacters(in: .whitespacesAndNewlines)
        savingKey = "githubFetch"
        Task { @MainActor in
            do {
                let identity = try await service.fetchGithubUserId(username: name)
                savingKey = nil
                guard active, github.username.trimmingCharacters(in: .whitespacesAndNewlines) == name else { return }
                github.githubId = identity.id; github.username = identity.login
            } catch { savingKey = nil; if active { errorText = "GitHub 用户信息读取未完成，请检查用户名后重试。" } }
        }
    }

    func saveGithub() {
        github.username = github.username.trimmingCharacters(in: .whitespacesAndNewlines)
        github.githubId = github.githubId.trimmingCharacters(in: .whitespacesAndNewlines)
        github.clientId = github.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        github.redirectUri = github.redirectUri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validation({
            try github.secretMode.validate(github.clientSecret, hasSaved: github.hasClientSecret, required: github.enabled)
            try require(github.githubId.isEmpty || github.githubId.range(of: #"^[1-9]\d*$"#, options: .regularExpression) != nil, "请填写有效 GitHub ID。")
            try require(!github.enabled || (!github.githubId.isEmpty && !github.clientId.isEmpty && !github.redirectUri.isEmpty), "启用时需要 GitHub ID、Client ID 和回调地址。")
            try require(validCallback(github.redirectUri), "请输入有效 HTTP(S) 回调地址。")
        }) else { return }
        let form = github
        submit("github", confirmation: "保存 GitHub 登录设置。" + clearWarning(form.secretMode)) { try await self.service.updateGithub(form) }
    }
    func saveGoogle() {
        google.email = google.email.trimmingCharacters(in: .whitespacesAndNewlines)
        google.clientId = google.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        google.redirectUri = google.redirectUri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validation({
            try google.secretMode.validate(google.clientSecret, hasSaved: google.hasClientSecret, required: google.enabled)
            try require(google.email.isEmpty || google.email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil, "请输入有效 Google 邮箱。")
            try require(!google.enabled || (!google.email.isEmpty && !google.clientId.isEmpty && !google.redirectUri.isEmpty), "启用时需要邮箱、Client ID 和回调地址。")
            try require(validCallback(google.redirectUri), "请输入有效 HTTP(S) 回调地址。")
        }) else { return }
        let form = google
        submit("google", confirmation: "保存 Google 登录设置。" + clearWarning(form.secretMode)) { try await self.service.updateGoogle(form) }
    }
    func saveTurnstile() {
        turnstile.siteKey = turnstile.siteKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validation({
            try turnstile.secretMode.validate(turnstile.secretKey, hasSaved: turnstile.hasSecretKey, required: turnstile.enabled)
            try require(!turnstile.enabled || !turnstile.siteKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "启用时需要 Site Key。")
        }) else { return }
        let form = turnstile
        submit("turnstile", confirmation: "保存登录人机验证配置。" + clearWarning(form.secretMode)) { try await self.service.updateTurnstile(form) }
    }
    func saveMfa() {
        guard validation({ try require(mfa.issuer.rangeOfCharacter(from: .controlCharacters) == nil, "应用名称不能包含控制字符。") }) else { return }
        let form = mfa
        submit("mfa", confirmation: form.enabled ? "启用 MFA。请完成验证器设置并验证验证码。" : "停用 MFA 登录验证。") {
            try await self.service.updateMfa(enabled: form.enabled, issuer: form.issuer)
        }
    }
    func regenerateMfa() {
        guard !hasUnsavedChanges else { errorText = "请先保存或放弃修改，再重新生成 MFA 密钥。"; return }
        submit("mfaRegen", confirmation: "重新生成 MFA 密钥后旧验证码失效，需要重新设置验证器。") { try await self.service.regenerateMfaSecret() }
    }
    func deleteMfa() {
        guard !hasUnsavedChanges else { errorText = "请先保存或放弃修改，再删除 MFA。"; return }
        submit("mfaDelete", confirmation: "删除 MFA 设置密钥并停用 MFA，原验证器的验证码将失效。") { try await self.service.deleteMfaConfig() }
    }
    func revealMfa() {
        guard canMutate, mfa.hasSecretKey else { return }
        savingKey = "mfaMaterial"
        Task { @MainActor in
            do {
                let material = try await service.fetchMfaMaterial()
                savingKey = nil
                guard active else { return }
                mfa.secretKey = material.secret; mfa.qrCodeBase64 = material.qrCode
            } catch { savingKey = nil; if active { errorText = "MFA 设置资料读取未完成，请重试。" } }
        }
    }
    func verifyMfa() {
        let code = mfa.verifyCode
        guard validation({ try require(code.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil, "请输入 6 位数字验证码。") }) else { return }
        savingKey = "mfaVerify"
        Task { @MainActor in
            do { notice = try await service.verifyMfaCode(code) }
            catch { errorText = "验证码未通过验证，请重试。" }
            savingKey = nil; mfa.verifyCode = ""
        }
    }
    func saveChannelNotify() {
        let enabled = channelNotifyEnabled
        submit("channel", confirmation: enabled ? "启用向频道发送开机通知。" : "停用向频道发送开机通知。") {
            try await self.service.updateChannelNotify(enabled: enabled)
        }
    }
    private func clearWarning(_ mode: NativeSecretMode) -> String { mode == .clear ? " 此操作会清除已保存的密钥。" : "" }
    private func submit(_ key: String, confirmation: String, _ work: @escaping () async throws -> Void) {
        guard canMutate, AppAlert.confirm(title: "确认保存", message: confirmation) else { return }
        savingKey = key; errorText = nil; notice = nil
        let accountDraft = (currentPassword, newUsername, newPassword, confirmPassword)
        Task { @MainActor in
            do {
                try await work()
                clearSecrets()
                savingKey = nil
                guard active else { return }
                requiresReview = true
                await reload()
                if key == "logo" {
                    currentPassword = accountDraft.0; newUsername = accountDraft.1
                    newPassword = accountDraft.2; confirmPassword = accountDraft.3
                }
                notice = "操作已确认完成；请核对重新读取的配置。"
            } catch {
                clearSecrets(); savingKey = nil
                guard active else { return }
                requiresReview = true
                errorText = "操作结果未确认。请重新读取并核对配置后继续，避免重复提交。"
            }
        }
    }
}
