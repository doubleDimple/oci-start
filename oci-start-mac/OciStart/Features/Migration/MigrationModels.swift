import Foundation

struct MigrationExportResult {
    let data: Data
    let filename: String
    let masterKey: String?
}

enum MigrationJSON {
    static func parseImportMessage(_ data: Data) -> String {
        if data.isEmpty { return "导入成功" }
        if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            return s
        }
        return "导入成功"
    }
}
