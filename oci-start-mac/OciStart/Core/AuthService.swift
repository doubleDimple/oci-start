import Foundation

final class AuthService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func login(
        baseURL: String,
        username: String,
        password: String,
        verificationCode: String? = nil,
        mfaCode: String? = nil,
        rememberMe: Bool = true
    ) async throws {
        let html = try await client.fetchLoginPage(baseURL: baseURL)
        let encrypted: String
        if let publicKey = Self.extractPublicKey(from: html),
           let cipher = RSAHelper.encrypt(plainText: password, publicKeyBase64: publicKey) {
            encrypted = cipher
        } else {
            encrypted = password
        }

        let result = try await client.performLogin(
            baseURL: baseURL,
            username: username,
            password: encrypted,
            verificationCode: verificationCode,
            mfaCode: mfaCode,
            rememberMe: rememberMe
        )

        if result.success == false {
            throw APIError.serverMessage(result.message ?? "登录失败")
        }
    }

    func registerFirstUser(baseURL: String, username: String, password: String) async throws {
        try await client.registerFirstUser(baseURL: baseURL, username: username, password: password)
    }

    func sendVerificationCode(baseURL: String, username: String) async throws {
        try await client.sendLoginVerificationCode(baseURL: baseURL, username: username)
    }

    func loginPageMeta(baseURL: String) async throws -> APIClient.LoginPageMeta {
        try await client.fetchLoginPageMeta(baseURL: baseURL)
    }

    static func extractPublicKeyPublic(from html: String) -> String? {
        extractPublicKey(from: html)
    }

    func logout(baseURL: String) async {
        await client.performLogout(baseURL: baseURL)
    }

    func validateSession(baseURL: String) async -> Bool {
        await client.validateSession(baseURL: baseURL)
    }

    func loginFactorConfig(baseURL: String) async -> APIClient.LoginFactorConfig {
        await client.fetchLoginFactorConfig(baseURL: baseURL)
    }

    private static func extractPublicKey(from html: String) -> String? {
        let pattern = #"window\.RSA_PUBLIC_KEY\s*=\s*"([A-Za-z0-9+/=\r\n]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }
}
