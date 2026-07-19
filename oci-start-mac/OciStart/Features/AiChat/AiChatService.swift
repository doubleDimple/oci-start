import Foundation

struct AiChatService {
    let baseURL: String
    private let client = APIClient.shared

    /// 租户下拉（OCI，优先展示）
    func listTenants() async throws -> [AiChatTenantOption] {
        let url = try client.makeURL(baseURL, path: "/tenants/list/json", query: [
            "page": "0",
            "size": "500",
            "cloudType": "1"
        ])
        let raw = try await client.getJSON(url)
        let resp = try JSONDecoder().decode(TenantsListResponse.self, from: raw)
        return resp.content.map {
            AiChatTenantOption(
                id: $0.id,
                name: $0.displayName,
                region: $0.regionEn.isEmpty ? $0.region : $0.regionEn,
                supportAI: $0.supportAI == 1
            )
        }
    }

    func models(tenantId: Int64) async throws -> [AiChatModelOption] {
        let url = try client.makeURL(baseURL, path: "/ai/models", query: ["tenantId": "\(tenantId)"])
        let raw = try await client.getJSON(url)
        let obj = (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
        if let ok = obj["success"] as? Bool, !ok {
            throw APIError.serverMessage((obj["message"] as? String) ?? "获取模型失败")
        }
        let list = (obj["models"] as? [[String: Any]]) ?? []
        return list.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            return AiChatModelOption(
                id: id,
                displayName: (m["displayName"] as? String) ?? id,
                version: (m["version"] as? String) ?? ""
            )
        }
    }
}
