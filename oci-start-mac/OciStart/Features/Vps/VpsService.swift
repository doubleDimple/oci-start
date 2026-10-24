import Foundation
import Darwin

/// Canonical Vue resource APIs; the resource list spans all cloud providers.
struct VpsService {
    let baseURL: String
    private let client = APIClient.shared

    func listAll() async throws -> InstancesListResponse {
        let size = 200
        var page = 0, pages = 1
        var total: Int64?
        var rows: [InstanceItem] = []
        var identities = Set<String>()
        repeat {
            let url = try client.makeURL(baseURL, path: "/vps/instances/list/json", query: ["page": "\(page)", "size": "\(size)"])
            let raw = try await client.getJSON(url, headers: ["Cache-Control": "no-cache, no-store"])
            guard let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let content = root["content"] as? [[String: Any]],
                  let current = root["currentPage"] as? Int, current == page,
                  let actualSize = root["size"] as? Int, actualSize == size,
                  let count = root["totalElements"] as? Int64, count >= 0,
                  let pageCount = root["totalPages"] as? Int, pageCount == Int((count + Int64(size) - 1) / Int64(size)),
                  total == nil || total == count,
                  content.count == min(size, max(0, Int(count) - page * size))
            else { throw APIError.invalidResponse }
            total = count
            pages = max(1, pageCount)
            for record in content {
                guard let id = record["id"] as? String, Int64(id).map({ $0 > 0 }) == true,
                      identities.insert(id).inserted else { throw APIError.invalidResponse }
                var item = InstanceJSON.parseItem(record)
                item.onLineEnable = (record["onLineEnable"] as? Int).flatMap { [0, 1].contains($0) ? $0 : nil } ?? -1
                item.cloudType = record["cloudType"] as? Int ?? 0
                if item.publicIps == "0.0.0.0" { item.publicIps = "" }
                if item.architecture == "NONE" { item.architecture = "" }
                rows.append(item)
            }
            page += 1
        } while page < pages
        guard Int64(rows.count) == total else { throw APIError.invalidResponse }
        return InstancesListResponse(content: rows, currentPage: 0, totalPages: pages, totalElements: total ?? 0, size: size)
    }

    func enablePing() async throws -> String { try await operation("enablePing") }
    func disablePing() async throws -> String { try await operation("disablePing") }
    func manualPing() async throws -> String { try await operation("ping") }
    func installMonitor(vpsId: String) async throws -> String { try await operation("install", id: vpsId) }
    func uninstallMonitor(vpsId: String) async throws -> String { try await operation("uninstall", id: vpsId) }

    private func operation(_ kind: String, id: String? = nil) async throws -> String {
        let path = id == nil ? "/vps/instances/\(kind)" : "/api/monitor/\(kind)"
        let url = try client.makeURL(baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let id = id {
            guard Int64(id).map({ $0 > 0 }) == true else { throw APIError.invalidURL }
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("vpsId=\(id)".utf8)
        }
        let body = try await NetworkQualityService.send(request, write: true)
        return body["message"] as? String ?? vpsText("操作已确认", "Operation acknowledged")
    }

    /// Same measurement as the Vue resource list: elapsed time of a completed HTTP request.
    /// Uses a separate ephemeral session so application cookies never reach a monitored IP.
    static func httpLatency(ip: String, run: VpsLatencyRun) async -> Int {
        guard let target = literalIP(from: ip) else { return -1 }
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = target.contains(":") ? "[\(target)]" : target
        parts.path = "/"
        guard let url = parts.url else { return -1 }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 5
        let probe = URLSession(configuration: config, delegate: VpsLatencyRedirectGuard(), delegateQueue: nil)
        guard run.register(probe) else { probe.invalidateAndCancel(); return -1 }
        defer { run.remove(probe); probe.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = Date()
        do {
            let (_, response) = try await probe.compatData(for: request)
            guard response is HTTPURLResponse else { return -1 }
            return max(1, Int(Date().timeIntervalSince(start) * 1000))
        } catch { return -1 }
    }

    private static func literalIP(from source: String) -> String? {
        guard source.utf8.count <= 16384 else { return nil }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [String]
        if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            candidates = values
        } else {
            candidates = trimmed.components(separatedBy: CharacterSet(charactersIn: ",;|").union(.whitespacesAndNewlines))
        }
        for candidate in candidates {
            var ip = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if ip.hasPrefix("["), ip.hasSuffix("]") { ip = String(ip.dropFirst().dropLast()) }
            guard !ip.isEmpty, !ip.contains("%"), !ip.contains("\0") else { continue }
            var v4 = in_addr(), v6 = in6_addr()
            if ip.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 ||
                ip.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 { return ip }
        }
        return nil
    }
}

/// A navigation cancellation closes the real requests, including sessions added concurrently.
final class VpsLatencyRun {
    private let lock = NSLock()
    private var sessions: [ObjectIdentifier: URLSession] = [:]
    private var cancelled = false
    func register(_ session: URLSession) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        sessions[ObjectIdentifier(session)] = session
        return true
    }
    func remove(_ session: URLSession) {
        lock.lock()
        sessions[ObjectIdentifier(session)] = nil
        lock.unlock()
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let pending = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        pending.forEach { $0.invalidateAndCancel() }
    }
}

/// Measure the literal endpoint itself; never follow a redirect to another host.
private final class VpsLatencyRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct NetworkQualityService {
    let baseURL: String
    private let client = APIClient.shared

