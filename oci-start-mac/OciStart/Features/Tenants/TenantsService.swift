import Foundation

/// Network layer for `/tenants/*` (and related social/email). No UI.
/// Session: sa-token via shared `HTTPCookieStorage` (same as Dashboard/Regions).
struct TenantsService {
    let baseURL: String
    private let client = APIClient.shared

    // MARK: - List

    func list(page: Int, size: Int, keyword: String?, cloudType: Int, emailEnable: Int?) async throws -> TenantsListResponse {
        var q: [String: String] = [
            "page": "\(page)",
            "size": "\(size)",
            "cloudType": "\(cloudType)"
        ]
        if let keyword = keyword, !keyword.isEmpty { q["keyword"] = keyword }
        if let emailEnable = emailEnable { q["emailEnable"] = "\(emailEnable)" }
        let url = try client.makeURL(baseURL, path: "/tenants/list/json", query: q)
        let raw = try await client.getJSON(url)
        return try JSONDecoder().decode(TenantsListResponse.self, from: raw)
    }

    // MARK: - CRUD

    func delete(tenantId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/deleteApi", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        if let r = try? JSONDecoder().decode(TenantBoolMessage.self, from: raw), !r.success {
            throw APIError.serverMessage(r.message.isEmpty ? "删除失败" : r.message)
        }
    }

    func syncOci(tenantId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/syncOci", query: ["tenantId": "\(tenantId)"])
        _ = try await client.getJSON(url)
    }

    func saveTenant(fields: [String: String], keyFileURL: URL) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/save")
        let raw = try await client.postMultipart(url, fields: fields, fileFieldName: "keyFileStr", fileURL: keyFileURL)
        if let env = try? JSONDecoder().decode(TenantApiEnvelope.self, from: raw), !env.ok {
            throw APIError.serverMessage(env.text)
        }
    }

    func updateCustomName(tenantId: Int64, defName: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/updateCustomName")
        let raw = try await client.postJSON(url, body: ["tenantId": "\(tenantId)", "defName": defName])
        try throwIfApiFailed(raw)
    }

    func updateAccountCost(tenantId: Int64, cost: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/updateAccountCost")
        let raw = try await client.postJSON(url, body: ["tenantId": "\(tenantId)", "accountCost": cost])
        try throwIfApiFailed(raw)
    }

    // MARK: - Users

    func listUsers(tenantId: Int64) async throws -> [TenantOracleUser] {
        let url = try client.makeURL(baseURL, path: "/tenants/oracle-users", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantOracleUser].self, from: raw)) ?? []
    }

    func groups(tenantId: Int64) async throws -> [TenantOciGroup] {
        let url = try client.makeURL(baseURL, path: "/tenants/groups")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId])
        return (try? JSONDecoder().decode([TenantOciGroup].self, from: raw)) ?? []
    }

    func createUser(tenantId: Int64, username: String, email: String, groupId: String) async throws -> [String: String] {
        let url = try client.makeURL(baseURL, path: "/tenants/oracle-users")
        var body: [String: Any] = ["tenantId": tenantId, "username": username, "email": email]
        if !groupId.isEmpty { body["groupId"] = groupId }
        let raw = try await client.postJSON(url, body: body)
        let obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
        var out: [String: String] = [:]
        for (k, v) in obj { out[k] = "\(v)" }
        return out
    }

    func resetPassword(tenantId: Int64, userId: String) async throws -> TenantApiEnvelope {
        let url = try client.makeURL(baseURL, path: "/tenants/oracle-users/resetPassword")
        let raw = try await client.postJSON(url, body: ["tenantId": "\(tenantId)", "userId": userId])
        return try JSONDecoder().decode(TenantApiEnvelope.self, from: raw)
    }

    func deleteUser(tenantId: Int64, userId: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/oracle-users/deleteUser")
        let raw = try await client.postJSON(url, body: ["tenantId": "\(tenantId)", "userId": userId])
        try throwIfApiFailed(raw)
    }

    func getPasswordPolicy(tenantId: Int64) async throws -> [TenantPasswordPolicy] {
        let url = try client.makeURL(baseURL, path: "/tenants/oracle-users/getPasspolicy")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId])
        if let env = try? JSONDecoder().decode(TenantApiEnvelope.self, from: raw),
           let data = env.data {
            let listData = try JSONSerialization.data(withJSONObject: jsonObject(data))
            return (try? JSONDecoder().decode([TenantPasswordPolicy].self, from: listData)) ?? []
        }
        return (try? JSONDecoder().decode([TenantPasswordPolicy].self, from: raw)) ?? []
    }

    func updatePasswordPolicy(tenantId: Int64, enable: Bool, days: Int) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/oracle-users/password-policy")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "enablePasswordExpiry": enable,
            "expiryDays": days
        ])
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let ok = obj["success"] as? Bool, !ok {
            throw APIError.serverMessage((obj["message"] as? String) ?? "更新密码策略失败")
        }
    }

    // MARK: - MFA / Notification

    func mfaStatus(tenantId: Int64) async throws -> [String: Any] {
        let url = try client.makeURL(baseURL, path: "/tenants/mfa/status", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        return (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
    }

    func toggleEmailMFA(tenantId: Int64, enable: Bool) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/mfa/email")
        let raw = try await client.postJSON(url, body: ["tenantId": "\(tenantId)", "enableEmail": enable])
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let ok = obj["success"] as? Bool, !ok {
            throw APIError.serverMessage((obj["message"] as? String) ?? "MFA 操作失败")
        }
    }

    func resetAccountFactor(tenantId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/resetAccountFactor", query: ["tenantId": "\(tenantId)"])
        // Controller uses @RequestParam — POST with query
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, http) = try await client.data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage(String(data: data, encoding: .utf8) ?? "重置失败")
        }
        try throwIfApiFailed(data)
    }

    func notificationRecipients(tenantId: Int64) async throws -> [String] {
        let url = try client.makeURL(baseURL, path: "/tenants/notification/recipients")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId])
        let obj = (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
        if let emails = obj["emails"] as? [String] { return emails }
        if let emails = obj["recipients"] as? [String] { return emails }
        if let data = obj["data"] as? [String: Any], let emails = data["emails"] as? [String] { return emails }
        return []
    }

    func updateNotificationRecipients(tenantId: Int64, emails: [String]) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/notification/update")
        let raw = try await client.postJSON(url, body: ["tenantId": "\(tenantId)", "emails": emails])
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let ok = obj["success"] as? Bool, !ok {
            throw APIError.serverMessage((obj["message"] as? String) ?? "更新失败")
        }
    }

    // MARK: - Traffic / Audit / Volumes

    func trafficAlert(tenantId: Int64) async throws -> TenantTrafficAlert {
        let url = try client.makeURL(baseURL, path: "/tenants/traffic-alert/\(tenantId)")
        let raw = try await client.getJSON(url)
        return try JSONDecoder().decode(TenantTrafficAlert.self, from: raw)
    }

    func saveTrafficAlert(tenantId: Int64, threshold: Double, autoShutdown: Bool, stats: Bool) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/traffic-alert")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "threshold": threshold,
            "autoShutdown": autoShutdown,
            "statisticsEnabled": stats,
            "enabled": true
        ])
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let ok = obj["success"] as? Bool, !ok {
            throw APIError.serverMessage((obj["message"] as? String) ?? "保存失败")
        }
    }

    func auditLogs(tenantId: Int64, start: String?, end: String?, pageToken: String?) async throws -> [TenantAuditLogEntry] {
        let url = try client.makeURL(baseURL, path: "/tenants/audit/log")
        var body: [String: Any] = ["tenantId": "\(tenantId)", "days": 7]
        if let start = start, !start.isEmpty { body["startDate"] = start }
        if let end = end, !end.isEmpty { body["endDate"] = end }
        if let pageToken = pageToken, !pageToken.isEmpty { body["pageToken"] = pageToken }
        let raw = try await client.postJSON(url, body: body)
        if let env = try? JSONDecoder().decode(TenantApiEnvelope.self, from: raw), let data = env.data {
            let listData = try JSONSerialization.data(withJSONObject: jsonObject(data))
            if let list = try? JSONDecoder().decode([TenantAuditLogEntry].self, from: listData) { return list }
            if let dict = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
               let items = dict["items"] ?? dict["logs"] ?? dict["content"] {
                let itemData = try JSONSerialization.data(withJSONObject: items)
                return (try? JSONDecoder().decode([TenantAuditLogEntry].self, from: itemData)) ?? []
            }
        }
        return (try? JSONDecoder().decode([TenantAuditLogEntry].self, from: raw)) ?? []
    }

    func bootVolumes(tenantId: Int64) async throws -> [TenantBootVolume] {
        let url = try client.makeURL(baseURL, path: "/tenants/boot-volumes", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantBootVolume].self, from: raw)) ?? []
    }

    func updateBootVolume(tenantId: Int64, volumeId: String, name: String?, vpus: Int64?) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/update-volumes/\(volumeId)")
        var body: [String: Any] = ["tenantId": tenantId]
        if let name = name { body["displayName"] = name }
        if let vpus = vpus { body["vpusPerGB"] = vpus }
        let raw = try await client.putJSON(url, body: body)
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let ok = obj["success"] as? Bool, !ok {
            throw APIError.serverMessage((obj["message"] as? String) ?? "更新失败")
        }
    }

    func deleteBootVolume(tenantId: Int64, volumeId: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/delete-volume/\(volumeId)")
        let raw = try await client.deleteJSON(url, body: ["tenantId": tenantId])
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let ok = obj["success"] as? Bool, !ok {
            throw APIError.serverMessage((obj["message"] as? String) ?? "删除失败")
        }
    }

    // MARK: - Email / Social / Quota

    func emailTenantGet(tenantId: Int64) async throws -> [String: Any] {
        let url = try client.makeURL(baseURL, path: "/email/tenant/get")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId])
        return (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
    }

    func enableEmail(tenantId: Int64, domain: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/email/enable")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId, "emailDomain": domain])
        try throwIfApiFailed(raw)
    }

    func disableEmail(tenantId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/email/disable")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId])
        try throwIfApiFailed(raw)
    }

    func testEmail(tenantId: Int64, testEmail: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/email/test")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId, "testEmail": testEmail])
        try throwIfApiFailed(raw)
    }

    func emailStatus(tenantId: Int64) async throws -> TenantApiEnvelope {
        let url = try client.makeURL(baseURL, path: "/tenants/email/status", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        return try JSONDecoder().decode(TenantApiEnvelope.self, from: raw)
    }

    func socialTypes() async throws -> [String] {
        let url = try client.makeURL(baseURL, path: "/social/availableLoginTypes")
        let raw = try await client.postJSON(url, body: [:])
        if let env = try? JSONDecoder().decode(TenantApiEnvelope.self, from: raw),
           let data = env.data, case .array(let arr) = data {
            return arr.compactMap { $0.stringValue }
        }
        if let arr = try? JSONDecoder().decode([String].self, from: raw) { return arr }
        return []
    }

    func socialList(tenantId: Int64) async throws -> [TenantSocialItem] {
        let url = try client.makeURL(baseURL, path: "/social/list")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId])
        if let env = try? JSONDecoder().decode(TenantApiEnvelope.self, from: raw), let data = env.data {
            let d = try JSONSerialization.data(withJSONObject: jsonObject(data))
            return (try? JSONDecoder().decode([TenantSocialItem].self, from: d)) ?? []
        }
        return (try? JSONDecoder().decode([TenantSocialItem].self, from: raw)) ?? []
    }

    func socialAdd(_ item: TenantSocialItem) async throws {
        let url = try client.makeURL(baseURL, path: "/social/add")
        let raw = try await client.postJSON(url, body: socialBody(item))
        try throwIfApiFailed(raw)
    }

    func socialUpdate(_ item: TenantSocialItem) async throws {
        let url = try client.makeURL(baseURL, path: "/social/update")
        let raw = try await client.postJSON(url, body: socialBody(item))
        try throwIfApiFailed(raw)
    }

    func socialEnable(_ item: TenantSocialItem) async throws {
        let url = try client.makeURL(baseURL, path: "/social/enable")
        let raw = try await client.postJSON(url, body: socialBody(item))
        try throwIfApiFailed(raw)
    }

    func socialDisable(_ item: TenantSocialItem) async throws {
        let url = try client.makeURL(baseURL, path: "/social/disable")
        let raw = try await client.postJSON(url, body: socialBody(item))
        try throwIfApiFailed(raw)
    }

    func listRegions(parentId: Int64) async throws -> [TenantRegionOption] {
        let url = try client.makeURL(baseURL, path: "/tenants/listRegions", query: ["parentId": "\(parentId)"])
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantRegionOption].self, from: raw)) ?? []
    }

    // MARK: - Security rules / MySQL（租户详情页）

    func securityRules(tenantId: Int64, type: String) async throws -> [TenantSecurityRule] {
        let url = try client.makeURL(baseURL, path: "/tenants/security-rules", query: [
            "tenantId": "\(tenantId)",
            "type": type
        ])
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantSecurityRule].self, from: raw)) ?? []
    }

    func addSecurityRule(tenantId: Int64, type: String, protocolValue: String, source: String, ports: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/security-rules")
        let body: [String: Any] = [
            "tenantId": "\(tenantId)",
            "type": type,
            "protocol": protocolValue,
            "source": source,
            "ports": ports
        ]
        let raw = try await client.postJSON(url, body: body)
        try throwIfApiFailed(raw)
    }

    func deleteSecurityRule(compositeId: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/security-rules/\(compositeId)")
        let raw = try await client.deleteJSON(url)
        try throwIfApiFailed(raw)
    }

    func mysqlInfo(tenantId: Int64) async throws -> [TenantMysqlInstance] {
        let url = try client.makeURL(baseURL, path: "/tenants/mysql-info", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        if let env = try? JSONDecoder().decode(TenantApiEnvelope.self, from: raw), let data = env.data {
            let d = try JSONSerialization.data(withJSONObject: jsonObject(data))
            return (try? JSONDecoder().decode([TenantMysqlInstance].self, from: d)) ?? []
        }
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let arr = obj["data"] as? [[String: Any]] {
            let d = try JSONSerialization.data(withJSONObject: arr)
            return (try? JSONDecoder().decode([TenantMysqlInstance].self, from: d)) ?? []
        }
        return (try? JSONDecoder().decode([TenantMysqlInstance].self, from: raw)) ?? []
    }

    func syncMysql(tenantId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/sync-mysql", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.postJSON(url, body: [:])
        try throwIfApiFailed(raw)
    }

    func quota(tenantId: Int64, service: String, page: Int, pageSize: Int) async throws -> [String: Any] {
        let url = try client.makeURL(baseURL, path: "/tenants/quota", query: [
            "tenantId": "\(tenantId)",
            "serviceName": service,
            "page": "\(page)",
            "pageSize": "\(pageSize)"
        ])
        let raw = try await client.getJSON(url)
        return (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
    }

    // MARK: - Export / Import

    func sendExportCode() async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/verify/sendExportCode")
        _ = try await client.postJSON(url, body: [:])
    }

    func exportAll(code: String) async throws -> (Data, String?) {
        let url = try client.makeURL(baseURL, path: "/tenants/export")
        return try await client.download(url, headers: ["X-Verify-Code": code])
    }

    func exportTenant(id: Int64, code: String) async throws -> (Data, String?) {
        let url = try client.makeURL(baseURL, path: "/tenants/exportByTenant", query: ["id": "\(id)"])
        return try await client.download(url, headers: ["X-Verify-Code": code])
    }

    func importJSON(_ data: Data) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/import")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.serverMessage("JSON 格式应为对象数组")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try JSONSerialization.data(withJSONObject: obj)
        let (resp, http) = try await client.data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage(String(data: resp, encoding: .utf8) ?? "导入失败")
        }
    }

    // MARK: - Region detail / subscribe / boot / cost / traffic / AI

    func regionSummary(tenantId: Int64) async throws -> [String: Any] {
        let url = try client.makeURL(baseURL, path: "/tenants/region-summary", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        return (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
    }

    func subscribedRegions(tenantId: Int64) async throws -> [TenantSubscribedRegion] {
        let url = try client.makeURL(baseURL, path: "/tenants/subscribed-regions-data", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantSubscribedRegion].self, from: raw)) ?? []
    }

    func unsubscribedRegions(tenantId: Int64) async throws -> [TenantUnsubscribedRegion] {
        let url = try client.makeURL(baseURL, path: "/tenants/unsubscribed-regions", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantUnsubscribedRegion].self, from: raw)) ?? []
    }

    func subscribeRegions(tenantId: Int64, regionKeys: [String]) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/tenants/subscribe-regions")
        let raw = try await client.postJSON(url, body: ["tenantId": tenantId, "regionKeys": regionKeys])
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            if let ok = obj["success"] as? Bool, !ok {
                throw APIError.serverMessage((obj["message"] as? String) ?? (obj["error"] as? String) ?? "订阅失败")
            }
            return (obj["message"] as? String) ?? "订阅完成"
        }
        return "订阅完成"
    }

    func querySystemImages(tenantId: Int64, shapeType: String) async throws -> [TenantImageInfo] {
        let url = try client.makeURL(baseURL, path: "/tenants/querySystemImages")
        let raw = try await client.postJSON(url, body: ["tenantId": "\(tenantId)", "shapeType": shapeType])
        if let env = try? JSONDecoder().decode(TenantApiEnvelope.self, from: raw), let data = env.data {
            let d = try JSONSerialization.data(withJSONObject: jsonObject(data))
            return (try? JSONDecoder().decode([TenantImageInfo].self, from: d)) ?? []
        }
        return (try? JSONDecoder().decode([TenantImageInfo].self, from: raw)) ?? []
    }

    func saveBootInstance(fields: [String: String]) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/boot/save")
        let (data, http) = try await client.postForm(url, fields: fields)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage(String(data: data, encoding: .utf8) ?? "保存失败")
        }
        try throwIfApiFailed(data)
    }

    func queryCost(tenantId: Int64, start: String, end: String) async throws -> AnyCodableJSON? {
        let url = try client.makeURL(baseURL, path: "/cost/query")
        let raw = try await client.postJSON(url, body: [
            "tenantId": "\(tenantId)",
            "startDate": start,
            "endDate": end
        ])
        let env = try JSONDecoder().decode(TenantApiEnvelope.self, from: raw)
        if !env.ok { throw APIError.serverMessage(env.text) }
        return env.data
    }

    func instanceTraffic(tenantIds: [Int64], start: String, end: String, period: String) async throws -> [TenantTrafficRow] {
        let url = try client.makeURL(baseURL, path: "/monitor/api/instances/traffic")
        let raw = try await client.postJSON(url, body: [
            "tenantIds": tenantIds,
            "startDate": start,
            "endDate": end,
            "period": period
        ])
        return (try? JSONDecoder().decode([TenantTrafficRow].self, from: raw)) ?? []
    }

    func aiModels(tenantId: Int64) async throws -> [TenantAiModel] {
        let url = try client.makeURL(baseURL, path: "/ai/models", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        let obj = (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
        if let ok = obj["success"] as? Bool, !ok {
            throw APIError.serverMessage((obj["message"] as? String) ?? "获取模型失败")
        }
        let list = (obj["models"] as? [[String: Any]]) ?? []
        return list.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            return TenantAiModel(
                id: id,
                displayName: (m["displayName"] as? String) ?? id,
                version: (m["version"] as? String) ?? ""
            )
        }
    }

    // MARK: - SSE helpers (update / account check) — macOS 11 safe (no URLSession.bytes)

    /// Consume SSE until complete/error. `onEvent` may be called off-main.
    func streamSSE(
        path: String,
        query: [String: String] = [:],
        onEvent: @escaping (String, String) -> Void
    ) async throws {
        let url = try client.makeURL(baseURL, path: path, query: query)
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.timeoutInterval = 600
        try await TenantSSEClient.shared.stream(request: req, onEvent: onEvent)
    }

    // MARK: - Private

    private func socialBody(_ item: TenantSocialItem) -> [String: Any] {
        var b: [String: Any] = [
            "tenantId": item.tenantId,
            "clientId": item.clientId,
            "clientSecret": item.clientSecret,
            "socialTypeStr": item.socialTypeStr,
            "thirdLoginAddress": item.thirdLoginAddress,
            "redirectUrl": item.redirectUrl,
            "socialStatus": item.socialStatus,
            "cloudType": item.cloudType
        ]
        if item.id > 0 { b["id"] = item.id }
        return b
    }

    private func throwIfApiFailed(_ raw: Data) throws {
        if let env = try? JSONDecoder().decode(TenantApiEnvelope.self, from: raw), !env.ok {
            throw APIError.serverMessage(env.text)
        }
        if let r = try? JSONDecoder().decode(TenantBoolMessage.self, from: raw), !r.success, !r.message.isEmpty {
            // some endpoints only have success when true
            if r.message.lowercased().contains("fail") || r.message.contains("失败") {
                throw APIError.serverMessage(r.message)
            }
        }
    }

    private func jsonObject(_ j: AnyCodableJSON) -> Any {
        switch j {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map { jsonObject($0) }
        case .object(let o):
            var d: [String: Any] = [:]
            for (k, v) in o { d[k] = jsonObject(v) }
            return d
        }
    }

}
