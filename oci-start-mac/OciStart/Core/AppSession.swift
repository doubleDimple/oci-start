import Foundation
import Combine

/// Authentication + shell chrome state (no business list caches).
/// Not marked @MainActor on the type: AppDelegate must touch `.shared` on the main
/// thread only. Methods that update @Published should run on main.
final class AppSession: ObservableObject {
    static let shared = AppSession()

    @Published private(set) var isLoggedIn = false
    @Published var lastError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var username: String = ""
    @Published private(set) var siteName: String = "OCI-START"
    /// 1 = Oracle, 2 = GCP (align web header provider switch)
    @Published private(set) var cloudProvider: Int = 1

    private let auth = AuthService()
    private let defaultsKey = "serverURL"
    private let userKey = "lastUsername"
    private let cloudKey = "cloudProvider"

    var serverURL: String {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? "http://localhost:9856"
            return Self.normalize(raw)
        }
        set {
            UserDefaults.standard.set(Self.normalize(newValue), forKey: defaultsKey)
            objectWillChange.send()
        }
    }

    var cloudProviderName: String {
        switch cloudProvider {
        case 2: return "Google Cloud"
        case 3: return "Azure"
        case 4: return "AWS"
        default: return "Oracle Cloud"
        }
    }

    private init() {
        username = UserDefaults.standard.string(forKey: userKey) ?? ""
        let stored = UserDefaults.standard.integer(forKey: cloudKey)
        cloudProvider = stored == 0 ? 1 : stored
    }

    @MainActor
    func bootstrap() async {
        isBusy = true
        defer { isBusy = false }
        // Always require explicit login on launch.
        // Auto-restore was causing “open → skip login into main” while the shell
        // was still unstable; re-enable only after remember-me UX is intentional.
        isLoggedIn = false
        APIClient.shared.clearCookies(for: serverURL)
        AppDelegate.log("bootstrap: forced login (session restore disabled)")
    }

    @MainActor
    func login(
        username: String,
        password: String,
        verificationCode: String? = nil,
        mfaCode: String? = nil,
        rememberMe: Bool = true
    ) async throws {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            try await auth.login(
                baseURL: serverURL,
                username: username,
                password: password,
                verificationCode: verificationCode,
                mfaCode: mfaCode,
                rememberMe: rememberMe
            )
            self.username = username
            UserDefaults.standard.set(username, forKey: userKey)
            isLoggedIn = true
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    @MainActor
    func registerFirstUser(username: String, password: String) async throws {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        try await auth.registerFirstUser(baseURL: serverURL, username: username, password: password)
        // After first register, login immediately
        try await login(username: username, password: password)
    }

    func sendLoginCode(username: String) async throws {
        try await auth.sendVerificationCode(baseURL: serverURL, username: username)
    }

    func fetchLoginPageMeta() async throws -> APIClient.LoginPageMeta {
        try await auth.loginPageMeta(baseURL: serverURL)
    }

    @MainActor
    func logout() async {
        isBusy = true
        defer { isBusy = false }
        // Close main shell first, then hit logout API / clear cookies.
        let base = serverURL
        isLoggedIn = false
        await auth.logout(baseURL: base)
        APIClient.shared.clearCookies(for: base)
    }

    @MainActor
    func forceLogout() {
        isLoggedIn = false
        APIClient.shared.clearCookies(for: serverURL)
    }

    /// Local embedded backend (localhost) vs remote deployment.
    static func isLocalServerURL(_ raw: String) -> Bool {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return true }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "http://\(s)"
        }
        guard let host = URL(string: s)?.host?.lowercased() else { return true }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "0.0.0.0"
            || host == "::1"
            || host == "[::1]"
    }

    @MainActor
    func setCloudProvider(_ type: Int) {
        cloudProvider = type
        UserDefaults.standard.set(type, forKey: cloudKey)
        MenuBuilder.rebuildNavigationMenu()
        // Web header: if current page not available for this cloud, go to default landing
        let landing: NavID
        switch type {
        case 2: landing = .gcpAccounts
        case 3: landing = .azureVms
        case 4: landing = .awsEc2
        default: landing = .tenants
        }
        if let item = NavigationCatalog.item(for: NavigationState.shared.selected),
           let allowed = item.cloudTypes,
           !allowed.contains(type) {
            NavigationState.shared.select(landing)
        }
    }

    /// Update username from `/api/userInfo` without re-login.
    func applyRemoteUsername(_ name: String) {
        guard !name.isEmpty else { return }
        let apply = { [weak self] in
            self?.username = name
            UserDefaults.standard.set(name, forKey: self?.userKey ?? "lastUsername")
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    func fetchLoginFactors() async -> APIClient.LoginFactorConfig {
        await auth.loginFactorConfig(baseURL: serverURL)
    }

    private static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "http://localhost:9856" }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "http://\(s)"
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