    func overview() async throws -> NetworkQualityOverview {
        let request = try makeRequest("/api/network-quality/overview")
        let root = try await Self.send(request)
        let overview: NetworkQualityOverview = try Self.decode(root["data"])
        guard overview.legacyDisabled, overview.tasks.count <= 64, overview.agents.count <= 20000,
              overview.latest.count <= 16384, Set(overview.tasks.map(\.id)).count == overview.tasks.count,
              Set(overview.agents.map(\.id)).count == overview.agents.count,
              overview.agents.allSatisfy({ $0.id == $0.instanceId }),
              Set(overview.latest.map { "\($0.instanceId):\($0.taskId)" }).count == overview.latest.count
        else { throw APIError.invalidResponse }
        return overview
    }

    func history(instance: String, task: NetworkQualityTask, hours: Int) async throws -> NetworkQualityHistory {
        let request = try makeRequest("/api/network-quality/history", query: [
            "instanceId": instance, "taskId": task.id, "revision": task.version, "hours": "\(hours)"
        ])
        let root = try await Self.send(request)
        let history: NetworkQualityHistory = try Self.decode(root["data"])
        guard history.instanceId == instance, history.taskId == task.id, history.revision == task.version,
              history.hours == hours, history.from <= history.to, history.points.count <= 720,
              history.totalPoints >= history.points.count, history.truncated == (history.totalPoints > history.points.count),
              history.stats.count == history.totalPoints,
              history.points.allSatisfy({ $0.instanceId == instance && $0.taskId == task.id && $0.revision == task.version }),
              Set(history.points.map(\.executionId)).count == history.points.count
        else { throw APIError.invalidResponse }
        return history
    }

    func save(_ task: NetworkQualityTask) async throws -> NetworkQualityTask {
        try task.validate()
        var body = task.payload
        let isNew = task.id.isEmpty
        if !isNew { body["version"] = task.version }
        let path = "/api/network-quality/tasks" + (isNew ? "" : "/\(task.id)")
        let root = try await Self.send(try makeRequest(path, method: isNew ? "POST" : "PUT", body: body), write: true)
        do {
            let saved: NetworkQualityTask = try Self.decode(root["data"])
            guard isNew || saved.id == task.id else { throw APIError.invalidResponse }
            return saved
        } catch {
            throw NetworkQualityMutationError(message: vpsText("服务端结果无法确认，请刷新任务核对后再操作。", "The result is unconfirmed. Refresh tasks and review before another operation."), needsReview: true)
        }
    }

    func delete(_ task: NetworkQualityTask) async throws {
        let root = try await Self.send(try makeRequest("/api/network-quality/tasks/\(task.id)",
                                                       method: "DELETE", query: ["version": task.version]), write: true)
        guard (root["data"] as? [String: Any])?["deleted"] as? Bool == true else {
            throw NetworkQualityMutationError(message: vpsText("删除结果未知，请刷新核对。", "Deletion is unconfirmed. Refresh to review."), needsReview: true)
        }
    }

    func run(_ task: NetworkQualityTask) async throws -> String {
        let root = try await Self.send(try makeRequest("/api/network-quality/tasks/\(task.id)/run",
                                                       method: "POST", body: ["version": task.version]), write: true)
        guard let data = root["data"] as? [String: Any], data["status"] as? String == "queued",
              let queued = data["queued"] as? Int, let running = data["alreadyRunning"] as? Int,
              let waiting = data["alreadyQueued"] as? Int, let requested = data["requested"] as? Int,
              queued >= 0, running >= 0, waiting >= 0, requested > 0,
              requested == queued + running + waiting else {
            throw NetworkQualityMutationError(message: vpsText("提交结果未知，请核对任务结果，勿重复提交。", "Submission is unconfirmed. Review task results before submitting again."), needsReview: true)
        }
        return vpsText("已排队 \(queued) · 运行中 \(running) · 等待中 \(waiting)", "Queued \(queued) · Running \(running) · Waiting \(waiting)")
    }

    private func makeRequest(_ path: String, method: String = "GET", query: [String: String] = [:], body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: try client.makeURL(baseURL, path: path, query: query))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func decode<T: Decodable>(_ value: Any?) throws -> T {
        guard let value = value, JSONSerialization.isValidJSONObject(value) else { throw APIError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }

    static func send(_ request: URLRequest, write: Bool = false) async throws -> [String: Any] {
        do {
            let (data, http) = try await APIClient.shared.data(for: request)
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetworkQualityMutationError(message: vpsText("服务端响应无效。", "Invalid server response."), needsReview: write)
            }
            guard (200..<300).contains(http.statusCode), root["success"] as? Bool == true else {
                let code = root["errorKey"] as? String ?? ""
                let rejected = ["invalidInput", "notFound", "conflict", "unauthorized", "forbidden", "expired", "limitExceeded"].contains(code)
                let message: String
                if code == "conflict" { message = vpsText("任务已被修改，请刷新后核对当前版本。", "The task changed. Refresh and review its current version.") }
                else if http.statusCode == 404 { message = vpsText("接口不存在，请升级服务端。", "API unavailable. Upgrade the server.") }
                else { message = root["message"] as? String ?? vpsText("请求失败。", "Request failed.") }
                throw NetworkQualityMutationError(message: message, needsReview: write && !rejected)
            }
            return root
        } catch let error as NetworkQualityMutationError { throw error }
        catch {
            throw NetworkQualityMutationError(message: error.localizedDescription, needsReview: write)
        }
    }
}
