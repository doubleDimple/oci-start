import Foundation

/// Same guarded reads and conditional writes as Web api/memos.ts.
struct MemoService {
    let baseURL: String
    private let client = APIClient.shared

    func list() async throws -> [MemoItem] {
        do {
            let data = try await read(path: "/api/memos")
            return try MemoJSON.parseList(data)
        } catch { throw failure(error) }
    }

    func get(id: Int64) async throws -> MemoItem {
        guard id > 0 else { throw MemoFailure(key: .invalidInput) }
        do {
            let data = try await read(path: "/api/memos/\(id)", query: [URLQueryItem(name: "guarded", value: "true")])
            return try MemoJSON.parseGuarded(data, id: id)
        } catch { throw failure(error) }
    }

    private func read(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let base = try client.makeURL(baseURL, path: path)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw MemoFailure(key: .invalidInput) }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw MemoFailure(key: .invalidInput) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await client.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw responseFailure(data, status: response.statusCode) }
        return data
    }

    func save(_ draft: MemoFormState) async throws -> MemoItem {
        let form = try draft.normalized()
        if let id = form.id, id <= 0 || !MemoJSON.validRevision(form.revision) {
            throw MemoFailure(key: .invalidInput)
        }
        let path = form.id.map { "/api/memos/\($0)" } ?? "/api/memos"
        var request = URLRequest(url: try client.makeURL(baseURL, path: path))
        request.httpMethod = form.id == nil ? "POST" : "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let revision = form.revision { request.setValue(revision, forHTTPHeaderField: "If-Match") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": form.title, "summary": form.summary, "content": form.content,
            "htmlContent": form.htmlContent.map { $0 as Any } ?? NSNull()
        ])
        request.timeoutInterval = 86_400
        do {
            let (data, response) = try await client.data(for: request, longRunning: true)
            guard (200..<300).contains(response.statusCode) else {
                throw responseFailure(data, status: response.statusCode, writing: true)
            }
            do { return try MemoJSON.parseOneData(data, expectedID: form.id) }
            catch { throw MemoFailure(key: .invalidResponse, writeAttempted: true) }
        } catch { throw failure(error, attempted: true) }
    }

    func delete(_ item: MemoItem) async throws {
        guard item.id > 0, MemoJSON.validRevision(item.revision) else { throw MemoFailure(key: .invalidInput) }
        var request = URLRequest(url: try client.makeURL(baseURL, path: "/api/memos/\(item.id)"))
        request.httpMethod = "DELETE"
        request.setValue(item.revision, forHTTPHeaderField: "If-Match")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.timeoutInterval = 86_400
        do {
            let (data, response) = try await client.data(for: request, longRunning: true)
            guard (200..<300).contains(response.statusCode) else {
                throw responseFailure(data, status: response.statusCode, writing: true)
            }
            guard data.isEmpty || String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true else {
                throw MemoFailure(key: .invalidResponse, writeAttempted: true)
            }
        } catch { throw failure(error, attempted: true) }
    }

    private func responseFailure(_ data: Data, status: Int, writing: Bool = false) -> MemoFailure {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let errorKey = body?["errorKey"] as? String
        let rejected = (status == 400 && errorKey == "invalidInput")
            || (status == 404 && errorKey == "notFound") || (status == 409 && errorKey == "conflict")
        let key: MemoFailure.Key
        switch status {
        case 400: key = .invalidInput
        case 401: key = .unauthorized
        case 403: key = .forbidden
        case 404 where errorKey == "notFound": key = .notFound
        case 409: key = .conflict
        default: key = .requestFailed
        }
        return MemoFailure(key: key, writeAttempted: writing && !rejected)
    }

    private func failure(_ error: Error, attempted: Bool = false) -> MemoFailure {
        if let failure = error as? MemoFailure { return failure }
        if let apiError = error as? APIError, case .unauthorized = apiError {
            return MemoFailure(key: .unauthorized, writeAttempted: attempted)
        }
        return MemoFailure(key: .requestFailed, writeAttempted: attempted)
    }
}
