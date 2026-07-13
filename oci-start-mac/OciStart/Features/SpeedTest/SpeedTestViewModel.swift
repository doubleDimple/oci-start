import Foundation
import Combine

/// Web-parity 延迟测试 (`speed_test.ftl`): load regions + client IP, parallel HEAD ping.
@MainActor
final class SpeedTestViewModel: ObservableObject {
    @Published private(set) var regions: [SpeedRegionEndpoint] = []
    @Published private(set) var latency: [String: SpeedLatencyState] = [:]
    @Published private(set) var clientIPText = "测试中…"
    @Published private(set) var bestRegionText = "--"
    @Published private(set) var avgLatencyText = "--"
    @Published private(set) var top5: [SpeedRankItem] = []
    @Published private(set) var isLoadingRegions = false
    @Published private(set) var isTesting = false
    @Published private(set) var errorText: String?
    /// Region currently mid-ping (border highlight like web).
    @Published private(set) var activeCode: String?

    private let session: AppSession
    private var testGeneration = 0

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task {
            await loadClientIP()
            await loadRegions()
            // web: setTimeout(initTest, 500)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await runTest()
        }
    }

    func refresh() async {
        await loadClientIP()
        await loadRegions()
        await runTest()
    }

    // MARK: - Load

    func loadClientIP() async {
        do {
            let raw = try await fetchStringData(path: "/api/getCurrentIp")
            if raw.contains("/") {
                let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
                let ip = parts.first ?? raw
                let loc = parts.count > 1 ? parts[1] : ""
                clientIPText = loc.isEmpty ? ip : "\(ip)  \(loc)"
            } else {
                clientIPText = raw.replacingOccurrences(of: "_", with: ".")
            }
        } catch {
            clientIPText = "error"
        }
    }

    func loadRegions() async {
        isLoadingRegions = true
        errorText = nil
        defer { isLoadingRegions = false }
        do {
            let list = try await fetchRegions(path: "/api/getOracleEndpoint")
            regions = list.filter { !$0.endpoint.isEmpty }
            var map: [String: SpeedLatencyState] = [:]
            for r in regions { map[r.code] = .idle }
            latency = map
        } catch {
            errorText = error.localizedDescription
            regions = []
        }
    }

    // MARK: - Test (web initTest)

    func runTest() async {
        guard !regions.isEmpty else { return }
        testGeneration += 1
        let gen = testGeneration
        isTesting = true
        bestRegionText = "loading..."
        avgLatencyText = "--"
        top5 = []
        activeCode = nil

        var next: [String: SpeedLatencyState] = [:]
        for r in regions { next[r.code] = .testing }
        latency = next

        var green: [SpeedRankItem] = []
        var totalLatency = 0
        var successCount = 0
        var minLatency = 9999
        var bestName = ""

        await withTaskGroup(of: (String, String, Int).self) { group in
            for r in regions {
                group.addTask { [weak self] in
                    guard let self = self else { return (r.code, r.simpleName, -1) }
                    var ms = await self.ping(r.endpoint)
                    if ms != -1 {
                        let retry = await self.ping(r.endpoint)
                        if retry != -1 && retry < ms { ms = retry }
                    }
                    return (r.code, r.simpleName, ms)
                }
            }

            for await (code, simpleName, ms) in group {
                guard gen == testGeneration else { continue }

                if ms != -1 {
                    var lat = latency
                    lat[code] = .ok(ms)
                    latency = lat

                    if ms < 150 {
                        green.append(SpeedRankItem(code: code, name: simpleName, ms: ms))
                        green.sort { $0.ms < $1.ms }
                        top5 = Array(green.prefix(5))
                    }

                    totalLatency += ms
                    successCount += 1
                    if ms < minLatency {
                        minLatency = ms
                        bestName = simpleName
                        bestRegionText = "\(bestName) (\(minLatency)ms)"
                    }
                    if successCount > 0 {
                        avgLatencyText = "\(Int(round(Double(totalLatency) / Double(successCount))))ms"
                    }
                } else {
                    var lat = latency
                    lat[code] = .timeout
                    latency = lat
                }
            }
        }

        guard gen == testGeneration else { return }
        if !bestName.isEmpty {
            bestRegionText = "\(bestName) (\(minLatency)ms)"
        } else if bestRegionText == "loading..." {
            bestRegionText = "--"
        }
        isTesting = false
        activeCode = nil
    }

    /// Browser: `fetch(url, { method: 'HEAD', mode: 'no-cors' })` timing.
    /// Native: HEAD request round-trip; any HTTP response counts as success for timing.
    private func ping(_ urlString: String) async -> Int {
        guard let url = URL(string: urlString) else { return -1 }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 6
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await URLSession.shared.compatData(for: req)
            let ms = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
            return max(1, ms)
        } catch {
            // Network-level failure → timeout like web catch
            return -1
        }
    }

    // MARK: - HTTP helpers

    private func fetchStringData(path: String) async throws -> String {
        let url = try APIClient.shared.makeURL(session.serverURL, path: path)
        let data = try await APIClient.shared.getJSON(url)
        if let env = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let success = (env["success"] as? Bool) ?? true
            if !success {
                throw APIError.serverMessage((env["message"] as? String) ?? "失败")
            }
            if let s = env["data"] as? String { return s }
            if let n = env["data"] as? NSNumber { return n.stringValue }
        }
        if let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r")) {
            return s
        }
        throw APIError.serverMessage("无法解析 IP")
    }

    private func fetchRegions(path: String) async throws -> [SpeedRegionEndpoint] {
        let url = try APIClient.shared.makeURL(session.serverURL, path: path)
        let data = try await APIClient.shared.getJSON(url)
        guard let env = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.serverMessage("无效响应")
        }
        let success = (env["success"] as? Bool) ?? true
        if !success {
            throw APIError.serverMessage((env["message"] as? String) ?? "加载失败")
        }
        let arr = env["data"] as? [[String: Any]] ?? []
        return arr.compactMap { d in
            let code = (d["code"] as? String) ?? ""
            let endpoint = (d["endpoint"] as? String) ?? ""
            guard !code.isEmpty, !endpoint.isEmpty else { return nil }
            return SpeedRegionEndpoint(
                code: code,
                name: (d["name"] as? String) ?? code,
                simpleName: (d["simpleName"] as? String) ?? code,
                endpoint: endpoint
            )
        }
    }
}
