import Foundation
import CoreFoundation

struct AiTenantOption: Identifiable, Equatable {
    var id = ""
    var name = ""
}

struct AiAvailableModel: Identifiable, Equatable {
    var id = ""
    var name = ""
    var provider = ""
    var tenantId = ""
    var description = ""
    var modelName = ""
    var enabled: Bool?
    var userName = ""

    var displayName: String { !name.isEmpty ? name : !modelName.isEmpty ? modelName : id }
}

/// Presentation fields only. Credentials and advanced options stay in request-local DTOs.
struct AiConfigItem: Identifiable, Equatable {
    var id: Int64 = 0
    var tenantId = ""
    var modelId = ""
    var showModelId = ""
    var modelName = ""
    var provider = ""
    var cloudType: Int?
    var enabled: Bool?
    var userName = ""
    var region = ""

    var displayName: String { !modelName.isEmpty ? modelName : !modelId.isEmpty ? modelId : String(id) }

    func matchesReceipt(_ other: AiConfigItem) -> Bool {
        id == other.id && tenantId == other.tenantId && modelId == other.modelId
            && modelName == other.modelName && provider == other.provider
            && enabled == other.enabled && cloudType == other.cloudType
    }
}

struct AiModelsFailure: Error {
    enum Reason { case invalidInput, invalidResponse, requestFailed, alreadyConfigured, configMissing, saveMismatch }
    let reason: Reason
    var writeAttempted = false

    static func sanitized(_ error: Error, attempted: Bool = false) -> AiModelsFailure {
        if var failure = error as? AiModelsFailure {
            failure.writeAttempted = failure.writeAttempted || attempted
            return failure
        }
        return AiModelsFailure(reason: .requestFailed, writeAttempted: attempted)
    }
}

struct AiModelsBatchReceipt {
    let updatedCount: Int
    let enabled: Bool
}

enum AiModelsJSON {
    static func invalid() -> AiModelsFailure { AiModelsFailure(reason: .invalidResponse) }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data), let row = value as? [String: Any] else { throw invalid() }
        return row
    }
    static func objects(_ data: Data) throws -> [[String: Any]] {
        guard let value = try? JSONSerialization.jsonObject(with: data), let rows = value as? [[String: Any]] else { throw invalid() }
        return rows
    }
    static func text(_ value: Any?) throws -> String {
        guard let value = value, !(value is NSNull) else { return "" }
        guard let text = value as? String else { throw invalid() }
        return text
    }
    static func nullableText(_ value: Any?) throws -> Any {
        guard let value = value, !(value is NSNull) else { return NSNull() }
        guard let text = value as? String else { throw invalid() }
        return text
    }
    static func identifier(_ value: Any?) throws -> String {
        let text: String
        if let value = value as? String { text = value }
        else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { text = value.stringValue }
        else { throw invalid() }
        guard let number = Int64(text), number > 0, String(number) == text else { throw invalid() }
        return text
    }
    static func requireID(_ value: String) throws {
        guard let number = Int64(value), number > 0, String(number) == value else { throw AiModelsFailure(reason: .invalidInput) }
    }
    static func requireText(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !value.contains("\0") else { throw AiModelsFailure(reason: .invalidInput) }
    }
    static func tenantReference(_ value: Any?) throws -> String {
        if value == nil || value is NSNull { return "" }
        if let text = value as? String, text.isEmpty || text == "-1" { return text }
        return try identifier(value)
    }
    static func boolean(_ value: Any?) throws -> Bool? {
        guard let value = value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw invalid() }
        return number.boolValue
    }
    static func integer(_ value: Any?) throws -> Int? {
        guard let value = value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let integer = Int(number.stringValue), integer >= Int(Int32.min), integer <= Int(Int32.max) else { throw invalid() }
        return integer
    }
    static func config(_ row: [String: Any]) throws -> AiConfigItem {
        let id = try identifier(row["id"])
        return try AiConfigItem(id: Int64(id)!, tenantId: tenantReference(row["tenantId"]), modelId: text(row["modelId"]),
                               showModelId: text(row["showModelId"]), modelName: text(row["modelName"]), provider: text(row["provider"]),
                               cloudType: integer(row["cloudType"]), enabled: boolean(row["enabled"]), userName: text(row["userName"]), region: text(row["region"]))
    }
    static func parseTenants(_ data: Data) throws -> [AiTenantOption] {
        let rows = try objects(data).map { try AiTenantOption(id: identifier($0["id"]), name: text($0["name"])) }
        guard Set(rows.map(\.id)).count == rows.count else { throw invalid() }
        return rows
    }
    static func parseModels(_ data: Data, tenantId: String) throws -> [AiAvailableModel] {
        let rows = try objects(data).map { row -> AiAvailableModel in
            let id = try text(row["id"])
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, try identifier(row["tenantId"]) == tenantId else { throw invalid() }
            return try AiAvailableModel(id: id, name: text(row["name"]), provider: text(row["provider"]), tenantId: tenantId,
                                        description: text(row["description"]), modelName: text(row["modelName"]), enabled: boolean(row["enabled"]), userName: text(row["userName"]))
        }
        guard Set(rows.map(\.id)).count == rows.count else { throw invalid() }
        return rows
    }
    static func configDTOs(_ data: Data) throws -> [[String: Any]] {
        let rows = try objects(data)
        let projections = try rows.map { try config($0) }
        guard Set(projections.map(\.id)).count == projections.count else { throw invalid() }
        return rows
    }
    static func parseConfigs(_ data: Data) throws -> [AiConfigItem] {
        try configDTOs(data).map { try config($0) }
    }
}
