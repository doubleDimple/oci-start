import Foundation

/// Network layer for MFA 备份（`/mfa/page` · `/api/mfa/keys` · `/generate-otp-batch`）。
struct MfaBackupService {
    let baseURL: String
    private let client = APIClient.shared

    func listKeys() async throws -> [MfaKeyItem] {
        let url = try client.makeURL(baseURL, path: "/api/mfa/keys")
        let raw = try await client.getJSON(url)
        return try MfaBackupJSON.parseList(raw)
    }

    func generateOtpBatch(secrets: [String]) async throws -> [String: String] {
        guard !secrets.isEmpty else { return [:] }
        let url = try client.makeURL(baseURL, path: "/generate-otp-batch")
        let raw = try await client.postJSON(url, body: ["secretKeys": secrets])
        return MfaBackupJSON.parseBatchOtp(raw)
    }

    func saveSecret(keyName: String, secretKey: String) async throws {
        let url = try client.makeURL(baseURL, path: "/save-secret")
        let (data, http) = try await client.postForm(url, fields: [
            "keyName": keyName,
            "secretKey": secretKey
        ])
        guard (200..<400).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "保存失败"
            throw APIError.serverMessage(msg.isEmpty ? "保存失败" : msg)
        }
    }

    func deleteKey(keyName: String) async throws {
        let url = try client.makeURL(baseURL, path: "/delete-key")
        let raw = try await client.postJSON(url, body: ["keyName": keyName])
        try MfaBackupJSON.parseDelete(raw)
    }

    func exportCSV() async throws -> (Data, String) {
        let url = try client.makeURL(baseURL, path: "/export-data")
        let (data, name) = try await client.download(url)
        return (data, name ?? "otp_keys.csv")
    }
}
