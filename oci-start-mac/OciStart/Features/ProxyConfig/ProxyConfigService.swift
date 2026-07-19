import Foundation

/// Network layer for `/vpnProxy/*` (系统管理 · 代理配置).
struct ProxyConfigService {
    let baseURL: String
    private let client = APIClient.shared

    /// POST `/vpnProxy/pageList` · pageNum 1-based
    func pageList(pageNum: Int, pageSize: Int) async throws -> (items: [VpnProxyItem], total: Int64, pages: Int, number: Int, size: Int) {
        let url = try client.makeURL(baseURL, path: "/vpnProxy/pageList")
        let raw = try await client.postJSON(url, body: [
            "pageNum": pageNum,
            "pageSize": pageSize
        ])
        return try ProxyConfigJSON.parsePage(raw)
    }

    /// POST `/vpnProxy/saveOrUpdate`
    func saveOrUpdate(_ form: ProxyFormState) async throws {
        let port = Int(form.proxyPort) ?? 0
        guard !form.proxyType.isEmpty, !form.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.serverMessage("请填写代理类型与地址")
        }
        guard (1...65535).contains(port) else {
            throw APIError.serverMessage("端口范围应为 1–65535")
        }
        var body: [String: Any] = [
            "proxyType": form.proxyType,
            "proxyHost": form.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines),
            "proxyPort": port,
            "availableStatus": form.availableStatus,
            // 强制代理：1=强制（不通拒绝请求），0=非强制
            "forceProxy": form.forceProxy == 1 ? 1 : 0
        ]
        if let id = form.id { body["id"] = id }
        // 用户名始终提交（可空），避免更新时被误判为未传
        body["proxyUsername"] = form.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        // 密码：有内容才提交；空则不传，后端保留原密码
        let pass = form.proxyPassword
        if !pass.isEmpty {
            body["proxyPassword"] = pass
        }
        if let tid = form.tenantId, tid > 0 {
            body["tenantId"] = tid
        } else {
            body["tenantId"] = NSNull()
        }
        let url = try client.makeURL(baseURL, path: "/vpnProxy/saveOrUpdate")
        let raw = try await client.postJSON(url, body: body)
        try ProxyConfigJSON.ensureSuccess(raw, fallback: "保存代理失败")
    }

    /// POST `/vpnProxy/delete`
    func delete(id: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/vpnProxy/delete")
        let raw = try await client.postJSON(url, body: ["id": id])
        try ProxyConfigJSON.ensureSuccess(raw, fallback: "删除代理失败")
    }

    /// GET `/tenants/listParentTenants`
    func listParentTenants() async throws -> [ProxyParentTenant] {
        let url = try client.makeURL(baseURL, path: "/tenants/listParentTenants")
        let raw = try await client.getJSON(url)
        return ProxyConfigJSON.parseParentTenants(raw)
    }

    /// POST `/vpnProxy/testConnection` · body `{ id }` · persists availableStatus
    func testConnection(id: Int64) async throws -> ProxyTestResult {
        let url = try client.makeURL(baseURL, path: "/vpnProxy/testConnection")
        let raw = try await client.postJSON(url, body: ["id": id])
        return try ProxyConfigJSON.parseTestResult(raw)
    }

    /// POST `/vpnProxy/testAll` · probe every proxy and persist
    func testAll() async throws -> ProxyTestAllResult {
        let url = try client.makeURL(baseURL, path: "/vpnProxy/testAll")
        let raw = try await client.postJSON(url, body: [:])
        return try ProxyConfigJSON.parseTestAllResult(raw)
    }
}
