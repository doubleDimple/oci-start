import Foundation

struct MigrationService {
    let baseURL: String
    private let client = APIClient.shared

    func exportEncrypted() async throws -> MigrationExportResult {
        let url = try client.makeURL(baseURL, path: "/migration/exportEncrypted")
        let result = try await client.downloadWithHeaders(url, headers: ["Cache-Control": "no-store"])
        try MigrationJSON.validateEnvelope(result.data)
        let rawKey = result.headers.first { "\($0.key)".uppercased() == "X-MASTER-KEY" }.map { "\($0.value)" } ?? ""
        let key = try MigrationJSON.normalizeKey(rawKey)
        return MigrationExportResult(data: result.data,
            filename: "oci-start_migration_\(Int(Date().timeIntervalSince1970)).enc", masterKey: key)
    }

    /// Submit the exact validated memory snapshot once; never fall back to legacy import.
    func importEncrypted(data: Data, masterKey: String) async throws -> MigrationImportReceipt {
        try MigrationJSON.validateEnvelope(data)
        let key = try MigrationJSON.normalizeKey(masterKey)
        let url = try client.makeURL(baseURL, path: "/migration/importEncryptedResult")
        let boundary = "Migration-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"masterKey\"\r\n\r\n\(key)\r\n".utf8)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"backup.enc\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 86_400
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        do {
            let (raw, response) = try await client.data(for: request, longRunning: true)
            guard response.url == url, response.mimeType == "application/json" else {
                throw MigrationFailure(message: "服务器没有返回导入回执", outcome: .unknown)
            }
            return try MigrationJSON.parseReceipt(raw, status: response.statusCode)
        } catch let failure as MigrationFailure {
            throw failure
        } catch {
            throw MigrationFailure(message: "连接中断或回执缺失，导入结果未知。请先在服务器核对，勿重复提交。", outcome: .unknown)
        }
    }
}
