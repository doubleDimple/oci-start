import SwiftUI

struct InstancesView: View {
    @EnvironmentObject var appState: AppState

    @State private var searchText = ""
    @State private var instanceToTerminate: OciInstance?
    @State private var showTerminateAlert = false
    @State private var selectedDetail: OciInstance?
    @State private var consoleInstance: OciInstance?

    var filtered: [OciInstance] {
        guard !searchText.isEmpty else { return appState.instances }
        let q = searchText.lowercased()
        return appState.instances.filter {
            ($0.displayName?.lowercased().contains(q) ?? false) ||
            ($0.publicIps?.lowercased().contains(q) ?? false) ||
            ($0.tenancyName?.lowercased().contains(q) ?? false) ||
            ($0.regionName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            columnHeaders
            Divider()
            instanceList
        }
        .navigationTitle("实例列表")
        .toolbar { toolbarItems }
        .alert(isPresented: $showTerminateAlert) {
            Alert(
                title: Text("确认终止实例"),
                message: Text("实例「\(instanceToTerminate?.displayName ?? "")」将被永久删除，此操作不可撤销。"),
                primaryButton: .destructive(Text("终止")) {
                    if let inst = instanceToTerminate {
                        Task { await appState.terminateInstance(inst.instanceId ?? inst.id) }
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            if appState.instances.isEmpty {
                Task { await appState.loadInstances() }
            }
        }
        .sheet(item: $selectedDetail) { inst in
            InstanceDetailView(instance: inst)
                .environmentObject(appState)
        }
        .sheet(item: $consoleInstance) { inst in
            let path = "/oci/console/terminal/\(inst.instanceId ?? inst.id)"
            EmbeddedPageSheet(title: "VNC 控制台 — \(inst.displayName ?? "")", path: path)
                .environmentObject(appState)
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.callout)
            TextField("搜索实例名、IP、租户…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("状态").frame(width: 90, alignment: .leading)
            Text("实例名").frame(maxWidth: .infinity, alignment: .leading)
            Text("公网 IP").frame(width: 140, alignment: .leading)
            Text("配置").frame(width: 110, alignment: .leading)
            Text("租户").frame(width: 130, alignment: .leading)
            Text("操作").frame(width: 170, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var instanceList: some View {
        Group {
            if appState.isLoading && appState.instances.isEmpty {
                centerPlaceholder { ProgressView("加载中…") }
            } else if filtered.isEmpty {
                centerPlaceholder {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(appState.instances.isEmpty ? "暂无实例数据" : "未找到匹配结果")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                List(filtered) { instance in
                    InstanceRowView(
                        instance: instance,
                        onDetail:    { selectedDetail = instance },
                        onConsole:   { consoleInstance = instance },
                        onTerminate: { instanceToTerminate = instance; showTerminateAlert = true }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .listStyle(.plain)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Text("\(filtered.count) 个实例")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        ToolbarItem(placement: .automatic) {
            if appState.isLoading {
                ProgressView().scaleEffect(0.75)
            }
        }
        ToolbarItem(placement: .automatic) {
            Button(action: { Task { await appState.loadInstances() } }) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isLoading)
            .keyboardShortcut("r", modifiers: .command)
            .help("刷新实例列表 (⌘R)")
        }
    }

    private func centerPlaceholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
    }
}

// MARK: - Row

struct InstanceRowView: View {
    @EnvironmentObject var appState: AppState

    let instance: OciInstance
    let onDetail: () -> Void
    let onConsole: () -> Void
    let onTerminate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            stateCell
            nameCell
            ipCell
            shapeCell
            tenantCell
            actionsCell
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.01))
    }

    // State dot + label
    private var stateCell: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text(instance.state ?? "—")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 90, alignment: .leading)
    }

    private var nameCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(instance.displayName ?? "未命名")
                .fontWeight(.medium)
                .lineLimit(1)
            if let remark = instance.remark, !remark.isEmpty {
                Text(remark)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ipCell: some View {
        Text(instance.displayPublicIP)
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .frame(width: 140, alignment: .leading)
    }

    private var shapeCell: some View {
        Text(instance.displayShape)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .frame(width: 110, alignment: .leading)
    }

    private var tenantCell: some View {
        Text(instance.displayTenant)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .frame(width: 130, alignment: .leading)
    }

    private var actionsCell: some View {
        HStack(spacing: 6) {
            Group {
                if instance.isStopped {
                    Button("启动") {
                        Task { await appState.startInstance(instance.instanceId ?? instance.id) }
                    }
                    .buttonStyle(ProminentButton())
                    .controlSize(.small)
                } else if instance.isRunning {
                    Button("停止") {
                        Task { await appState.stopInstance(instance.instanceId ?? instance.id) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(instance.state ?? "—") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(true)
                }
            }
            .frame(width: 52)

            Menu {
                Button("查看详情") { onDetail() }
                Button("VNC 控制台") { onConsole() }
                Divider()
                Button("换 IP") {
                    Task { await appState.changeIP(instance.id) }
                }
                Divider()
                Button("终止实例…") { onTerminate() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("更多操作")
        }
        .frame(width: 170, alignment: .center)
    }

    private var stateColor: Color {
        switch instance.state?.uppercased() {
        case "RUNNING":      return .green
        case "STOPPED":      return .red
        case "PROVISIONING", "STARTING", "STOPPING", "TERMINATING": return .orange
        default:             return .gray
        }
    }
}
