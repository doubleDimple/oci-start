import Foundation

struct ApiTokenForm: Equatable {
    var tokenName = ""
    var expirationDays = 30
    var description = ""
    var valid: Bool {
        let name = tokenName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.utf16.count <= 255 && description.utf16.count <= 1000 && (1...365).contains(expirationDays)
    }
}

/// Metadata never contains the token; material is fetched explicitly against its revision.
struct ApiTokenStatus: Decodable, Equatable {
    let revision: String
    let tokenName: String
    let description: String
    let enabled: Bool
    let hasToken: Bool
    let isExpired: Bool?
    let expirationDays: Int
    let createdAt: String?
    let expiresAt: String?
    let daysUntilExpiration: Int?
    let allowSwaggerAccess: Bool
    let serverTime: Int64
    let expiresAtEpochMs: Int64?
    let serverTimeZone: String
    var form: ApiTokenForm { ApiTokenForm(tokenName: tokenName, expirationDays: expirationDays, description: description) }
}

struct ApiTokenMaterial {
    let metadata: ApiTokenStatus
    var tokenValue: String
}

struct ApiTokenFailure: LocalizedError {
    let key: String
    var writeAttempted = false
    var errorDescription: String? {
        let messages = ["invalidInput": "请检查名称、描述和有效期", "invalidResponse": "服务器返回的 Token 数据不完整",
                        "conflict": "Token 配置已变化，请刷新并核对最新版本", "notFound": "Token 已不存在，请刷新",
                        "unauthorized": "登录已失效", "forbidden": "没有执行此操作的权限", "requestFailed": "Token 请求未完成，请检查连接"]
        return messages[key] ?? messages["requestFailed"]
    }
}

enum ApiTokensJSON {
    static func validRevision(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }

    static func state(_ value: Any?) throws -> ApiTokenStatus {
        let keys = ["revision", "tokenName", "description", "enabled", "hasToken", "isExpired", "expirationDays",
                    "createdAt", "expiresAt", "daysUntilExpiration", "allowSwaggerAccess", "serverTime", "expiresAtEpochMs", "serverTimeZone"]
        guard let row = value as? [String: Any], keys.allSatisfy({ row[$0] != nil }),
              let data = try? JSONSerialization.data(withJSONObject: row),
              let state = try? JSONDecoder().decode(ApiTokenStatus.self, from: data),
              validRevision(state.revision), state.tokenName.utf16.count <= 255, state.description.utf16.count <= 1000,
              (1...365).contains(state.expirationDays), state.serverTime > 0, state.serverTimeZone.count <= 100,
              state.daysUntilExpiration == nil || state.daysUntilExpiration! >= 0,
              state.expiresAtEpochMs == nil || state.expiresAtEpochMs! > 0 else { throw ApiTokenFailure(key: "invalidResponse") }
        for date in [state.createdAt, state.expiresAt].compactMap({ $0 }) {
            guard date.range(of: "^\\d{4}-\\d{2}-\\d{2}[ T]\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,9})?$", options: .regularExpression) != nil else {
                throw ApiTokenFailure(key: "invalidResponse")
            }
        }
        return state
    }

    static func material(_ value: Any?) throws -> ApiTokenMaterial {
        guard let row = value as? [String: Any], let token = row["tokenValue"] as? String,
              !token.isEmpty, token.count <= 4096, token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            throw ApiTokenFailure(key: "invalidResponse")
        }
        let metadata = try state(row["metadata"])
        guard metadata.hasToken else { throw ApiTokenFailure(key: "invalidResponse") }
        return ApiTokenMaterial(metadata: metadata, tokenValue: token)
    }
}
