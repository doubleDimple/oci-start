import SwiftUI

/// Native OCI region latency test (Web: /delayTest)
struct SpeedTestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var clientIP = "—"
    @State private var regions: [SpeedRegion] = []
    @State private var loading = false
    @State private var testing = false
    @State private var bestText = "—"
    @State private var avgText = "—"

    private var ranked: [SpeedRegion] {
        regions.filter { $0.latencyMs != nil && ($0.latencyMs ?? -1) >= 0 }
            .sorted { ($0.latencyMs ?? 99999) < ($1.latencyMs ?? 99999) }
    }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()
            if loading && regions.isEmpty {
                PageLoadingView(message: "加载区域列表…")
            } else if regions.isEmpty {
                EmptyStateView(icon: "gauge", title: "暂无区域数据")
            } else {
                List {
                    ForEach(regions) { r in
                        regionRow(r)
                            .listRowBackground(AppTheme.pageBg(scheme))
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("延迟测试")
        .toolbar {
            ToolbarItem {
                if loading || testing { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: { Task { await runTest() } }) {
                    Label(testing ? "测试中…" : "开始测试", systemImage: "bolt.fill")
                }
                .disabled(testing || regions.isEmpty)
            }
            ToolbarItem {
                Button(action: { Task { await load() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { Task { await load() } }
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            statCard("当前 IP", clientIP)
            statCard("最佳区域", bestText)
            statCard("平均延迟", avgText)
            Spacer()
        }
        .padding(16)
        .background(AppTheme.surface(scheme))
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(AppTheme.muted(scheme))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.text(scheme))
                .lineLimit(2)
        }
        .padding(12)
        .frame(minWidth: 140, alignment: .leading)
        .background(AppTheme.elevated(scheme))
        .cornerRadius(10)
    }

    private func regionRow(_ r: SpeedRegion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.simpleName)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.text(scheme))
                Text(r.code)
                    .font(.caption)
                    .foregroundColor(AppTheme.muted(scheme))
            }
            Spacer()
            if let ms = r.latencyMs {
                if ms < 0 {
                    Text("timeout")
                        .font(.callout)
                        .foregroundColor(AppTheme.muted(scheme))
                } else {
                    Text("\(ms) ms")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(ms < 150 ? AppTheme.success : ms < 300 ? AppTheme.warning : AppTheme.danger)
                }
            } else {
                Text(testing ? "…" : "—")
                    .foregroundColor(AppTheme.muted(scheme))
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let ipTask = appState.network.getCurrentIpDisplay(baseURL: appState.serverURL)
            async let regTask = appState.network.getOracleEndpoints(baseURL: appState.serverURL)
            clientIP = (try? await ipTask) ?? "—"
            let arr = try await regTask
            regions = arr.compactMap { SpeedRegion(dict: $0) }.filter { !$0.endpoint.isEmpty }
            bestText = "—"
            avgText = "—"
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func runTest() async {
        guard !regions.isEmpty else { return }
        testing = true
        defer { testing = false }
        // reset
        var working = regions
        for i in working.indices { working[i].latencyMs = nil }
        regions = working
        bestText = "测试中…"
        avgText = "—"

        let endpoints = working.map { $0.endpoint }
        var results = Array(repeating: -1, count: endpoints.count)
        let maxConcurrent = 6
        var next = 0
        var inFlight = 0

        await withTaskGroup(of: (Int, Int).self) { group in
            while next < endpoints.count || inFlight > 0 {
                while inFlight < maxConcurrent && next < endpoints.count {
                    let idx = next
                    let ep = endpoints[idx]
                    next += 1
                    inFlight += 1
                    group.addTask {
                        let ms = await Self.ping(ep)
                        return (idx, ms)
                    }
                }
                if let (idx, ms) = await group.next() {
                    inFlight -= 1
                    if idx < results.count {
                        results[idx] = ms
                        working[idx].latencyMs = ms
                        regions = working
                        updateStatsFrom(working)
                    }
                }
            }
        }
        regions = working
        updateStatsFrom(working)
        if bestText == "测试中…" { bestText = "—" }
    }

    private func updateStatsFrom(_ list: [SpeedRegion]) {
        let ok = list.compactMap { $0.latencyMs }.filter { $0 >= 0 }
        guard !ok.isEmpty else { return }
        let avg = ok.reduce(0, +) / ok.count
        avgText = "\(avg) ms"
        let ranked = list.filter { ($0.latencyMs ?? -1) >= 0 }
            .sorted { ($0.latencyMs ?? 99999) < ($1.latencyMs ?? 99999) }
        if let best = ranked.first, let ms = best.latencyMs {
            bestText = "\(best.simpleName) (\(ms) ms)"
        }
    }

    /// Mimic web: HEAD timing; fallback GET with short timeout.
    private static func ping(_ urlString: String) async -> Int {
        guard let url = URL(string: urlString) else { return -1 }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        req.httpMethod = "HEAD"
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4
            let session = URLSession(configuration: config)
            _ = try await session.compatData(for: req)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            return max(ms, 1)
        } catch {
            // retry GET
            var getReq = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
            getReq.httpMethod = "GET"
            let start2 = CFAbsoluteTimeGetCurrent()
            do {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 4
                let session = URLSession(configuration: config)
                _ = try await session.compatData(for: getReq)
                return max(Int((CFAbsoluteTimeGetCurrent() - start2) * 1000), 1)
            } catch {
                return -1
            }
        }
    }
}

struct SpeedRegion: Identifiable {
    let id: String
    let code: String
    let simpleName: String
    let endpoint: String
    var latencyMs: Int? // nil=pending, -1=timeout

    init?(dict: [String: Any]) {
        let code = (dict["code"] as? String) ?? (dict["region"] as? String) ?? UUID().uuidString
        let name = (dict["simpleName"] as? String) ?? (dict["name"] as? String) ?? code
        let ep = (dict["endpoint"] as? String) ?? ""
        self.id = code
        self.code = code
        self.simpleName = name
        self.endpoint = ep
        self.latencyMs = nil
    }
}
