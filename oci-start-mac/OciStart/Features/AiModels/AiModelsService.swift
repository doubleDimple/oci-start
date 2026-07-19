import Foundation

struct AiModelsService {
    let baseURL: String
    private let client = APIClient.shared

    func listTenants() async throws -> [AiTenantOption] {
        let url = try client.makeURL(baseURL, path: "/system/ai/tenants")
        let raw = try await client.getJSON(url)
        return AiModelsJSON.parseTenants(raw)
    }

    func listModels(tenantId: String) async throws -> [AiAvailableModel] {
        let url = try client.makeURL(baseURL, path: "/system/ai/modelsByTenant", query: ["tenantId": tenantId])
        let raw = try await client.getJSON(url)
        return AiModelsJSON.parseModels(raw)
    }

    func listConfigs() async throws -> [AiConfigItem] {
        let url = try client.makeURL(baseURL, path: "/system/telegramAiConfigs")
        let raw = try await client.getJSON(url)
        return AiModelsJSON.parseConfigs(raw)
    }

    func addConfig(tenantId: String, model: AiAvailableModel) async throws {
        let url = try client.makeURL(baseURL, path: "/system/updateTelegramAiConfig")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "modelId": model.id,
            "modelName": model.name,
            "provider": model.provider.isEmpty ? "OCI" : model.provider,
            "enabled": true,
            "cloudType": 1
        ])
        // 失败时 body 可能是纯文本
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let msg = obj["message"] as? String,
           (obj["success"] as? Bool) == false {
            throw APIError.serverMessage(msg)
        }
    }

    func toggleConfig(_ item: AiConfigItem, enabled: Bool) async throws {
        let url = try client.makeURL(baseURL, path: "/system/updateTelegramAiConfig")
        _ = try await client.postJSON(url, body: [
            "id": item.id,
            "tenantId": item.tenantId,
            "modelId": item.modelId,
            "modelName": item.modelName,
            "provider": item.provider,
            "enabled": enabled,
            "cloudType": 1
        ])
    }

    func deleteConfig(id: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/system/deleteTelegramAiConfig/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (_, http) = try await client.data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage("删除失败 HTTP \(http.statusCode)")
        }
    }

    func batchToggle(enabled: Bool) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/system/batchToggleTelegramAiConfigs")
        let raw = try await client.postJSON(url, body: ["enabled": enabled])
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            return AiModelsJSON.string(obj["message"]).isEmpty
                ? (enabled ? "已批量启用" : "已批量禁用")
                : AiModelsJSON.string(obj["message"])
        }
        return enabled ? "已批量启用" : "已批量禁用"
    }
}
