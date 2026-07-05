import Foundation

final class AuthService {

    private let network: NetworkService

    init(network: NetworkService) {
        self.network = network
    }

    func login(baseURL: String, username: String, password: String,
               verificationCode: String? = nil, mfaCode: String? = nil) async throws {
        // 1. Fetch login page to get RSA public key + session cookie
        let html = try await network.fetchLoginPage(baseURL: baseURL)

        // 2. Extract public key from JS variable: window.RSA_PUBLIC_KEY = "..."
        let encryptedPassword: String
        if let publicKey = extractPublicKey(from: html) {
            encryptedPassword = RSAHelper.encrypt(plainText: password, publicKeyBase64: publicKey) ?? password
        } else {
            // Server allows plaintext fallback
            encryptedPassword = password
        }

        // 3. Submit credentials
        let response = try await network.performLogin(
            baseURL: baseURL,
            username: username,
            encryptedPassword: encryptedPassword,
            verificationCode: verificationCode,
            mfaCode: mfaCode
        )

        guard response.success == true else {
            throw NetworkError.serverError(response.message ?? "登录失败")
        }
    }

    private func extractPublicKey(from html: String) -> String? {
        // Matches: window.RSA_PUBLIC_KEY = "BASE64STRING";
        let pattern = #"window\.RSA_PUBLIC_KEY\s*=\s*"([A-Za-z0-9+/=\r\n]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }
}
