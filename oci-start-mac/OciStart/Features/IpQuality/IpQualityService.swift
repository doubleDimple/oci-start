import Foundation

/// Network layer for IP quality settings (`/system/ipSettings` · `/api/system/ipSettingsConfigs`).
struct IpQualityService {
    let baseURL: String
    private let client = APIClient.shared

    /// GET `/api/system/ipSettingsConfigs`
    func fetchConfigs() async throws -> IpQualityConfigs {
        let url = try client.makeURL(baseURL, path: "/api/system/ipSettingsConfigs")
        let raw = try await client.getJSON(url)
        return try IpQualityJSON.parseConfigs(raw)
    }

    /// POST `/api/system/updateIpCheckConfig`
    func updateIpCheck(enabled: Bool, checkInterval: Int) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateIpCheckConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": enabled,
            "checkInterval": checkInterval
        ])
        try IpQualityJSON.ensureOK(raw, fallback: "保存 IP 检测配置失败")
    }

    /// POST `/system/vps/saveConfig`
    func saveVPS(_ config: VPSConfigDTO) async throws {
        let url = try client.makeURL(baseURL, path: "/system/vps/saveConfig")
        let raw = try await client.postJSON(url, body: [
            "type": config.type,
            "enabled": config.enabled,
            "serverIp": config.serverIp,
            "username": config.username,
            "password": config.password,
            "sshPort": config.sshPort
        ])
        try IpQualityJSON.ensureOK(raw, fallback: "保存 VPS 配置失败")
    }

    /// POST `/system/vps/testConnection`
    func testConnection(_ config: VPSConfigDTO) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/system/vps/testConnection")
        let raw = try await client.postJSON(url, body: [
            "type": config.type,
            "serverIp": config.serverIp,
            "username": config.username,
            "password": config.password,
            "sshPort": config.sshPort
        ])
        return try IpQualityJSON.parseTestResult(raw)
    }
}
