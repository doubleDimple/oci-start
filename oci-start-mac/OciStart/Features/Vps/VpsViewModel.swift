import Foundation
import Combine
import AppKit
import CoreFoundation

@MainActor
final class VpsViewModel: ObservableObject {
    @Published private(set) var cards: [VpsCardItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorText: String?
    @Published private(set) var requiresReview = false
    @Published private(set) var reviewLoaded = false
    @Published var searchText = ""
    @Published var showIP = false
    @Published var showTenant = false
    @Published var offlineOnly = false
    @Published var provider = ""
    @Published var pageState = PageState(page: 0, size: 20)
    @Published private(set) var isLatencyTesting = false
    @Published var sshItem: InstanceItem?
    @Published private(set) var monitorConnected = false
    private let session: AppSession
    private var service: VpsService { VpsService(baseURL: session.serverURL) }
    private let monitorWS = NativeWSClient()
    private var heartbeatTimer: Timer?
    private var reconnect: DispatchWorkItem?
    private var active = false
    private var loadGeneration = 0
    private var latencyGeneration = 0
    private var latencyRun: VpsLatencyRun?
    private var observed: [String: (token: String, metrics: VpsLiveMetrics)] = [:]

    var totalCount: Int { cards.count }
    var onlineCount: Int { cards.filter(\.isOnline).count }
    var offlineCount: Int { cards.filter { $0.item.onLineEnable == 0 }.count }
    var filteredCards: [VpsCardItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return cards.filter { card in
            if offlineOnly && card.item.onLineEnable != 0 { return false }
            if !provider.isEmpty && "\(card.item.cloudType)" != provider { return false }
            let item = card.item
            return q.isEmpty || [item.publicIps, item.tenancyName, item.regionName, item.displayName,
                                item.architecture, item.instanceId].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
    var visibleCards: [VpsCardItem] {
        Array(filteredCards.dropFirst(pageState.page * pageState.size).prefix(pageState.size))
    }

    init(session: AppSession = .shared) {
        self.session = session
        monitorWS.onText = { [weak self] text in
            guard let self = self else { return }
            Task { @MainActor in self.handleMonitorMessage(text) }
        }
        monitorWS.onState = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in self.monitorState(state) }
        }
    }

    func start() {
        guard !active else { return }
        active = true
        Task { await reload() }
        connectMonitor()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.refreshWarnings() }
        }
    }
    func teardown() {
        active = false
        loadGeneration += 1
        stopLatencyTest()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        reconnect?.cancel()
        reconnect = nil
        monitorConnected = false
        monitorWS.disconnect(reason: nil)
    }
    func updatePagination(reset: Bool = false) {
        if reset { pageState.page = 0 }
        pageState.apply(totalElements: Int64(filteredCards.count))
    }
    func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let response = try await service.listAll()
            guard generation == loadGeneration else { return }
            let previous = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
            cards = response.content.map { item in
                var card = VpsCardItem(item: item)
                if let old = previous[item.id], old.item.instanceId == item.instanceId,
                   !(old.item.monitorInstalled && !item.monitorInstalled),
                   let report = observed[item.id], report.token == item.instanceId {
                    card.metrics = report.metrics
                    card.latencyMs = old.latencyMs
                } else { observed[item.id] = nil }
                return card
            }
            let ids = Set(cards.map(\.id))
            observed = observed.filter { ids.contains($0.key) }
            updatePagination()
            refreshWarnings()
            reviewLoaded = requiresReview
            if !requiresReview { errorText = nil }
        } catch {
            guard generation == loadGeneration else { return }
            errorText = error.localizedDescription
            reviewLoaded = false
        }
    }
    func acknowledgeReview() {
        guard reviewLoaded else { return }
        requiresReview = false
        reviewLoaded = false
        errorText = nil
    }

    func enablePing() { ping("enable") }
    func disablePing() { ping("disable") }
    func manualPing() { ping("manual") }
    private func ping(_ kind: String) {
        guard !isBusy, !requiresReview, AppAlert.confirm(
            title: vpsText("确认全局 Ping 操作", "Confirm global Ping operation"),
            message: vpsText("此操作影响全部 OCI 实例，不受当前搜索或厂商筛选限制。手动检测包含关闭自动 Ping 的实例，并可能发送通知。",
                             "This affects all OCI instances regardless of filters. Manual Ping includes instances with automatic Ping disabled and may send notifications.")
        ) else { return }
        perform {
            switch kind {
            case "enable": return try await self.service.enablePing()
            case "disable": return try await self.service.disablePing()
            default: return try await self.service.manualPing()
            }
        }
    }
    private func perform(_ operation: @escaping () async throws -> String, completed: (() -> Void)? = nil) {
        guard !isBusy, !requiresReview else { return }
        isBusy = true
        Task {
            do {
                let message = try await operation()
                completed?()
                ToastCenter.shared.success(message)
                await reload()
            } catch {
                requiresReview = (error as? NetworkQualityMutationError)?.needsReview ?? true
                reviewLoaded = false
                errorText = error.localizedDescription
            }
            isBusy = false
        }
    }
    func installMonitor(_ card: VpsCardItem) {
        guard AppAlert.confirm(title: vpsText("安装 / 升级监控探针", "Install / upgrade monitoring agent"),
                               message: vpsText("将通过 SSH 在 \(card.item.displayName) 上安装。安装完成后仍需等待真实上报。",
                                                "Install over SSH on \(card.item.displayName). Monitoring becomes available after an actual report.")) else { return }
        perform { try await self.service.installMonitor(vpsId: card.id) }
    }
    func uninstallMonitor(_ card: VpsCardItem) {
        guard AppAlert.confirm(title: vpsText("卸载监控探针", "Uninstall monitoring agent"),
                               message: card.item.displayName) else { return }
        perform({ try await self.service.uninstallMonitor(vpsId: card.id) }, completed: {
            self.observed[card.id] = nil
            if let index = self.cards.firstIndex(where: { $0.id == card.id }) {
                self.cards[index].metrics = VpsLiveMetrics()
                self.cards[index].item.monitorInstalled = false
            }
        })
    }
    func openSSH(_ card: VpsCardItem) { FloatingMenuDismiss.all(); stopLatencyTest(); sshItem = card.item }
    func closeSSH() { sshItem = nil }
    func copyIP(_ card: VpsCardItem) {
        guard !card.item.publicIps.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.item.publicIps, forType: .string)
    }
    func runLatencyTest() {
        guard !isLatencyTesting else { return }
        latencyGeneration += 1
        let generation = latencyGeneration
        latencyRun?.cancel()
        let run = VpsLatencyRun()
        latencyRun = run
        isLatencyTesting = true
        let targets = filteredCards.filter { !$0.item.publicIps.isEmpty }
        Task {
            // Bounded batches avoid occupying all network/worker slots during navigation.
            var offset = 0
            while offset < targets.count, generation == latencyGeneration, active {
                let batch = Array(targets.dropFirst(offset).prefix(4))
                let results = await withTaskGroup(of: (String, Int).self, returning: [(String, Int)].self) { group in
                    for card in batch { group.addTask { (card.id, await VpsService.httpLatency(ip: card.item.publicIps, run: run)) } }
                    var values: [(String, Int)] = []
                    for await value in group { values.append(value) }
                    return values
                }
                guard generation == latencyGeneration, active else { return }
                for (id, value) in results {
                    if let original = targets.first(where: { $0.id == id }),
                       let index = cards.firstIndex(where: { $0.id == id && $0.item.publicIps == original.item.publicIps }) {
                        cards[index].latencyMs = value
                    }
                }
                offset += batch.count
            }
            if generation == latencyGeneration { isLatencyTesting = false }
        }
    }
    func stopLatencyTest() {
        latencyGeneration += 1
        latencyRun?.cancel()
        latencyRun = nil
        isLatencyTesting = false
    }

    func agentLabel(_ card: VpsCardItem) -> String {
        if !monitorConnected { return vpsText("待确认", "Unconfirmed") }
        if card.metrics.hasData { return card.monitorWarning ? vpsText("上报过期", "Stale report") : vpsText("在线", "Online") }
        return card.item.monitorInstalled ? vpsText("等待上报", "Awaiting report") : vpsText("未安装", "Not installed")
    }
    private func connectMonitor() {
        guard active else { return }
        do { monitorWS.connect(url: try NativeWSURL.make(baseHTTP: session.serverURL, path: "/ws/monitor")) }
        catch { monitorConnected = false }
    }
    private func monitorState(_ state: NativeWSClient.State) {
        guard active else { return }
        // NativeWSClient's .open means transport started, not an observed heartbeat.
        if case .open = state { monitorConnected = true }
        if case .closed = state {
            monitorConnected = false
            reconnect?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.connectMonitor() }
            reconnect = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            refreshWarnings()
        }
    }
    private func handleMonitorMessage(_ text: String) {
        guard active, text.utf8.count <= 65536, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["token"] as? String, !token.isEmpty,
              cards.contains(where: { $0.item.instanceId == token }) else { return }
        func number(_ raw: Any?) -> Double? {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
            return number.doubleValue
        }
        func percentage(_ raw: Any?) -> Double? {
            guard let source = raw as? [String: Any], let used = number(source["used"]),
                  let total = number(source["total"]), total > 0, used <= total else { return nil }
            return used / total * 100
        }
        let cpu = object["cpu"] as? [String: Any] ?? [:]
        let host = object["host"] as? [String: Any] ?? [:]
        let disk = object["disk"] as? [String: Any] ?? [:]
        let network = object["network"] as? [String: Any] ?? [:]
        var metrics = VpsLiveMetrics()
        metrics.cpuPercent = number(cpu["usage"]).flatMap { $0 <= 100 ? $0 : nil }
        metrics.memPercent = percentage(object["memory"])
        metrics.diskPercent = percentage(object["disk"])
        metrics.diskTotalLabel = number(disk["total"]).map(VpsFormat.sizeMB) ?? "—"
        metrics.uptime = number(host["uptime"]).map(VpsFormat.uptime) ?? "—"
        metrics.netRx = number(network["rx_rate"]).map(VpsFormat.bytes) ?? "—"
        metrics.netTx = number(network["tx_rate"]).map(VpsFormat.bytes) ?? "—"
        if let load = cpu["load"] as? [Any] {
            metrics.load = load.prefix(3).map { number($0).map { String(format: "%.2f", $0) } ?? "—" }.joined(separator: " / ")
        }
        guard metrics.cpuPercent != nil || metrics.memPercent != nil || metrics.diskPercent != nil ||
                metrics.diskTotalLabel != "—" || metrics.uptime != "—" || metrics.netRx != "—" ||
                metrics.netTx != "—" || (metrics.load != "—" && !metrics.load.isEmpty) else { return }
        metrics.hasData = true
        metrics.lastBeatMs = Int64(Date().timeIntervalSince1970 * 1000)
        for index in cards.indices where cards[index].item.instanceId == token {
            observed[cards[index].id] = (token, metrics)
            cards[index].metrics = metrics
            cards[index].monitorWarning = false
        }
    }
    private func refreshWarnings() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for index in cards.indices {
            let metrics = cards[index].metrics
            cards[index].monitorWarning = metrics.hasData && (!monitorConnected || now - metrics.lastBeatMs > 12000)
        }
    }
}

