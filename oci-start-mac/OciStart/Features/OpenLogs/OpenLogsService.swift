import Foundation

/// Network layer for `/system/openLogs` + `/system/streamLogs`.
struct OpenLogsService {
    let baseURL: String
    private let client = APIClient.shared

    /// `GET /system/openLogs/json` — latest boot-related log lines.
    func fetchHistory(lines: Int = 300) async throws -> [String] {
        let url = try client.makeURL(
            baseURL,
            path: "/system/openLogs/json",
            query: ["lines": "\(lines)"]
        )
        let raw = try await client.getJSON(url)
        if let resp = try? JSONDecoder().decode(OpenLogsHistoryResponse.self, from: raw) {
            if let err = resp.error, !err.isEmpty, resp.lines.isEmpty {
                throw APIError.serverMessage(err)
            }
            return resp.lines
        }
        // Fallback: raw array
        if let arr = try? JSONDecoder().decode([String].self, from: raw) {
            return arr
        }
        return []
    }

    /// Build SSE request for continuous boot log stream.
    func streamRequest() throws -> URLRequest {
        let url = try client.makeURL(
            baseURL,
            path: "/system/streamLogs",
            query: ["isBootLog": "true"]
        )
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.timeoutInterval = 0
        return req
    }
}
