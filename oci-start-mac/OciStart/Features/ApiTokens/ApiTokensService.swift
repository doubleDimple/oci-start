import Foundation

struct ApiTokensService {
    let baseURL: String
    private let client = APIClient.shared

    private func request<T>(_ path: String, revision: String? = nil, body: [String: Any]? = nil,
                            write: Bool = false, parse: (Any?) throws -> T) async throws -> T {
        if let revision = revision, !ApiTokensJSON.validRevision(revision) { throw ApiTokenFailure(key: "invalidInput") }
        let url = try client.makeURL(baseURL, path: "/api/system" + path)
        var request = URLRequest(url: url)
        request.httpMethod = write ? "POST" : "GET"
        request.timeoutInterval = write ? 86_400 : 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let revision = revision { request.setValue(revision, forHTTPHeaderField: "If-Match") }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        var declaredRejection = false
        do {
            let (raw, http) = try await client.data(for: request, longRunning: write)
            guard http.url == url, http.mimeType == "application/json", raw.count <= 65_536,
                  let root = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
                throw ApiTokenFailure(key: "invalidResponse")
            }
            if (200..<300).contains(http.statusCode), root["success"] as? Bool == true { return try parse(root["data"]) }
            let known = ["invalidInput", "requestFailed", "unauthorized", "forbidden", "notFound", "conflict"]
            if root["success"] as? Bool == false, let key = root["errorKey"] as? String, known.contains(key) {
                declaredRejection = root["writeAttempted"] as? Bool == false
                throw ApiTokenFailure(key: key)
            }
            throw ApiTokenFailure(key: "invalidResponse")
        } catch {
            var failure = (error as? ApiTokenFailure) ?? ApiTokenFailure(key: "requestFailed")
            if case APIError.unauthorized = error { failure = ApiTokenFailure(key: "unauthorized") }
            failure.writeAttempted = write && !declaredRejection
            throw failure
        }
    }

    func fetchConfigs() async throws -> ApiTokenStatus {
        try await request("/apiTokenConfigs", parse: ApiTokensJSON.state)
    }

    func material(revision: String) async throws -> ApiTokenMaterial {
        guard ApiTokensJSON.validRevision(revision) else { throw ApiTokenFailure(key: "invalidInput") }
        return try await request("/apiTokenMaterial?revision=" + revision) { value in
            let result = try ApiTokensJSON.material(value)
            guard result.metadata.revision == revision else { throw ApiTokenFailure(key: "invalidResponse") }
            return result
        }
    }

    func generate(_ form: ApiTokenForm, revision: String) async throws -> ApiTokenMaterial {
        guard form.valid else { throw ApiTokenFailure(key: "invalidInput") }
        return try await request("/generateApiToken", revision: revision, body: [
            "tokenName": form.tokenName.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": form.description, "expirationDays": form.expirationDays, "enabled": true, "allowSwaggerAccess": true
        ], write: true, parse: ApiTokensJSON.material)
    }

    func revoke(revision: String) async throws -> ApiTokenStatus {
        try await request("/revokeApiToken", revision: revision, write: true, parse: ApiTokensJSON.state)
    }
}
