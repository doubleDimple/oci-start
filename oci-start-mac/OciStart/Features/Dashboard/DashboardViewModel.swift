import Foundation
import Combine

/// Loads `/boot/dashboard-stats` + `/monitor/stats` on the same schedule as web dashboard.js.
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var stats = DashboardStats()
    @Published private(set) var metrics = SystemMetrics()
    @Published private(set) var networkHistory: [NetworkSample] = []
    @Published private(set) var lastUpdateText = "加载中..."
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var monitorTimer: Timer?
    private var statsTimer: Timer?
    private let maxNetworkPoints = 30

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task { await refreshAll() }
        stopTimers()
        // web: monitor 20s, stats 60s
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refreshMetrics()
            }
        }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refreshStats()
            }
        }
        if let monitorTimer = monitorTimer { RunLoop.main.add(monitorTimer, forMode: .common) }
        if let statsTimer = statsTimer { RunLoop.main.add(statsTimer, forMode: .common) }
    }

    func stop() {
        stopTimers()
    }

    func refreshAll() async {
        isLoading = true
        errorText = nil
        async let s: () = refreshStats()
        async let m: () = refreshMetrics()
        _ = await (s, m)
        isLoading = false
    }

    func refreshStats() async {
        do {
            let data = try await fetchEnvelope(path: "/boot/dashboard-stats", as: DashboardStats.self)
            stats = data
        } catch {
            // keep previous; show soft error
            if error is APIError {
                errorText = error.localizedDescription
            }
        }
    }

    func refreshMetrics() async {
        do {
            // Prefer web path used by dashboard.js
            let data = try await fetchEnvelope(path: "/monitor/stats", as: SystemMetrics.self)
            metrics = data
            appendNetwork(upload: data.uploadSpeed, download: data.downloadSpeed)
            if !data.timestamp.isEmpty {
                lastUpdateText = data.timestamp
            } else {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                lastUpdateText = f.string(from: Date())
            }
            errorText = nil
        } catch {
            // Fallback alternate endpoint from DashBoardController
            do {
                let data = try await fetchEnvelope(path: "/boot/stats", as: SystemMetrics.self)
                metrics = data
                appendNetwork(upload: data.uploadSpeed, download: data.downloadSpeed)
                if !data.timestamp.isEmpty {
                    lastUpdateText = data.timestamp
                }
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func appendNetwork(upload: Double, download: Double) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm:ss"
        networkHistory.append(NetworkSample(timeLabel: f.string(from: Date()), upload: upload, download: download))
        if networkHistory.count > maxNetworkPoints {
            networkHistory.removeFirst(networkHistory.count - maxNetworkPoints)
        }
    }

    private func fetchEnvelope<T: Decodable>(path: String, as type: T.Type) async throws -> T {
        let base = session.serverURL
        let url = try APIClient.shared.makeURL(base, path: path)
        let raw = try await APIClient.shared.getJSON(url)
        let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: raw)
        guard envelope.success, let data = envelope.data else {
            throw APIError.serverMessage(envelope.message ?? "请求失败")
        }
        return data
    }

    private func stopTimers() {
        monitorTimer?.invalidate()
        statsTimer?.invalidate()
        monitorTimer = nil
        statsTimer = nil
    }

    deinit {
        monitorTimer?.invalidate()
        statsTimer?.invalidate()
    }
}
