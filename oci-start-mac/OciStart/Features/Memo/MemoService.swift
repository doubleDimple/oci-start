import Foundation

/// Network layer for `/api/memos`.
struct MemoService {
    let baseURL: String
    private let client = APIClient.shared

    func list() async throws -> [MemoItem] {
        let url = try client.makeURL(baseURL, path: "/api/memos")
        let raw = try await client.getJSON(url)
        return try MemoJSON.parseList(raw)
    }

    func create(title: String, summary: String, content: String) async throws -> MemoItem {
        let url = try client.makeURL(baseURL, path: "/api/memos")
        let raw = try await client.postJSON(url, body: [
            "title": title,
            "summary": summary,
            "content": content
        ])
        return try MemoJSON.parseOneData(raw)
    }

    func update(id: Int64, title: String, summary: String, content: String) async throws -> MemoItem {
        let url = try client.makeURL(baseURL, path: "/api/memos/\(id)")
        let raw = try await client.putJSON(url, body: [
            "title": title,
            "summary": summary,
            "content": content
        ])
        return try MemoJSON.parseOneData(raw)
    }

    func delete(id: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/api/memos/\(id)")
        _ = try await client.deleteJSON(url)
    }
}
