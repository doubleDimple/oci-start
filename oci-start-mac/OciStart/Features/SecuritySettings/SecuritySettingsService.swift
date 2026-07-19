import Foundation

/// Network layer for Web `/system/settings` security page.
struct SecuritySettingsService {
    let baseURL: String
    private let client = APIClient.shared

    /// GET `/api/system/securitySettingsConfigs`
    func fetchConfigs() async throws -> SecuritySettingsSnapshot {
        let url = try client.makeURL(baseURL, path: "/api/system/securitySettingsConfigs")
        let raw = try await client.getJSON(url)
        return try SecuritySettingsJSON.parse(raw)
    }

    /// POST `/api/system/updatePassword`
    func updateAccount(currentPassword: String, newUsername: String?, newPassword: String?) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updatePassword")
        var body: [String: Any] = ["currentPassword": currentPassword]
        if let newUsername = newUsername, !newUsername.isEmpty {
            body["newUsername"] = newUsername
        }
        if let newPassword = newPassword, !newPassword.isEmpty {
            body["newPassword"] = newPassword
        }
        let raw = try await client.postJSON(url, body: body)
        try SecuritySettingsJSON.ensureOK(raw, fallback: "账号更新失败")
    }

    /// POST `/api/system/settings/logo?logoName=`
    func updateLogoName(_ logoName: String) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/settings/logo")
        let (data, http) = try await client.postForm(url, fields: ["logoName": logoName])
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "保存 Logo 失败"
            throw APIError.serverMessage(msg.isEmpty ? "保存 Logo 失败" : msg)
        }
        try SecuritySettingsJSON.ensureOK(data, fallback: "保存 Logo 失败")
    }

    /// POST `/api/system/updateGithubConfig`
    func updateGithub(_ form: GithubOAuthForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateGithubConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "userName": form.username,
            "username": form.username,
            "githubId": form.githubId,
            "clientId": form.clientId,
            "clientSecret": form.clientSecret,
            "redirectUri": form.redirectUri
        ])
        try SecuritySettingsJSON.ensureOK(raw, fallback: "GitHub 配置更新失败")
    }

    /// POST `/api/system/updateGoogleConfig`
    func updateGoogle(_ form: GoogleOAuthForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateGoogleConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "email": form.email,
            "clientId": form.clientId,
            "clientSecret": form.clientSecret,
            "redirectUri": form.redirectUri
        ])
        try SecuritySettingsJSON.ensureOK(raw, fallback: "Google 配置更新失败")
    }

    /// POST `/api/system/updateMfaConfig`
    func updateMfa(enabled: Bool, issuer: String) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateMfaConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": enabled,
            "issuer": issuer.isEmpty ? "OCI-Start Verify" : issuer
        ])
        try SecuritySettingsJSON.ensureOK(raw, fallback: "MFA 配置更新失败")
    }

    /// POST `/api/system/regenerateMfaSecret`
    func regenerateMfaSecret() async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/regenerateMfaSecret")
        let raw = try await client.postJSON(url, body: [:])
        try SecuritySettingsJSON.ensureOK(raw, fallback: "重新生成 MFA 密钥失败")
    }

    /// DELETE `/api/system/deleteMfaConfig`
    func deleteMfaConfig() async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/deleteMfaConfig")
        let raw = try await client.deleteJSON(url)
        try SecuritySettingsJSON.ensureOK(raw, fallback: "删除 MFA 失败")
    }

    /// POST `/api/system/verifyMfaCode`
    func verifyMfaCode(_ code: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/system/verifyMfaCode")
        let raw = try await client.postJSON(url, body: ["code": code])
        return try SecuritySettingsJSON.parseApiResponse(raw, fallback: "验证成功")
    }

    /// POST `/api/system/updateTurnstileConfig`
    func updateTurnstile(_ form: TurnstileForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateTurnstileConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "siteKey": form.siteKey,
            "secretKey": form.secretKey
        ])
        try SecuritySettingsJSON.ensureOK(raw, fallback: "Turnstile 配置更新失败")
    }

    /// POST `/api/system/updateChannelNotifyConfig`
    func updateChannelNotify(enabled: Bool) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateChannelNotifyConfig")
        let raw = try await client.postJSON(url, body: ["enabled": enabled])
        try SecuritySettingsJSON.ensureOK(raw, fallback: "频道通知配置更新失败")
    }

    /// Fetch GitHub user id via public API.
    func fetchGithubUserId(username: String) async throws -> (id: String, login: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.serverMessage("请输入 GitHub 用户名") }
        guard let url = URL(string: "https://api.github.com/users/\(trimmed)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.compatData(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "用户不存在"
            throw APIError.serverMessage(msg.isEmpty ? "GitHub 用户不存在" : msg)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.serverMessage("解析 GitHub 用户失败")
        }
        let id: String
        if let n = obj["id"] as? NSNumber {
            id = n.stringValue
        } else if let s = obj["id"] as? String {
            id = s
        } else {
            throw APIError.serverMessage("未获取到 GitHub ID")
        }
        let login = (obj["login"] as? String) ?? trimmed
        return (id, login)
    }
}
