import Foundation

struct MfaBackupService {
    let baseURL: String
    private let client = APIClient.shared

    private func request(_ path: String, payload: [String: Any]? = nil, write: Bool = false) async throws -> [String: Any] {
        let url = try client.makeURL(baseURL, path: "/api/mfa" + path)
        var request = URLRequest(url: url)
        request.timeoutInterval = write ? 86_400 : 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let payload = payload {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        do {
            let (raw, http) = try await client.data(for: request, longRunning: write)
            guard http.url == url, http.mimeType == "application/json" else {
                throw MfaBackupFailure(message: "MFA 响应无效", writeAttempted: write)
            }
            let body = try MfaBackupJSON.object(raw, write: write)
            guard (200..<300).contains(http.statusCode) else { throw MfaBackupFailure(message: "MFA 请求失败", writeAttempted: write) }
            return body
        } catch let error as MfaBackupFailure { throw error }
        catch { throw MfaBackupFailure(message: "MFA 请求未完成，请核对服务器连接", writeAttempted: write) }
    }

    func listKeys() async throws -> [MfaKeyItem] {
        let body = try await request("/entries")
        guard let rows = body["data"] as? [[String: Any]], rows.count <= 5000 else { throw APIError.invalidResponse }
        let items = try rows.map(MfaBackupJSON.entry)
        guard Set(items.map(\.id)).count == items.count else { throw APIError.invalidResponse }
        return items
    }

    func codes(ids: [String]) async throws -> (codes: [String: String], validFor: TimeInterval) {
        guard !ids.isEmpty, ids.count <= 100 else { throw APIError.invalidResponse }
        let began = ProcessInfo.processInfo.systemUptime
        let body = try await request("/codes", payload: ["ids": ids])
        guard let server = body["serverTime"] as? Double, let expires = body["expiresAt"] as? Double,
              server > 0, expires > server, expires - server <= 30_000,
              let rows = body["items"] as? [[String: Any]], rows.count == ids.count else { throw APIError.invalidResponse }
        var codes: [String: String] = [:], seen = Set<String>()
        for row in rows {
            let id = MfaBackupJSON.text(row["id"])
            guard ids.contains(id), seen.insert(id).inserted else { throw APIError.invalidResponse }
            if let code = row["code"] as? String,
               code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil, row["errorKey"] == nil || row["errorKey"] is NSNull {
                codes[id] = code
            }
        }
        return (codes, max(0, (expires - server) / 1000 - (ProcessInfo.processInfo.systemUptime - began)))
    }

    func material(_ item: MfaKeyItem) async throws -> MfaMaterial {
        let body = try await request("/entries/\(item.id)/material")
        guard let row = body["data"] as? [String: Any], MfaBackupJSON.text(row["id"]) == item.id,
              let name = row["keyName"] as? String, let issuer = row["issuer"] as? String,
              let secret = row["secretKey"] as? String, let qr = row["qrCode"] as? String,
              MfaBackupJSON.qrImage(from: qr) != nil else { throw APIError.invalidResponse }
        return MfaMaterial(id: item.id, keyName: name, issuer: issuer, secretKey: secret, qrCode: qr)
    }

    func preview(mode: String, name: String, issuer: String, secret: String, uri: String, image: Data?) async throws -> (entries: [MfaCandidate], partial: Bool) {
        guard ["manual", "uri", "image"].contains(mode), name.count <= 255, issuer.count <= 255,
              secret.count <= 1024, uri.utf8.count <= 65_536 else { throw MfaBackupFailure(message: "输入超过允许的长度") }
        if mode == "image", image == nil { throw MfaBackupFailure(message: "请先选择二维码图片") }
        if mode == "uri", uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MfaBackupFailure(message: "请先输入二维码文本") }
        let url = try client.makeURL(baseURL, path: "/api/mfa/preview")
        let raw: Data
        if mode == "image", let image = image {
            guard !image.isEmpty, image.count <= 5 * 1024 * 1024 else { throw MfaBackupFailure(message: "二维码图片不能超过 5 MiB") }
            let boundary = "MfaPreview-\(UUID().uuidString)"
            var payload = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"mode\"\r\n\r\nimage\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"qrCode\"; filename=\"qr-image\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
            payload.append(image); payload.append(Data("\r\n--\(boundary)--\r\n".utf8))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.httpBody = payload
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            let (data, http) = try await client.data(for: request)
            guard http.url == url, http.mimeType == "application/json", (200..<300).contains(http.statusCode) else {
                _ = try MfaBackupJSON.object(data); throw APIError.invalidResponse
            }
            raw = data
        } else {
            let fields = mode == "uri" ? ["mode": "uri", "qrUrl": uri]
                : ["mode": "manual", "keyName": name, "issuer": issuer, "secretKey": secret]
            let (data, http) = try await client.postForm(url, fields: fields)
            guard (200..<300).contains(http.statusCode) else { _ = try MfaBackupJSON.object(data); throw APIError.invalidResponse }
            raw = data
        }
        let body = try MfaBackupJSON.object(raw)
        guard let result = body["data"] as? [String: Any],
              let rows = result["entries"] as? [[String: Any]], !rows.isEmpty, rows.count <= 100,
              let partial = result["partialBatch"] as? Bool else { throw APIError.invalidResponse }
        let entries = try rows.map { row -> MfaCandidate in
            guard let name = row["keyName"] as? String, let issuer = row["issuer"] as? String,
                  let secret = row["secretKey"] as? String, !secret.isEmpty else { throw APIError.invalidResponse }
            return MfaCandidate(keyName: name, issuer: issuer, secretKey: secret)
        }
        return (entries, partial)
    }

