import Foundation

/// Network layer for Web `/dns/cloudflare` + domain provider config.
struct CloudflareService {
    let baseURL: String
    private let client = APIClient.shared

    func fetchZones() async throws -> [CfZone] {
        let url = try client.makeURL(baseURL, path: "/dns/cloudflare/api/zones")
        let raw = try await client.getJSON(url)
        return try CloudflareJSON.parseZones(raw)
    }

    /// Cloudflare API page is 1-based.
    func fetchRecords(zoneId: String, page: Int, size: Int) async throws -> (items: [CfDnsRecord], total: Int64, pages: Int) {
        let url = try client.makeURL(
            baseURL,
            path: "/dns/cloudflare/api/zones/\(zoneId)/records",
            query: [
                "page": "\(max(1, page))",
                "size": "\(size)"
            ]
        )
        let raw = try await client.getJSON(url)
        return try CloudflareJSON.parseRecordsPage(raw)
    }

    func createRecord(
        zoneId: String,
        type: String,
        name: String,
        content: String,
        ttl: Int,
        proxied: Bool
    ) async throws {
        let url = try client.makeURL(baseURL, path: "/dns/cloudflare/api/records")
        let raw = try await client.postJSON(url, body: [
            "zoneId": zoneId,
            "type": type,
            "name": name,
            "content": content,
            "ttl": ttl,
            "proxied": proxied
        ])
        try CloudflareJSON.ensureOK(raw, fallback: "创建 DNS 记录失败")
    }

    func updateRecord(
        recordId: String,
        zoneId: String,
        type: String,
        name: String,
        content: String,
        ttl: Int,
        proxied: Bool
    ) async throws {
        let url = try client.makeURL(baseURL, path: "/dns/cloudflare/api/records/\(recordId)")
        let raw = try await client.putJSON(url, body: [
            "zoneId": zoneId,
            "recordType": type,
            "recordName": name,
            "content": content,
            "ttl": ttl,
            "proxied": proxied
        ])
        try CloudflareJSON.ensureOK(raw, fallback: "更新 DNS 记录失败")
    }

    func deleteRecord(recordId: String, zoneId: String) async throws {
        let url = try client.makeURL(
            baseURL,
            path: "/dns/cloudflare/api/records/\(recordId)",
            query: ["zoneId": zoneId]
        )
        let raw = try await client.deleteJSON(url)
        try CloudflareJSON.ensureOK(raw, fallback: "删除 DNS 记录失败")
    }

    func syncZone(zoneId: String, domainName: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/dns/cloudflare/api/zones/\(zoneId)/sync")
        let raw = try await client.postJSON(url, body: ["domainName": domainName])
        return try CloudflareJSON.parseSyncMessage(raw)
    }

    func fetchConfig() async throws -> CfConfigForm {
        let url = try client.makeURL(baseURL, path: "/api/system/domainProviderConfigs")
        let raw = try await client.getJSON(url)
        return try CloudflareJSON.parseConfig(raw)
    }

    func updateConfig(_ form: CfConfigForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateCloudflareConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "apiToken": form.apiToken,
            "email": form.email,
            "zoneId": ""
        ])
        try CloudflareJSON.ensureOK(raw, fallback: "保存 Cloudflare 配置失败")
    }

    func testConfig(_ form: CfConfigForm) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/system/testCloudflareConnection")
        let raw = try await client.postJSON(url, body: [
            "apiToken": form.apiToken,
            "email": form.email,
            "enabled": form.enabled
        ])
        return try CloudflareJSON.parseTestResult(raw)
    }
}
