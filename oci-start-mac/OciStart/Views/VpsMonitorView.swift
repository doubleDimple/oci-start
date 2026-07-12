import SwiftUI

/// Web: /vps/instances/list — same instance data source + batch ping controls
struct VpsMonitorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var filterOnline = false
    @State private var busy = false

    var stats: (total: Int, online: Int, offline: Int) {
        let all = appState.instances
        let on = all.filter { $0.onLineEnable == 1 }.count
        return (all.count, on, all.count - on)
    }

    var filtered: [OciInstance] {
        var list = appState.instances
        if filterOnline { list = list.filter { $0.onLineEnable == 1 } }
        guard !searchText.isEmpty else { return list }
        let q = searchText.lowercased()
        return list.filter {
            ($0.displayName?.lowercased().contains(q) ?? false) ||
            ($0.displayPublicIP.lowercased().contains(q)) ||
            ($0.tenancyName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                monitorStat("总计", count: stats.total, color: AppTheme.text(scheme))
                monitorStat("在线", count: stats.online, color: AppTheme.success)
                monitorStat("离线", count: stats.offline, color: AppTheme.danger)
                Spacer()
                Toggle("仅显示在线", isOn: $filterOnline)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(AppTheme.surface(scheme))

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(AppTheme.muted(scheme)).font(.callout)
                TextField("搜索实例名、IP、租户…", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(AppTheme.muted(scheme))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(AppTheme.elevated(scheme))

            HStack(spacing: 0) {
                Text("状态").frame(width: 70, alignment: .leading)
                Text("实例名").frame(maxWidth: .infinity, alignment: .leading)
                Text("公网 IP").frame(width: 140, alignment: .leading)
                Text("延迟").frame(width: 80, alignment: .leading)
                Text("Ping").frame(width: 60, alignment: .center)
                Text("租户").frame(width: 130, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .font(.caption.weight(.semibold))
            .foregroundColor(AppTheme.muted(scheme))
            .background(AppTheme.elevated(scheme))

            Divider()

            if (appState.vpsLoading || appState.instancesLoading) && appState.instances.isEmpty {
                PageLoadingView()
            } else if filtered.isEmpty {
                EmptyStateView(icon: "list.bullet", title: "暂无数据")
            } else {
                List(filtered) { instance in
                    VpsRowView(instance: instance)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(AppTheme.pageBg(scheme))
                }
                .listStyle(.plain)
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("实例列表")
        .toolbar {
            ToolbarItem {
                Text("\(filtered.count) 台").font(.caption).foregroundColor(AppTheme.muted(scheme))
            }
            ToolbarItem {
                if busy || appState.vpsLoading { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: { Task { await run { await appState.vpsEnablePing() } } }) {
                    Label("启用 Ping", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(busy)
            }
            ToolbarItem {
                Button(action: { Task { await run { await appState.vpsDisablePing() } } }) {
                    Label("停用 Ping", systemImage: "pause.circle")
                }
                .disabled(busy)
            }
            ToolbarItem {
                Button(action: { Task { await run { await appState.vpsPingNow() } } }) {
                    Label("立即 Ping", systemImage: "bolt.horizontal")
                }
                .disabled(busy)
            }
            ToolbarItem {
                Button(action: {
                    Task {
                        appState.vpsLoading = true
                        await appState.loadInstances()
                        appState.vpsLoading = false
                    }
                }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            if appState.instances.isEmpty {
                Task {
                    appState.vpsLoading = true
                    await appState.loadInstances()
                    appState.vpsLoading = false
                }
            }
        }
    }

    private func run(_ work: () async -> Void) async {
        busy = true
        defer { busy = false }
        await work()
    }

    private func monitorStat(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.callout).foregroundColor(AppTheme.muted(scheme))
            Text("\(count)").font(.callout.weight(.semibold)).foregroundColor(AppTheme.text(scheme))
        }
    }
}

struct VpsRowView: View {
    @Environment(\.colorScheme) private var scheme
    let instance: OciInstance

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(instance.onLineEnable == 1 ? AppTheme.success : AppTheme.danger).frame(width: 7, height: 7)
                Text(instance.onLineEnable == 1 ? "在线" : "离线")
                    .font(.caption).foregroundColor(AppTheme.muted(scheme))
            }
            .frame(width: 70, alignment: .leading)

            Text(instance.displayName ?? "—")
                .fontWeight(.medium).lineLimit(1)
                .foregroundColor(AppTheme.text(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(instance.displayPublicIP)
                .font(.system(.callout, design: .monospaced)).lineLimit(1)
                .foregroundColor(AppTheme.text(scheme))
                .frame(width: 140, alignment: .leading)

            Group {
                if let ct = instance.connTime, ct > 0 {
                    Text("\(ct) ms")
                        .foregroundColor(ct < 100 ? AppTheme.success : ct < 300 ? AppTheme.warning : AppTheme.danger)
                } else {
                    Text("—").foregroundColor(AppTheme.muted(scheme))
                }
            }
            .font(.callout)
            .frame(width: 80, alignment: .leading)

            Image(systemName: instance.enablePing == 1 ? "checkmark.circle.fill" : "circle")
                .foregroundColor(instance.enablePing == 1 ? AppTheme.success : AppTheme.muted(scheme))
                .font(.callout)
                .frame(width: 60, alignment: .center)

            Text(instance.displayTenant)
                .font(.caption).foregroundColor(AppTheme.muted(scheme)).lineLimit(1)
                .frame(width: 130, alignment: .leading)
        }
        .padding(.vertical, 7).padding(.horizontal, 16)
    }
}
