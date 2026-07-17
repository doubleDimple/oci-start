import Foundation

/// Network layer for `/oci/*` instance list + actions. No UI.
struct InstancesService {
    let baseURL: String
    private let client = APIClient.shared

    // MARK: - List / filter

    func list(page: Int, size: Int, tenantId: String?) async throws -> InstancesListResponse {
        var q: [String: String] = [
            "page": "\(page)",
            "size": "\(size)"
        ]
        if let tenantId = tenantId, !tenantId.isEmpty {
            q["tenantId"] = tenantId
        }
        let url = try client.makeURL(baseURL, path: "/oci/list/json", query: q)
        let raw = try await client.getJSON(url)
        return try InstanceJSON.parseList(raw)
    }

    /// 父租户（级联筛选第一级）
    func listParentTenants() async throws -> [TenantRegionOption] {
        let url = try client.makeURL(baseURL, path: "/tenants/listParentTenants")
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantRegionOption].self, from: raw)) ?? []
    }

    /// 区域 / 子租户（筛选第二级，tenantId 过滤实例用这个 id）
    func listRegions(parentId: String) async throws -> [TenantRegionOption] {
        let url = try client.makeURL(baseURL, path: "/tenants/listRegions", query: ["parentId": parentId])
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantRegionOption].self, from: raw)) ?? []
    }

    func exportAll() async throws -> (Data, String?) {
        let url = try client.makeURL(baseURL, path: "/oci/export")
        return try await client.download(url)
    }

    // MARK: - Lifecycle

    func startInstance(localId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/startInstance")
        let raw = try await client.postJSON(url, body: ["instanceId": localId])
        let r = InstanceJSON.successMessage(raw, fallback: "实例启动请求已发送")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    func stopInstance(localId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/stopInstance")
        let raw = try await client.postJSON(url, body: ["instanceId": localId])
        let r = InstanceJSON.successMessage(raw, fallback: "实例停止请求已发送")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    func sendTerminateCode(localId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/sendVerificationCode")
        let raw = try await client.postJSON(url, body: ["instanceId": localId])
        let r = InstanceJSON.successMessage(raw, fallback: "验证码已发送")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    func terminateInstance(localId: String, code: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/terminateInstance")
        let raw = try await client.postJSON(url, body: [
            "instanceId": localId,
            "verificationCode": code
        ])
        let r = InstanceJSON.successMessage(raw, fallback: "实例终止请求已发送")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    // MARK: - Mutate

    func updateName(localId: String, newName: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/updateName")
        let raw = try await client.postJSON(url, body: [
            "instanceId": localId,
            "newName": newName
        ])
        let r = InstanceJSON.successMessage(raw, fallback: "名称已更新")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    func updateRemark(localId: String, remark: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/updateRemark")
        // UpdateRemarkRequest.instanceId is Long
        guard let idNum = Int64(localId) else {
            throw APIError.serverMessage("实例ID无效")
        }
        let raw = try await client.postJSON(url, body: [
            "instanceId": idNum,
            "remark": remark
        ])
        let r = InstanceJSON.successMessage(raw, fallback: "备注已更新")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    func updateConfig(localId: String, cpu: Int, memory: Int) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/updateConfig")
        let raw = try await client.postJSON(url, body: [
            "instanceId": localId,
            "cpu": cpu,
            "memory": memory
        ])
        let r = InstanceJSON.successMessage(raw, fallback: "配置更新成功")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    func updateBootVolume(localId: String, sizeGB: Int64) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/updateBootVolume")
        let raw = try await client.postJSON(url, body: [
            "instanceId": localId,
            "bootVolumeSize": sizeGB,
            "expand": true
        ])
        let r = InstanceJSON.successMessage(raw, fallback: "引导卷更新成功")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    func updateVpu(bootVolumeId: String, tenantId: String, instanceDetailId: String, vpus: Int) async throws -> String {
        guard !bootVolumeId.isEmpty else {
            throw APIError.serverMessage("引导卷 ID 为空，无法更新 VPU")
        }
        let url = try client.makeURL(baseURL, path: "/tenants/update-volumes/\(bootVolumeId)")
        var body: [String: Any] = [
            "vpusPerGB": vpus,
            "tenantId": tenantId
        ]
        if let id = Int64(instanceDetailId) {
            body["instanceDetailId"] = id
        }
        let raw = try await client.putJSON(url, body: body)
        let r = InstanceJSON.successMessage(raw, fallback: "VPU 已更新")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    /// Web changeSpecIp：body.tenantId = 本地 instance_detail 主键
    func changeSpecIp(localId: String, cidrRanges: [String]) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/changeSpecIp")
        guard let tid = Int64(localId) else {
            throw APIError.serverMessage("实例ID无效")
        }
        let raw = try await client.postJSON(url, body: [
            "tenantId": tid,
            "cidrRanges": cidrRanges
        ])
        let r = InstanceJSON.successMessage(raw, fallback: "IP 切换成功")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }

    /// Web enableIpv6：body.tenantId = 本地 instance_detail 主键
    func enableIpv6(localId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/enableIpv6")
        let raw = try await client.postJSON(url, body: ["tenantId": localId])
        let r = InstanceJSON.successMessage(raw, fallback: "IPv6 操作成功")
        if !r.ok { throw APIError.serverMessage(r.message) }
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let details = obj["details"] as? [String: Any],
           let ip = details["ipv6Address"] as? String, !ip.isEmpty {
            return "\(r.message)：\(ip)"
        }
        return r.message
    }

    func deleteLocalRecord(localId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/deleteInstanceRecord")
        guard let id = Int64(localId) else {
            throw APIError.serverMessage("实例ID无效")
        }
        let raw = try await client.postJSON(url, body: ["id": id])
        let r = InstanceJSON.successMessage(raw, fallback: "本地记录已删除")
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }
}
