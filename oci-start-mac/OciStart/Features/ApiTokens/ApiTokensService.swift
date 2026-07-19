import Foundation

/// Network layer for Web `/system/apiTokens`.
struct ApiTokensService {
    let baseURL: String
    private let client = APIClient.shared

    /// GET `/api/system/apiTokenConfigs`
    func fetchConfigs() async throws -> (form: ApiTokenForm, status: ApiTokenStatus) {
        let url = try client.makeURL(baseURL, path: "/api/system/apiTokenConfigs")
        let raw = try await client.getJSON(url)
        return try ApiTokensJSON.parseConfigs(raw)
    }

    /// POST `/api/system/generateApiToken`
    func generate(_ form: ApiTokenForm) async throws -> ApiTokenGenerateResult {
        let url = try client.makeURL(baseURL, path: "/api/system/generateApiToken")
        let raw = try await client.postJSON(url, body: [
            "enabled": true,
            "tokenName": form.tokenName,
            "expirationDays": form.expirationDays,
            "description": form.description,
            "allowSwaggerAccess": form.allowSwaggerAccess
        ])
        return try ApiTokensJSON.parseGenerate(raw)
    }

    /// POST `/api/system/revokeApiToken`
    func revoke() async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/revokeApiToken")
        let raw = try await client.postJSON(url, body: [:])
        try ApiTokensJSON.ensureOK(raw, fallback: "撤销 Token 失败")
    }
}
