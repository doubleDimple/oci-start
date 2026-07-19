import Foundation

/// Network layer for `/migration/*` 数据迁移.
struct MigrationService {
    let baseURL: String
    private let client = APIClient.shared

    /// GET `/migration/exportEncrypted` · body + `X-MASTER-KEY`
    func exportEncrypted() async throws -> MigrationExportResult {
        let url = try client.makeURL(baseURL, path: "/migration/exportEncrypted")
        let result = try await client.downloadWithHeaders(url)
        var masterKey: String?
        for (k, v) in result.headers {
            if "\(k)".uppercased() == "X-MASTER-KEY" {
                masterKey = "\(v)"
                break
            }
        }
        let name = result.filename ?? "oci-start_migration_\(Int(Date().timeIntervalSince1970)).enc"
        return MigrationExportResult(data: result.data, filename: name, masterKey: masterKey)
    }

    /// POST `/migration/importEncrypted` multipart
    func importEncrypted(fileURL: URL, masterKey: String?) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/migration/importEncrypted")
        var fields: [String: String] = [:]
        if let key = masterKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            fields["masterKey"] = key
        }
        let raw = try await client.postMultipart(
            url,
            fields: fields,
            fileFieldName: "file",
            fileURL: fileURL
        )
        return MigrationJSON.parseImportMessage(raw)
    }
}
