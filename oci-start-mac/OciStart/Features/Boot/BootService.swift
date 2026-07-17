import Foundation

/// Network layer for `/boot/*` (+ parent/region tenants for cascade filter).
struct BootService {
    let baseURL: String
    private let client = APIClient.shared

    // MARK: - List / filter

    /// `GET /boot/fullBootList/json` — 0-based page.
    func list(page: Int, size: Int, tenantId: String?) async throws -> BootListResponse {
        var q: [String: String] = [
            "page": "\(page)",
            "size": "\(size)"
        ]
        if let tenantId = tenantId, !tenantId.isEmpty {
            q["tenantId"] = tenantId
        }
        let url = try client.makeURL(baseURL, path: "/boot/fullBootList/json", query: q)
        let raw = try await client.getJSON(url)
        return try BootJSON.parseList(raw)
    }

    func listParentTenants() async throws -> [TenantRegionOption] {
        let url = try client.makeURL(baseURL, path: "/tenants/listParentTenants")
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantRegionOption].self, from: raw)) ?? []
    }

    func listRegions(parentId: String) async throws -> [TenantRegionOption] {
        let url = try client.makeURL(baseURL, path: "/tenants/listRegions", query: ["parentId": parentId])
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantRegionOption].self, from: raw)) ?? []
    }

    // MARK: - Actions (query-param style)

    func startBoot(bootId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/boot/startBoot", query: ["bootId": "\(bootId)"])
        let raw = try await client.getJSON(url)
        try BootJSON.ensureSuccess(raw, fallback: "启动失败")
    }

    func stopBoot(bootId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/boot/stopBoot", query: ["bootId": "\(bootId)"])
        let raw = try await client.getJSON(url)
        try BootJSON.ensureSuccess(raw, fallback: "停止失败")
    }

    func cloneBoot(bootId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/boot/startCloneBoot", query: ["bootId": "\(bootId)"])
        let raw = try await client.getJSON(url)
        try BootJSON.ensureSuccess(raw, fallback: "克隆失败")
    }

    func deleteBoot(bootId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/boot/deleteBoot", query: ["bootId": "\(bootId)"])
        let raw = try await client.getJSON(url)
        try BootJSON.ensureSuccess(raw, fallback: "删除失败")
    }

    func manualBoot(bootId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/boot/manualBoot", query: ["bootId": "\(bootId)"])
        let raw = try await client.getJSON(url)
        try BootJSON.ensureSuccess(raw, fallback: "手动抢机失败")
    }

    func batchStart() async throws {
        let url = try client.makeURL(baseURL, path: "/boot/batchStart")
        let raw = try await client.postJSON(url, body: [:])
        try BootJSON.ensureSuccess(raw, fallback: "批量启动失败")
    }

    func batchStop() async throws {
        let url = try client.makeURL(baseURL, path: "/boot/batchStop")
        let raw = try await client.postJSON(url, body: [:])
        try BootJSON.ensureSuccess(raw, fallback: "批量停止失败")
    }

    func batchInitFailCount() async throws {
        let url = try client.makeURL(baseURL, path: "/boot/batchInitFailCount")
        let raw = try await client.postJSON(url, body: [:])
        try BootJSON.ensureSuccess(raw, fallback: "重置失败次数失败")
    }

    func offlineCount() async throws -> Int64 {
        let url = try client.makeURL(baseURL, path: "/boot/getOfflineCount")
        let raw = try await client.getJSON(url)
        let root = BootJSON.obj(raw) ?? [:]
        return BootJSON.int64(root["count"])
    }

    func startingCount() async throws -> Int64 {
        let url = try client.makeURL(baseURL, path: "/boot/getStartingCount")
        let raw = try await client.getJSON(url)
        let root = BootJSON.obj(raw) ?? [:]
        return BootJSON.int64(root["count"])
    }

    // MARK: - Detail

    func bootDetail(bootId: Int64) async throws -> [BootDetailItem] {
        let url = try client.makeURL(baseURL, path: "/boot/bootDetail", query: ["bootId": "\(bootId)"])
        let raw = try await client.getJSON(url)
        return try BootJSON.parseDetailList(raw)
    }

    func deleteBootDetail(bootId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/boot/deleteBootDetail", query: ["bootId": "\(bootId)"])
        let raw = try await client.postJSON(url, body: [:])
        try BootJSON.ensureSuccess(raw, fallback: "删除详情失败")
    }

    func toggleStatus(id: Int64, status: Int) async throws {
        let url = try client.makeURL(baseURL, path: "/boot/toggleStatus", query: [
            "id": "\(id)",
            "status": "\(status)"
        ])
        let raw = try await client.postJSON(url, body: [:])
        try BootJSON.ensureSuccess(raw, fallback: "切换状态失败")
    }

    func updateBoot(
        id: Int64,
        ocpu: Int,
        memory: Int,
        disk: Int,
        loopTime: Int,
        rootPassword: String,
        dayGap: String
    ) async throws {
        let url = try client.makeURL(baseURL, path: "/boot/updateBoot")
        let raw = try await client.postJSON(url, body: [
            "id": "\(id)",
            "ocpu": ocpu,
            "memory": memory,
            "disk": disk,
            "loopTime": loopTime,
            "rootPassword": rootPassword,
            "dayGap": dayGap
        ])
        try BootJSON.ensureSuccess(raw, fallback: "更新配置失败")
    }
}
