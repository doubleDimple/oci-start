import Foundation

/// Network layer for `/system/logs` + `/system/streamLogs?isBootLog=false`.
struct SystemLogsService {
    let baseURL: String
    private let client = APIClient.shared

    /// GET `/system/logs/json` — latest application log lines.
    func fetchHistory(lines: Int = 300) async throws -> [String] {
        let url = try client.makeURL(
            baseURL,
            path: "/system/logs/json",
            query: ["lines": "\(lines)"]
        )
        let raw = try await client.getJSON(url)
        if let resp = try? JSONDecoder().decode(OpenLogsHistoryResponse.self, from: raw) {
            if let err = resp.error, !err.isEmpty, resp.lines.isEmpty {
                throw APIError.serverMessage(err)
            }
            return resp.lines
        }
        if let arr = try? JSONDecoder().decode([String].self, from: raw) {
            return arr
        }
        return []
    }

    /// SSE request for continuous system log stream (`isBootLog=false`).
    func streamRequest() throws -> URLRequest {
        let url = try client.makeURL(
            baseURL,
            path: "/system/streamLogs",
            query: ["isBootLog": "false"]
        )
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.timeoutInterval = 0
        return req
    }
}
