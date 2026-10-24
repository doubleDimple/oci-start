import Foundation

struct AiModelsService {
    let baseURL: String
    private let client = APIClient.shared

    func listTenants() async throws -> [AiTenantOption] {
        do {
            let raw = try await read("/system/ai/tenants")
            return try AiModelsJSON.parseTenants(raw)
        }
        catch { throw AiModelsFailure.sanitized(error) }
    }

    func listModels(tenantId: String) async throws -> [AiAvailableModel] {
        try AiModelsJSON.requireID(tenantId)
        do {
            let raw = try await read("/system/ai/modelsByTenant", query: ["tenantId": tenantId])
            return try AiModelsJSON.parseModels(raw, tenantId: tenantId)
        } catch { throw AiModelsFailure.sanitized(error) }
    }

    func listConfigs() async throws -> [AiConfigItem] {
        do {
            let rows = try await readConfigDTOs()
            return try rows.map { try AiModelsJSON.config($0) }
        }
        catch { throw AiModelsFailure.sanitized(error) }
    }

    func addConfig(tenantId: String, model: AiAvailableModel) async throws -> AiConfigItem {
        try AiModelsJSON.requireID(tenantId)
        try AiModelsJSON.requireText(model.id)
        try AiModelsJSON.requireText(model.displayName)
        guard model.tenantId == tenantId, model.provider == "OCI" else { throw AiModelsFailure(reason: .invalidInput) }
        // The existing endpoint has no uniqueness constraint. Preserve its global
        // modelId policy, including disabled rows, with a fresh preflight read.
        let current = try await listConfigs()
        guard !current.contains(where: { $0.modelId == model.id }) else { throw AiModelsFailure(reason: .alreadyConfigured) }
        let body: [String: Any] = ["tenantId": tenantId, "modelId": model.id, "modelName": model.displayName,
                                   "provider": "OCI", "userName": model.userName, "enabled": true, "cloudType": 1]
        do {
            let raw = try await write("/system/updateTelegramAiConfig", body: body)
            let receipt = try AiModelsJSON.config(AiModelsJSON.object(raw))
            guard receipt.tenantId == tenantId, receipt.modelId == model.id, receipt.modelName == model.displayName,
                  receipt.provider == "OCI", receipt.cloudType == 1, receipt.enabled == true else { throw AiModelsJSON.invalid() }
            return receipt
        } catch { throw AiModelsFailure.sanitized(error, attempted: true) }
    }

    func toggleConfig(_ item: AiConfigItem, enabled: Bool) async throws -> AiConfigItem {
        guard item.id > 0 else { throw AiModelsFailure(reason: .invalidInput) }
        let current = try await readConfigDTOs()
        guard let dto = current.first(where: { (try? AiModelsJSON.identifier($0["id"])) == String(item.id) }) else {
            throw AiModelsFailure(reason: .configMissing)
        }
        let before = try AiModelsJSON.config(dto)
        guard before.cloudType == 1 else { throw AiModelsJSON.invalid() }
        // saveOrUpdateConfig replaces omitted advanced fields. Retain a fresh
        // private snapshot in this request only, never in observable UI state.
        // The server has no version/ETag, so concurrent writes are not atomic.
        var body: [String: Any] = ["id": item.id, "tenantId": dto["tenantId"] ?? NSNull(), "cloudType": 1, "enabled": enabled]
        for field in ["modelId", "modelName", "provider", "apiKey", "baseUrl", "systemPrompt"] {
            body[field] = try AiModelsJSON.nullableText(dto[field])
        }
        for field in ["maxTokens", "maxHistoryMessages"] {
            body[field] = try AiModelsJSON.integer(dto[field]).map { $0 as Any } ?? NSNull()
        }
        // temperature is intentionally absent: the current service does not write it.
        do {
            let raw = try await write("/system/updateTelegramAiConfig", body: body)
            let receipt = try AiModelsJSON.config(AiModelsJSON.object(raw))
            guard receipt.id == item.id, receipt.enabled == enabled, receipt.cloudType == 1,
                  receipt.tenantId == before.tenantId, receipt.modelId == before.modelId else { throw AiModelsJSON.invalid() }
            return receipt
        } catch { throw AiModelsFailure.sanitized(error, attempted: true) }
    }

    func deleteConfig(id: Int64) async throws {
        guard id > 0 else { throw AiModelsFailure(reason: .invalidInput) }
        do {
            let raw = try await write("/system/deleteTelegramAiConfig/\(id)", method: "DELETE")
            guard raw.isEmpty else { throw AiModelsJSON.invalid() }
        } catch { throw AiModelsFailure.sanitized(error, attempted: true) }
    }

    func batchToggle(enabled: Bool) async throws -> AiModelsBatchReceipt {
        do {
            let raw = try await write("/system/batchToggleTelegramAiConfigs", body: ["enabled": enabled])
            let body = try AiModelsJSON.object(raw)
            guard try AiModelsJSON.boolean(body["enabled"]) == enabled,
                  let count = try AiModelsJSON.integer(body["updatedCount"]), count >= 0 else { throw AiModelsJSON.invalid() }
            _ = try AiModelsJSON.text(body["message"])
            return AiModelsBatchReceipt(updatedCount: count, enabled: enabled)
        } catch { throw AiModelsFailure.sanitized(error, attempted: true) }
    }

    private func readConfigDTOs() async throws -> [[String: Any]] {
        do {
            let raw = try await read("/system/telegramAiConfigs")
            return try AiModelsJSON.configDTOs(raw)
        }
        catch { throw AiModelsFailure.sanitized(error) }
    }
    private func read(_ path: String, query: [String: String] = [:]) async throws -> Data {
        let url = try client.makeURL(baseURL, path: path, query: query)
        return try await client.getJSON(url)
    }
    private func write(_ path: String, method: String = "POST", body: [String: Any]? = nil) async throws -> Data {
        let url = try client.makeURL(baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 86_400
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let body = body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        // No automatic retries or cancellation. Avoid a short timeout during a mutation.
        let (raw, http) = try await client.data(for: request, longRunning: true)
        if http.statusCode == 404 { throw AiModelsFailure(reason: .configMissing, writeAttempted: true) }
        guard (200..<300).contains(http.statusCode) else { throw AiModelsFailure(reason: .requestFailed, writeAttempted: true) }
        return raw
    }
}
