import SwiftUI

struct VpsMonitorView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var filterOnline = false

    var stats: (total: Int, online: Int, offline: Int) {
        let all = appState.instances
        let on  = all.filter { $0.onLineEnable == 1 }.count
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
            // Summary bar
            HStack(spacing: 24) {
                monitorStat("总计",   count: stats.total,   color: .primary)
                monitorStat("在线",   count: stats.online,  color: .green)
                monitorStat("离线",   count: stats.offline, color: .red)
                Spacer()
                Toggle("仅显示在线", isOn: $filterOnline)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.callout)
                TextField("搜索实例名、IP、租户…", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))

            // Column headers
            HStack(spacing: 0) {
                Text("状态").frame(width: 70, alignment: .leading)
                Text("实例名").frame(maxWidth: .infinity, alignment: .leading)
                Text("公网 IP").frame(width: 140, alignment: .leading)
                Text("延迟").frame(width: 80, alignment: .leading)
                Text("Ping").frame(width: 60, alignment: .center)
                Text("租户").frame(width: 130, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .font(.caption.weight(.semibold)).foregroundColor(.secondary)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if appState.vpsLoading && appState.instances.isEmpty {
                VStack { Spacer(); ProgressView("加载中…"); Spacer() }
            } else if filtered.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "display.2").font(.largeTitle).foregroundColor(.secondary)
                        Text("暂无数据").foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                List(filtered) { instance in
                    VpsRowView(instance: instance)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("资源监控")
        .toolbar {
            ToolbarItem {
                Text("\(filtered.count) 台").font(.caption).foregroundColor(.secondary)
            }
            ToolbarItem {
                if appState.vpsLoading { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: { Task {
                    appState.vpsLoading = true
                    await appState.loadInstances()
                    appState.vpsLoading = false
                }}) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            if appState.instances.isEmpty { Task { await appState.loadInstances() } }
        }
    }

    private func monitorStat(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.callout).foregroundColor(.secondary)
            Text("\(count)").font(.callout.weight(.semibold))
        }
    }
}

struct VpsRowView: View {
    let instance: OciInstance

    var body: some View {
        HStack(spacing: 0) {
            // Online/offline
            HStack(spacing: 4) {
                Circle().fill(instance.onLineEnable == 1 ? Color.green : Color.red).frame(width: 7, height: 7)
                Text(instance.onLineEnable == 1 ? "在线" : "离线")
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(width: 70, alignment: .leading)

            Text(instance.displayName ?? "—")
                .fontWeight(.medium).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(instance.displayPublicIP)
                .font(.system(.callout, design: .monospaced)).lineLimit(1)
                .frame(width: 140, alignment: .leading)

            // Latency
            Group {
                if let ct = instance.connTime, ct > 0 {
                    Text("\(ct) ms")
                        .foregroundColor(ct < 100 ? .green : ct < 300 ? .orange : .red)
                } else {
                    Text("—").foregroundColor(.secondary)
                }
            }
            .font(.callout)
            .frame(width: 80, alignment: .leading)

            // Ping enabled
            Image(systemName: instance.enablePing == 1 ? "checkmark.circle.fill" : "circle")
                .foregroundColor(instance.enablePing == 1 ? .green : .secondary)
                .font(.callout)
                .frame(width: 60, alignment: .center)

            Text(instance.displayTenant)
                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                .frame(width: 130, alignment: .leading)
        }
        .padding(.vertical, 7).padding(.horizontal, 16)
    }
}