@MainActor
final class NetworkQualityViewModel: ObservableObject {
    @Published private(set) var overview: NetworkQualityOverview?
    @Published private(set) var history: NetworkQualityHistory?
    @Published private(set) var loading = false
    @Published private(set) var historyLoading = false
    @Published private(set) var busy = false
    @Published private(set) var errorText: String?
    @Published private(set) var requiresReview = false
    @Published private(set) var reviewLoaded = false
    @Published var editor: NetworkQualityTask?
    @Published var selectedInstance = ""
    @Published var selectedTask = ""
    @Published var hours = "24"
    @Published var query = ""
    @Published var pageState = PageState(page: 0, size: 20)
    private var generation = 0
    private var historyGeneration = 0
    private var service: NetworkQualityService { NetworkQualityService(baseURL: AppSession.shared.serverURL) }
    var filteredTasks: [NetworkQualityTask] {
        (overview?.tasks ?? []).filter {
            (selectedInstance.isEmpty || $0.instanceIds.contains(selectedInstance)) &&
            (query.isEmpty || [$0.name, $0.target, $0.region, $0.operatorLabel].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    var visibleTasks: [NetworkQualityTask] { Array(filteredTasks.dropFirst(pageState.page * pageState.size).prefix(pageState.size)) }
    var task: NetworkQualityTask? { overview?.tasks.first { $0.id == selectedTask && $0.instanceIds.contains(selectedInstance) } }
    var canMutate: Bool { overview != nil && !loading && !busy && !requiresReview }

    func refresh() async {
        generation += 1
        let current = generation
        loading = true
        defer { if generation == current { loading = false } }
        do {
            let snapshot = try await service.overview()
            guard generation == current else { return }
            overview = snapshot
            updatePagination()
            reviewLoaded = requiresReview
            if !requiresReview { errorText = nil }
        } catch {
            guard generation == current else { return }
            errorText = error.localizedDescription
            reviewLoaded = false
        }
    }
    func updatePagination(reset: Bool = false) {
        if reset { pageState.page = 0 }
        pageState.apply(totalElements: Int64(filteredTasks.count))
    }
    func openHistory(instance: String, task: NetworkQualityTask? = nil) {
        selectedInstance = instance
        selectedTask = task?.id ?? overview?.tasks.first(where: { $0.instanceIds.contains(instance) })?.id ?? ""
        Task { await loadHistory() }
    }
    func loadHistory() async {
        historyGeneration += 1
        let current = historyGeneration
        history = nil
        guard let task = task, let window = Int(hours) else { return }
        historyLoading = true
        defer { if current == historyGeneration { historyLoading = false } }
        do {
            let result = try await service.history(instance: selectedInstance, task: task, hours: window)
            guard current == historyGeneration else { return }
            history = result
            if !requiresReview { errorText = nil }
        } catch {
            guard current == historyGeneration else { return }
            errorText = error.localizedDescription
        }
    }
    func create(instance: String? = nil) { guard canMutate else { return }; editor = .draft(instanceID: instance) }
    func edit(_ task: NetworkQualityTask) { guard canMutate else { return }; editor = task }
    func closeEditor() {
        guard !busy else { return }
        guard editor == nil || AppAlert.confirm(title: vpsText("放弃未保存的更改？", "Discard unsaved changes?"), message: "") else { return }
        editor = nil
    }
    func save() {
        guard let draft = editor, canMutate else { return }
        do { try draft.validate() } catch { errorText = error.localizedDescription; return }
        guard AppAlert.confirm(title: vpsText("保存检测任务", "Save monitoring task"),
                               message: "\(draft.name)\n\(draft.type.uppercased()) · \(draft.target)\n\(draft.instanceIds.count) " + vpsText("台实例", "instances")) else { return }
        mutate {
            _ = try await self.service.save(draft)
            self.editor = nil
            return vpsText("任务已保存", "Task saved")
        }
    }
    func run(_ task: NetworkQualityTask) {
        guard canMutate, AppAlert.confirm(title: vpsText("执行检测任务", "Run task"), message: "\(task.name) · \(task.instanceIds.count) " + vpsText("台实例", "instances")) else { return }
        mutate { try await self.service.run(task) }
    }
    func toggle(_ task: NetworkQualityTask) {
        guard canMutate, AppAlert.confirm(title: task.enabled ? vpsText("暂停任务", "Pause task") : vpsText("恢复任务", "Resume task"), message: task.name) else { return }
        var changed = task
        changed.enabled.toggle()
        mutate { _ = try await self.service.save(changed); return vpsText("任务已更新", "Task updated") }
    }
    func delete(_ task: NetworkQualityTask) {
        guard canMutate, AppAlert.confirm(title: vpsText("删除检测任务", "Delete task"), message: task.name) else { return }
        mutate { try await self.service.delete(task); return vpsText("任务已删除", "Task deleted") }
    }
    func install(_ agent: NetworkQualityAgent) {
        guard canMutate, AppAlert.confirm(title: vpsText("安装 / 升级探针", "Install / upgrade agent"), message: agent.title) else { return }
        mutate { try await VpsService(baseURL: AppSession.shared.serverURL).installMonitor(vpsId: agent.id) }
    }
    private func mutate(_ operation: @escaping () async throws -> String) {
        guard canMutate else { return }
        busy = true
        Task {
            do {
                ToastCenter.shared.success(try await operation())
                await refresh()
                if !selectedInstance.isEmpty { await loadHistory() }
            } catch {
                requiresReview = (error as? NetworkQualityMutationError)?.needsReview ?? true
                reviewLoaded = false
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
    func acknowledgeReview() {
        guard reviewLoaded else { return }
        requiresReview = false
        reviewLoaded = false
        errorText = nil
    }
    func stop() { generation += 1; historyGeneration += 1 }
}
