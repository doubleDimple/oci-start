import Foundation
import Combine
import AppKit

@MainActor
final class VpsViewModel: ObservableObject {
    @Published private(set) var cards: [VpsCardItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorText: String?
    @Published var searchText = ""
    @Published var showIP = false
    @Published var showTenant = false
    @Published var offlineOnly = false
    @Published private(set) var isLatencyTesting = false
    @Published private(set) var moreMenuOpen = false

    /// 内嵌 SSH 整页（对齐 Web 跳转终端）
    @Published var sshItem: InstanceItem?

    private let session: AppSession
    private var service: VpsService { VpsService(baseURL: session.serverURL) }
    private let monitorWS = NativeWSClient()
    private var heartbeatTimer: Timer?
    private var metricsByToken: [String: VpsLiveMetrics] = [:]

    var totalCount: Int { cards.count }
    var onlineCount: Int { cards.filter(\.isOnline).count }
    var offlineCount: Int { max(0, totalCount - onlineCount) }

    var filteredCards: [VpsCardItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cards.filter { card in
            if offlineOnly && card.isOnline { return false }
            guard !q.isEmpty else { return true }
            let it = card.item
            return it.publicIps.lowercased().contains(q)
                || it.tenancyName.lowercased().contains(q)
                || it.regionName.lowercased().contains(q)
                || it.displayName.lowercased().contains(q)
                || it.architecture.lowercased().contains(q)
                || it.instanceId.lowercased().contains(q)
        }
    }

    init(session: AppSession = .shared) {
        self.session = session
        wireMonitorWS()
    }

    func start() {
        Task { await reload() }
        connectMonitor()
        startHeartbeatWatch()
    }

    func teardown() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        monitorWS.disconnect(reason: nil)
        moreMenuOpen = false
    }

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let resp = try await service.listAll()
            cards = resp.content.map { item in
                var c = VpsCardItem(item: item)
                if let m = metricsByToken[item.instanceId], m.hasData {
                    c.metrics = m
                    c.item.monitorInstalled = true
                } else if item.lastHeartbeatMs > 0 {
                    c.metrics.lastBeatMs = item.lastHeartbeatMs
                }
                return c
            }
            refreshWarnings()
        } catch {
            cards = []
            errorText = error.localizedDescription
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    // MARK: - Actions

    func toggleOfflineFilter() {
        offlineOnly.toggle()
    }

    func toggleShowIP() { showIP.toggle() }
    func toggleShowTenant() { showTenant.toggle() }
    func toggleMoreMenu() { moreMenuOpen.toggle() }
    func closeMoreMenu() { moreMenuOpen = false }

    func enablePing() {
        closeMoreMenu()
        Task {
            isBusy = true
            do {
                ToastCenter.shared.success(try await service.enablePing())
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func disablePing() {
        closeMoreMenu()
        Task {
            isBusy = true
            do {
                ToastCenter.shared.success(try await service.disablePing())
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func manualPing() {
        closeMoreMenu()
        Task {
            isBusy = true
            do {
                ToastCenter.shared.success(try await service.manualPing())
                // 稍后再刷在线状态
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func runLatencyTest() {
        guard !isLatencyTesting else { return }
        isLatencyTesting = true
        for i in cards.indices {
            cards[i].isLatencyTesting = true
            cards[i].latencyMs = nil
        }
        let targets: [(String, String)] = cards.compactMap { card in
            let ip = card.item.publicIps.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ip.isEmpty, ip != "无IP", ip != "无 IP" else { return nil }
            return (card.id, ip)
        }
        Task {
            var results: [String: Int] = [:]
            await withTaskGroup(of: (String, Int).self) { group in
                for (id, ip) in targets {
                    group.addTask {
                        var ms = await VpsService.pingLatency(ip: ip)
                        if ms < 0 { ms = await VpsService.pingLatency(ip: ip) }
                        return (id, ms)
                    }
                }
                for await (id, ms) in group {
                    results[id] = ms
                }
            }
            for i in cards.indices {
                if let ms = results[cards[i].id] {
                    cards[i].latencyMs = ms
                }
                cards[i].isLatencyTesting = false
            }
            isLatencyTesting = false
            ToastCenter.shared.success("延迟测试完成")
        }
    }

    func installMonitor(_ card: VpsCardItem) {
        guard AppAlert.confirm(
            title: "安装监控探针",
            message: "将通过 SSH 连接 \(card.displayIP) 并安装 Agent。"
        ) else { return }
        Task {
            isBusy = true
            do {
                let msg = try await service.installMonitor(vpsId: card.item.id)
                ToastCenter.shared.success(msg)
                if let idx = cards.firstIndex(where: { $0.id == card.id }) {
                    cards[idx].item.monitorInstalled = true
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func uninstallMonitor(_ card: VpsCardItem) {
        guard AppAlert.confirm(
            title: "停止监控？",
            message: "将卸载 \(card.displayIP) 上的 Agent 服务。"
        ) else { return }
        Task {
            isBusy = true
            do {
                let msg = try await service.uninstallMonitor(vpsId: card.item.id)
                ToastCenter.shared.success(msg)
                if let idx = cards.firstIndex(where: { $0.id == card.id }) {
                    cards[idx].item.monitorInstalled = false
                    cards[idx].metrics = VpsLiveMetrics()
                    cards[idx].monitorWarning = false
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func openSSH(_ card: VpsCardItem) {
        FloatingMenuDismiss.all()
        sshItem = card.item
    }

    func closeSSH() {
        sshItem = nil
    }

    func copyIP(_ card: VpsCardItem) {
        let t = card.item.publicIps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            ToastCenter.shared.error("无公网 IP")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
        ToastCenter.shared.success("IP 已复制")
    }

    // MARK: - Monitor WS

    private func wireMonitorWS() {
        monitorWS.onText = { [weak self] text in
            self?.handleMonitorMessage(text)
        }
        monitorWS.onState = { [weak self] state in
            guard let self = self else { return }
            if case .closed = state {
                // 自动重连
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.connectMonitor()
                }
            }
        }
    }

    private func connectMonitor() {
        do {
            let url = try NativeWSURL.make(baseHTTP: session.serverURL, path: "/ws/monitor")
            monitorWS.connect(url: url)
        } catch {
            // 监控非致命
        }
    }

    private func handleMonitorMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String, !token.isEmpty else { return }

        var m = metricsByToken[token] ?? VpsLiveMetrics()
        m.hasData = true
        m.lastBeatMs = Int64(Date().timeIntervalSince1970 * 1000)

        if let cpu = obj["cpu"] as? [String: Any] {
            if let u = cpu["usage"] as? Double { m.cpuPercent = u }
            else if let n = cpu["usage"] as? NSNumber { m.cpuPercent = n.doubleValue }
            if let load = cpu["load"] as? [Any], let first = load.first {
                m.load = "\(first)"
            }
        }
        if let mem = obj["memory"] as? [String: Any] {
            let used = (mem["used"] as? NSNumber)?.doubleValue ?? 0
            let total = (mem["total"] as? NSNumber)?.doubleValue ?? 0
            if total > 0 { m.memPercent = (used / total) * 100 }
        }
        if let disk = obj["disk"] as? [String: Any] {
            let used = (disk["used"] as? NSNumber)?.doubleValue ?? 0
            let total = (disk["total"] as? NSNumber)?.doubleValue ?? 0
            if total > 0 {
                m.diskPercent = (used / total) * 100
                m.diskTotalLabel = VpsFormat.sizeMB(total)
            }
        }
        if let host = obj["host"] as? [String: Any],
           let up = (host["uptime"] as? NSNumber)?.doubleValue {
            m.uptime = VpsFormat.uptime(up)
        }
        if let net = obj["network"] as? [String: Any] {
            let rx = (net["rx_rate"] as? NSNumber)?.doubleValue ?? 0
            let tx = (net["tx_rate"] as? NSNumber)?.doubleValue ?? 0
            m.netRx = VpsFormat.speed(rx)
            m.netTx = VpsFormat.speed(tx)
        }

        metricsByToken[token] = m
        if let idx = cards.firstIndex(where: { $0.item.instanceId == token }) {
            cards[idx].metrics = m
            cards[idx].item.monitorInstalled = true
            cards[idx].monitorWarning = false
        }
    }

    private func startHeartbeatWatch() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.refreshWarnings()
            }
        }
    }

    private func refreshWarnings() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let timeout: Int64 = 12_000
        for i in cards.indices {
            let card = cards[i]
            guard card.item.monitorInstalled, card.isOnline else {
                cards[i].monitorWarning = false
                continue
            }
            let last = card.metrics.lastBeatMs > 0
                ? card.metrics.lastBeatMs
                : card.item.lastHeartbeatMs
            if last > 0, now - last > timeout {
                cards[i].monitorWarning = true
            } else if last > 0 {
                cards[i].monitorWarning = false
            }
        }
    }
}
