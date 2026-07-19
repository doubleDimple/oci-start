import Foundation

/// Network layer for Web `/dns/edgeone` + domain provider config.
struct EdgeOneService {
    let baseURL: String
    private let client = APIClient.shared

    func fetchZones() async throws -> [EoZone] {
        let url = try client.makeURL(baseURL, path: "/dns/edgeone/api/zones")
        let raw = try await client.getJSON(url)
        return try EdgeOneJSON.parseZones(raw)
    }

    func fetchDnsRecords(zoneId: String) async throws -> [EoDnsRecord] {
        let url = try client.makeURL(
            baseURL,
            path: "/dns/edgeone/api/records",
            query: ["zoneId": zoneId, "type": "dns"]
        )
        let raw = try await client.getJSON(url)
        return try EdgeOneJSON.parseDnsRecords(raw)
    }

    func fetchAccelDomains(zoneId: String) async throws -> [EoAccelDomain] {
        // Prefer dedicated domains API; fall back to records?type=domain
        do {
            let url = try client.makeURL(
                baseURL,
                path: "/dns/edgeone/api/domains",
                query: ["zoneId": zoneId]
            )
            let raw = try await client.getJSON(url)
            return try EdgeOneJSON.parseAccelDomains(raw)
        } catch {
            let url = try client.makeURL(
                baseURL,
                path: "/dns/edgeone/api/records",
                query: ["zoneId": zoneId, "type": "domain"]
            )
            let raw = try await client.getJSON(url)
            return try EdgeOneJSON.parseAccelDomains(raw)
        }
    }

    func createDnsRecord(
        zoneId: String,
        type: String,
        name: String,
        content: String,
        ttl: Int,
        priority: Int?
    ) async throws {
        let url = try client.makeURL(baseURL, path: "/dns/edgeone/api/records")
        var body: [String: Any] = [
            "zoneId": zoneId,
            "type": type,
            "name": name,
            "content": content,
            "ttl": ttl
        ]
        if let priority = priority {
            body["priority"] = priority
        }
        let raw = try await client.postJSON(url, body: body)
        try EdgeOneJSON.ensureOK(raw, fallback: "添加 DNS 记录失败")
    }

    func updateDnsRecord(
        recordId: String,
        zoneId: String,
        type: String,
        name: String,
        content: String,
        ttl: Int,
        priority: Int?
    ) async throws {
        let url = try client.makeURL(baseURL, path: "/dns/edgeone/api/records/\(recordId)")
        var body: [String: Any] = [
            "zoneId": zoneId,
            "recordType": type,
            "recordName": name,
            "content": content,
            "ttl": ttl
        ]
        if let priority = priority {
            body["priority"] = priority
        }
        let raw = try await client.putJSON(url, body: body)
        try EdgeOneJSON.ensureOK(raw, fallback: "更新 DNS 记录失败")
    }

    func deleteDnsRecord(recordId: String) async throws {
        let url = try client.makeURL(baseURL, path: "/dns/edgeone/api/records/\(recordId)")
        let raw = try await client.deleteJSON(url)
        try EdgeOneJSON.ensureOK(raw, fallback: "删除 DNS 记录失败")
    }

    func deleteAccelDomain(domainId: String) async throws {
        let url = try client.makeURL(baseURL, path: "/dns/edgeone/api/domains/\(domainId)")
        let raw = try await client.deleteJSON(url)
        try EdgeOneJSON.ensureOK(raw, fallback: "删除加速域名失败")
    }

    func syncDns(zoneId: String, domainName: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/dns/edgeone/api/zones/\(zoneId)/sync")
        let raw = try await client.postJSON(url, body: ["domainName": domainName])
        return try EdgeOneJSON.parseSyncMessage(raw)
    }

    func syncDomains(zoneId: String, domainName: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/dns/edgeone/api/zones/\(zoneId)/sync-domains")
        let raw = try await client.postJSON(url, body: ["domainName": domainName])
        return try EdgeOneJSON.parseSyncMessage(raw)
    }

    func fetchConfig() async throws -> EoConfigForm {
        let url = try client.makeURL(baseURL, path: "/api/system/domainProviderConfigs")
        let raw = try await client.getJSON(url)
        return try EdgeOneJSON.parseConfig(raw)
    }

    func updateConfig(_ form: EoConfigForm) async throws {
        let url = try client.makeURL(baseURL, path: "/api/system/updateEdgeOneConfig")
        let raw = try await client.postJSON(url, body: [
            "enabled": form.enabled,
            "secretId": form.secretId,
            "secretKey": form.secretKey,
            "region": form.region
        ])
        try EdgeOneJSON.ensureOK(raw, fallback: "保存 EdgeOne 配置失败")
    }

    func testConfig(_ form: EoConfigForm) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/system/testEdgeOneConnection")
        let raw = try await client.postJSON(url, body: [
            "secretId": form.secretId,
            "secretKey": form.secretKey,
            "region": form.region,
            "enabled": form.enabled
        ])
        return try EdgeOneJSON.parseTestResult(raw)
    }
}