    func importEntries(_ entries: [MfaCandidate]) async throws -> String {
        guard !entries.isEmpty, entries.count <= 100 else { throw APIError.invalidResponse }
        let normalized = try entries.map { entry -> [String: String] in
            let name = entry.keyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let issuer = entry.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = entry.secretKey.components(separatedBy: .whitespacesAndNewlines).joined().uppercased()
            guard !name.isEmpty, name.count <= 255, issuer.count <= 255, secret.count <= 255,
                  secret.range(of: "^[A-Z2-7]+={0,6}$", options: .regularExpression) != nil else {
                throw MfaBackupFailure(message: "请检查待导入的名称、发行者与密钥")
            }
            return ["keyName": name, "issuer": issuer, "secretKey": secret]
        }
        let body = try await request("/import", payload: ["entries": normalized], write: true)
        guard let result = body["data"] as? [String: Any],
              let imported = result["importedCount"] as? Int, let preserved = result["preservedCount"] as? Int,
              let total = result["totalCount"] as? Int, imported >= 0, preserved >= 0,
              total == entries.count, imported + preserved == total,
              let ids = result["ids"] as? [String], ids.count == total else {
            throw MfaBackupFailure(message: "缺少完整保存回执，请先核对结果", writeAttempted: true)
        }
        return "已添加 \(imported) 个账户，保留 \(preserved) 个相同账户"
    }

    func delete(_ item: MfaKeyItem) async throws {
        let body = try await request("/entries/\(item.id)/delete", payload: ["revision": item.revision], write: true)
        guard let data = body["data"] as? [String: Any], data["id"] as? String == item.id else {
            throw MfaBackupFailure(message: "缺少删除回执，请先核对结果", writeAttempted: true)
        }
    }

    func exportCSV(ids: [String]) async throws -> Data {
        let body = try await request("/export", payload: ["ids": ids])
        guard let rows = body["data"] as? [[String: Any]], rows.count == ids.count else { throw APIError.invalidResponse }
        var entries: [String: [String: Any]] = [:]
        for row in rows {
            guard let id = row["id"] as? String, ids.contains(id), entries[id] == nil,
                  row["keyName"] is String, row["issuer"] is String, row["secretKey"] is String else { throw APIError.invalidResponse }
            entries[id] = row
        }
        func cell(_ value: String) -> String {
            let probe = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let protected = ["=", "+", "-", "@"].contains(String(probe.prefix(1))) ? "'" + value : value
            return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let lines = try ids.map { id -> String in
            guard let row = entries[id] else { throw APIError.invalidResponse }
            return ["keyName", "issuer", "secretKey"].map { cell(MfaBackupJSON.text(row[$0])) }.joined(separator: ",")
        }
        return Data(("\u{FEFF}Key Name,Issuer,Secret Key\r\n" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
