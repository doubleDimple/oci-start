import Foundation

/// Network layer for Web `/system/domainSettings` · `/api/system/*`.
struct KeyConfigService {
    let baseURL: String
    private let client = APIClient.shared

    /// GET `/api/system/domainProviderConfigs`
    func fetchConfigs() async throws -> DomainProviderConfigs {
        let url = try client.makeURL(baseURL, path: "/api/system/domainProviderConfigs")
        let raw = try await client.getJSON(url)
        return try KeyConfigJSON.parseConfigs(raw)
    }

    /// POST `/api/system/updateCloudflareConfig`
    func updateCloudflare(_ cfg: CloudflareKeyConfig) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateCloudflareConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": cfg.enabled,
            "apiToken": cfg.apiToken,
            "email": cfg.email,
            "zoneId": cfg.zoneId
        ])
        try KeyConfigJSON.ensureOK(raw, fallback: "保存 Cloudflare 配置失败")
    }

    /// POST `/api/system/testCloudflareConnection`
    func testCloudflare(_ cfg: CloudflareKeyConfig) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/system/testCloudflareConnection")
        let raw = try await client.postJSON(url, body: [
            "apiToken": cfg.apiToken,
            "email": cfg.email,
            "zoneId": cfg.zoneId,
            "enabled": cfg.enabled
        ])
        return try KeyConfigJSON.parseTestResult(raw, fallbackOK: "Cloudflare API 连接成功")
    }

    /// POST `/api/system/updateEdgeOneConfig`
    func updateEdgeOne(_ cfg: EdgeOneKeyConfig) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateEdgeOneConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": cfg.enabled,
            "secretId": cfg.secretId,
            "secretKey": cfg.secretKey,
            "region": cfg.region
        ])
        try KeyConfigJSON.ensureOK(raw, fallback: "保存 EdgeOne 配置失败")
    }

    /// POST `/api/system/testEdgeOneConnection`
    func testEdgeOne(_ cfg: EdgeOneKeyConfig) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/system/testEdgeOneConnection")
        let raw = try await client.postJSON(url, body: [
            "secretId": cfg.secretId,
            "secretKey": cfg.secretKey,
            "region": cfg.region,
            "enabled": cfg.enabled
        ])
        return try KeyConfigJSON.parseTestResult(raw, fallbackOK: "腾讯云 EdgeOne API 连接成功")
    }
}
