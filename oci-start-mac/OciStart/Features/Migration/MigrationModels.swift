import Foundation

struct MigrationExportResult {
    let data: Data
    let filename: String
    let masterKey: String
}

struct MigrationTableResult: Identifiable {
    let table: String
    let importedRows: Int64
    let preservedRows: Int64
    var id: String { table }
}

struct MigrationImportReceipt {
    let formatVersion: Int
    let importedRows: Int64
    let preservedRows: Int64
    let tables: [MigrationTableResult]
}

struct MigrationFailure: LocalizedError {
    enum Outcome: String { case rejected, rolledBack, unknown }
    let message: String
    let outcome: Outcome
    var errorDescription: String? { message }
}

enum MigrationJSON {
    static let maxBackupBytes = 10 * 1024 * 1024

    static func normalizeKey(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed), data.count == 32 else {
            throw MigrationFailure(message: "Master Key 必须是有效的 32 字节 Base64 密钥", outcome: .rejected)
        }
        return data.base64EncodedString()
    }

    static func validateEnvelope(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maxBackupBytes,
              let text = String(data: data, encoding: .utf8) else {
            throw MigrationFailure(message: "请选择不超过 10 MiB 的加密备份文件", outcome: .rejected)
        }
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.count == 4, lines[0] == "-----BEGIN OCI-START MIGRATION-----",
              lines[3] == "-----END OCI-START MIGRATION-----",
              lines[1].hasPrefix("IV:"), lines[2].hasPrefix("DATA:"),
              let iv = Data(base64Encoded: String(lines[1].dropFirst(3))), iv.count == 16,
              let cipher = Data(base64Encoded: String(lines[2].dropFirst(5))),
              cipher.count >= 16, cipher.count % 16 == 0 else {
            throw MigrationFailure(message: "备份文件格式无效，请重新导出 .enc 文件", outcome: .rejected)
        }
    }

    static func parseReceipt(_ data: Data, status: Int) throws -> MigrationImportReceipt {
        let invalid = MigrationFailure(message: "未收到完整导入回执，请在服务器核对结果后再继续", outcome: .unknown)
        guard data.count <= 65_536, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalid }
        if body["success"] as? Bool == false,
           let error = body["error"] as? String,
           let raw = body["outcome"] as? String, let outcome = MigrationFailure.Outcome(rawValue: raw) {
            let messages = [
                "migration.invalidFile": "备份文件无效", "migration.invalidKey": "解密密钥无效",
                "migration.unsupportedFormat": "备份格式不支持，请使用当前版本重新导出",
                "migration.invalidSql": "备份内容无效", "migration.schemaMismatch": "备份与目标数据结构不匹配",
                "migration.duplicateData": "备份与目标存在冲突数据", "migration.limitExceeded": "备份超过允许的大小",
                "migration.importFailed": "导入未完成"
            ]
            if let message = messages[error] { throw MigrationFailure(message: message, outcome: outcome) }
        }
        guard (200..<300).contains(status), body["success"] as? Bool == true,
              let version = body["formatVersion"] as? Int, [1, 2].contains(version),
              let rows = body["tables"] as? [[String: Any]] else { throw invalid }
        func count(_ raw: Any?) throws -> Int64 {
            guard let n = raw as? NSNumber, String(cString: n.objCType) != "c",
                  n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue < Double(Int64.max),
                  n.doubleValue.rounded(.towardZero) == n.doubleValue else { throw invalid }
            return n.int64Value
        }
        let imported = try count(body["importedRows"]), preserved = try count(body["preservedRows"])
        var seen = Set<String>(), totalImported: Int64 = 0, totalPreserved: Int64 = 0
        var tables: [MigrationTableResult] = []
        for row in rows {
            guard let table = row["table"] as? String,
                  table.range(of: "^[A-Za-z][A-Za-z0-9_]{0,127}$", options: .regularExpression) != nil,
                  seen.insert(table).inserted else { throw invalid }
            let added = try count(row["importedRows"]), kept = try count(row["preservedRows"])
            let sumAdded = totalImported.addingReportingOverflow(added), sumKept = totalPreserved.addingReportingOverflow(kept)
            guard !sumAdded.overflow, !sumKept.overflow else { throw invalid }
            totalImported = sumAdded.partialValue; totalPreserved = sumKept.partialValue
            tables.append(MigrationTableResult(table: table, importedRows: added, preservedRows: kept))
        }
        guard totalImported == imported, totalPreserved == preserved, imported > 0 || preserved > 0 else { throw invalid }
        return MigrationImportReceipt(formatVersion: version, importedRows: imported, preservedRows: preserved, tables: tables)
    }
}
