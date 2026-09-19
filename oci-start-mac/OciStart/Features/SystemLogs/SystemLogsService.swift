import Foundation
import Combine

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
        // 远程主机偶发不自动带 Cookie：显式附上 satoken，避免 SSE 被 302/空流
        if let cookie = client.cookieHeader(for: baseURL), !cookie.isEmpty {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        req.timeoutInterval = 0
        return req
    }
}


// MARK: - Global API audit log (separate from OCI tenancy audit events)

struct GlobalAuditLog: Identifiable {
    let id: Int64
    let username: String
    let title: String
    let method: String
    let requestUri: String
    let actionMethod: String
    let ip: String
    let location: String
    let params: String
    let responseStatus: Int
    let status: Int
    let errorMsg: String
    let costTime: Int64
    let userAgent: String
    let createTime: String

    init(_ object: [String: Any]) throws {
        guard let number = object["id"] as? NSNumber, number.int64Value > 0 else { throw APIError.invalidResponse }
        id = number.int64Value
        username = object["username"] as? String ?? ""
        title = object["title"] as? String ?? ""
        method = object["method"] as? String ?? ""
        requestUri = object["requestUri"] as? String ?? ""
        actionMethod = object["actionMethod"] as? String ?? ""
        ip = object["ip"] as? String ?? ""
        location = object["location"] as? String ?? ""
        params = object["params"] as? String ?? ""
        responseStatus = object["responseStatus"] as? Int ?? 0
        status = object["status"] as? Int ?? -1
        errorMsg = object["errorMsg"] as? String ?? ""
        costTime = (object["costTime"] as? NSNumber)?.int64Value ?? 0
        userAgent = object["userAgent"] as? String ?? ""
        createTime = (object["createTime"] as? String ?? "").replacingOccurrences(of: "T", with: " ")
    }
}

struct GlobalAuditLogService {
    let baseURL: String
    private let client = APIClient.shared

    func list(query: [String: String]) async throws -> (rows: [GlobalAuditLog], total: Int64, pages: Int) {
        let url = try client.makeURL(baseURL, path: "/api/audit-logs", query: query)
        let body = try checked(try await client.getJSON(url))
        guard let data = body["data"] as? [String: Any],
              let records = data["content"] as? [[String: Any]],
              let total = data["totalElements"] as? NSNumber,
              let pages = data["totalPages"] as? Int,
              total.int64Value >= 0, pages >= 0 else { throw APIError.invalidResponse }
        let rows = try records.map(GlobalAuditLog.init)
        guard Set(rows.map(\.id)).count == rows.count else { throw APIError.invalidResponse }
        return (rows, total.int64Value, pages)
    }

    func delete(id: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/api/audit-logs/\(id)")
        _ = try checked(try await client.deleteJSON(url))
    }

    func delete(ids: [Int64]) async throws {
        guard !ids.isEmpty else { return }
        let url = try client.makeURL(baseURL, path: "/api/audit-logs/batch-delete")
        _ = try checked(try await client.postJSON(url, body: ["ids": ids]))
    }

    func clear() async throws {
        let url = try client.makeURL(baseURL, path: "/api/audit-logs/clear")
        _ = try checked(try await client.deleteJSON(url))
    }

    private func checked(_ raw: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else { throw APIError.invalidResponse }
        guard object["success"] as? Bool == true,
              let code = object["code"], ["0", "200"].contains(String(describing: code)) else {
            throw APIError.serverMessage(object["message"] as? String ?? "审计日志操作未完成")
        }
        return object
    }
}

@MainActor
final class GlobalAuditLogsViewModel: ObservableObject {
    @Published var keyword = ""
    @Published var method: String? = nil
    @Published var status: String? = nil
    @Published var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @Published var endDate = Date()
    @Published var pageState = PageState(page: 0, size: 15)
    @Published private(set) var rows: [GlobalAuditLog] = []
    @Published var selectedIDs = Set<Int64>()
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var needsReview = false
    @Published var detail: GlobalAuditLog?
    private var submittedKeyword = ""
    private var generation = 0

    func stop() { generation += 1 }

    func search() {
        submittedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        pageState.goFirst()
        selectedIDs.removeAll()
        Task { await load() }
    }

    func reset() {
        keyword = ""
        method = nil
        status = nil
        startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        endDate = Date()
        search()
    }

    func load() async {
        guard !busy else { return }
        let calendar = Calendar.current
        guard calendar.startOfDay(for: startDate) <= calendar.startOfDay(for: endDate) else {
            error = LanguageManager.shared.text("开始日期不能晚于结束日期。", "The start date must not be after the end date.")
            return
        }
        generation += 1
        let current = generation
        let baseURL = AppSession.shared.serverURL
        let dateFormat = DateFormatter()
        dateFormat.locale = Locale(identifier: "en_US_POSIX")
        dateFormat.dateFormat = "yyyy-MM-dd"
        var query = ["page": "\(pageState.page + 1)", "size": "\(pageState.size)",
                     "startDate": dateFormat.string(from: startDate) + " 00:00:00",
                     "endDate": dateFormat.string(from: endDate) + " 23:59:59"]
        if !submittedKeyword.isEmpty { query["keyword"] = submittedKeyword }
        if let method = method, !method.isEmpty { query["method"] = method }
        if let status = status, !status.isEmpty { query["status"] = status }
        loading = true
        defer { if current == generation { loading = false } }
        do {
            let result = try await GlobalAuditLogService(baseURL: baseURL).list(query: query)
            guard current == generation, baseURL == AppSession.shared.serverURL else { return }
            let requestedPage = pageState.page
            pageState.apply(totalElements: result.total, totalPages: result.pages)
            if result.total == 0 { pageState.page = 0 }
            if requestedPage != pageState.page, result.total > 0 {
                await load()
                return
            }
            rows = result.rows
            loaded = true
            error = nil
            needsReview = false
        } catch {
            if current == generation { self.error = error.localizedDescription }
        }
    }

    enum Removal { case single(Int64), selected([Int64]), all }

    func remove(_ removal: Removal) async {
        guard !busy, !loading, !needsReview else { return }
        generation += 1
        busy = true
        error = nil
        let service = GlobalAuditLogService(baseURL: AppSession.shared.serverURL)
        do {
            switch removal {
            case .single(let id): try await service.delete(id: id); selectedIDs.remove(id)
            case .selected(let ids): try await service.delete(ids: ids); selectedIDs.subtract(ids)
            case .all: try await service.clear(); selectedIDs.removeAll(); pageState.goFirst()
            }
            detail = nil
            needsReview = true
            busy = false
            await load()
        } catch {
            busy = false
            needsReview = true
            self.error = LanguageManager.shared.text("删除结果未确认。请刷新并核对记录后继续：", "Deletion was not confirmed. Refresh and review the records before continuing: ") + error.localizedDescription
        }
    }
}
