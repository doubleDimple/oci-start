import SwiftUI
import AppKit

enum InstanceStateFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case running = "运行中"
    case stopped = "已停止"
    case other = "其他"
    var id: String { rawValue }
}

struct InstancesView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var stateFilter: InstanceStateFilter = .all
    @State private var instanceToTerminate: OciInstance?
    @State private var showTerminateSheet = false
    @State private var selectedDetail: OciInstance?
    @State private var consoleInstance: OciInstance?
    @State private var toolSheet: ToolSheet?

    private struct ToolSheet: Identifiable {
        let id = UUID()
        let title: String
        let path: String
    }

    var filtered: [OciInstance] {
        var list = appState.instances
        switch stateFilter {
        case .all: break
        case .running: list = list.filter(\.isRunning)
        case .stopped: list = list.filter(\.isStopped)
        case .other: list = list.filter { !$0.isRunning && !$0.isStopped }
        }
        guard !searchText.isEmpty else { return list }
        let q = searchText.lowercased()
        return list.filter {
            ($0.displayName?.lowercased().contains(q) ?? false) ||
            ($0.publicIps?.lowercased().contains(q) ?? false) ||
            ($0.tenancyName?.lowercased().contains(q) ?? false) ||
            ($0.regionName?.lowercased().contains(q) ?? false) ||
            ($0.remark?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            columnHeaders
            Divider().background(AppTheme.border(scheme))
            instanceList
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("实例列表")
        .toolbar { toolbarItems }
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
        .sheet(item: $toolSheet) { sheet in
            EmbeddedPageSheet(title: sheet.title, path: sheet.path)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showTerminateSheet) {
            if let inst = instanceToTerminate {
                TerminateInstanceSheet(instance: inst)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.muted(scheme))
                    .font(.callout)
                TextField("搜索实例名、IP、租户、备注…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border(scheme), lineWidth: 1))

            Picker("", selection: $stateFilter) {
                ForEach(InstanceStateFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surface(scheme))
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("状态").frame(width: 90, alignment: .leading)
            Text("实例名").frame(maxWidth: .infinity, alignment: .leading)
            Text("公网 IP").frame(width: 140, alignment: .leading)
            Text("配置").frame(width: 110, alignment: .leading)
            Text("租户").frame(width: 130, alignment: .leading)
            Text("操作").frame(width: 190, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .font(.caption.weight(.semibold))
        .foregroundColor(AppTheme.muted(scheme))
        .background(AppTheme.elevated(scheme))
    }

    private var instanceList: some View {
        Group {
            if appState.instancesLoading && appState.instances.isEmpty {
                PageLoadingView(message: "加载实例…")
            } else if filtered.isEmpty {
                EmptyStateView(
                    icon: "server.rack",
                    title: appState.instances.isEmpty ? "暂无实例数据" : "未找到匹配结果",
                    subtitle: appState.instances.isEmpty ? "添加租户并同步后即可在此管理实例" : "试试调整搜索或筛选条件"
                )
            } else {
                List(filtered) { instance in
                    InstanceRowView(
                        instance: instance,
                        onDetail: { selectedDetail = instance },
                        onConsole: { consoleInstance = instance },
                        onTerminate: {
                            instanceToTerminate = instance
                            showTerminateSheet = true
                        },
                        onSSH: {
                            let id = instance.instanceId ?? instance.id
                            toolSheet = ToolSheet(title: "SSH — \(instance.displayName ?? "")",
                                                  path: "/oci/terminal?instanceId=\(id)")
                        },
                        onRescue: {
                            let id = instance.instanceId ?? instance.id
                            toolSheet = ToolSheet(title: "系统救援 — \(instance.displayName ?? "")",
                                                  path: "/oci/sysHelp?instanceId=\(id)")
                        },
                        onVnic: {
                            let id = instance.instanceId ?? instance.id
                            toolSheet = ToolSheet(title: "网络管理 — \(instance.displayName ?? "")",
                                                  path: "/oci/vnic/manage?instanceId=\(id)")
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(AppTheme.pageBg(scheme))
                }
                .listStyle(.plain)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Text("\(filtered.count) / \(appState.instances.count)")
                .font(.caption)
                .foregroundColor(AppTheme.muted(scheme))
        }
        ToolbarItem(placement: .automatic) {
            if appState.instancesLoading { ProgressView().scaleEffect(0.75) }
        }
        ToolbarItem(placement: .automatic) {
            Button(action: { Task { await appState.loadInstances() } }) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(appState.instancesLoading)
            .keyboardShortcut("r", modifiers: .command)
            .help("刷新实例列表 (⌘R)")
        }
    }
}

// MARK: - Row

struct InstanceRowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    let instance: OciInstance
    let onDetail: () -> Void
    let onConsole: () -> Void
    let onTerminate: () -> Void
    let onSSH: () -> Void
    let onRescue: () -> Void
    let onVnic: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            stateCell
            nameCell
            ipCell
            shapeCell
            tenantCell
            actionsCell
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDetail() }
    }

    private var stateCell: some View {
        HStack(spacing: 5) {
            Circle().fill(stateColor).frame(width: 7, height: 7)
            Text(instance.state ?? "—")
                .font(.caption)
                .foregroundColor(AppTheme.muted(scheme))
        }
        .frame(width: 90, alignment: .leading)
    }

    private var nameCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(instance.displayName ?? "未命名")
                .fontWeight(.medium)
                .foregroundColor(AppTheme.text(scheme))
                .lineLimit(1)
            if let remark = instance.remark, !remark.isEmpty {
                Text(remark)
                    .font(.caption2)
                    .foregroundColor(AppTheme.muted(scheme))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ipCell: some View {
        Text(instance.displayPublicIP)
            .font(.system(.callout, design: .monospaced))
            .foregroundColor(AppTheme.text(scheme))
            .lineLimit(1)
            .frame(width: 140, alignment: .leading)
            .help("双击行打开详情；右键菜单可复制 IP")
    }

    private var shapeCell: some View {
        Text(instance.displayShape)
            .font(.caption)
            .foregroundColor(AppTheme.muted(scheme))
            .lineLimit(1)
            .frame(width: 110, alignment: .leading)
    }

    private var tenantCell: some View {
        Text(instance.displayTenant)
            .font(.caption)
            .foregroundColor(AppTheme.muted(scheme))
            .lineLimit(1)
            .frame(width: 130, alignment: .leading)
    }

    private var actionsCell: some View {
        HStack(spacing: 6) {
            powerButton
                .frame(width: 52)
            moreMenu
        }
        .frame(width: 190, alignment: .center)
    }

    @ViewBuilder
    private var powerButton: some View {
        if instance.isStopped {
            Button(action: {
                Task { await appState.startInstance(instance.instanceId ?? instance.id) }
            }) { Text("启动") }
            .buttonStyle(ProminentButton())
            .controlSize(.small)
        } else if instance.isRunning {
            Button(action: {
                Task { await appState.stopInstance(instance.instanceId ?? instance.id) }
            }) { Text("停止") }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Text(instance.state ?? "—")
                .font(.caption)
                .foregroundColor(AppTheme.muted(scheme))
        }
    }

    private var moreMenu: some View {
        // ViewBuilder supports max 10 direct children — group sections
        Menu {
            Group {
                Button("查看详情") { onDetail() }
                Button("VNC 控制台") { onConsole() }
                Button("SSH 终端") { onSSH() }
                Button("系统救援") { onRescue() }
                Button("网络 / VNIC") { onVnic() }
            }
            Divider()
            Group {
                Button("复制公网 IP") { copyIP() }
                Button("换 IP") { doChangeIP() }
                Button("开启 / 刷新 IPv6") { doIpv6() }
            }
            Divider()
            Button("终止实例") { onTerminate() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(AppTheme.muted(scheme))
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .help("更多操作")
    }

    private func copyIP() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(instance.displayPublicIP, forType: .string)
        appState.showToast("IP 已复制")
    }

    private func doChangeIP() {
        Task { await appState.changeIP(instance.id) }
    }

    private func doIpv6() {
        Task { await appState.enableIpv6(instance.id) }
    }

    private var stateColor: Color {
        switch instance.state?.uppercased() {
        case "RUNNING": return AppTheme.success
        case "STOPPED": return AppTheme.danger
        case "PROVISIONING", "STARTING", "STOPPING", "TERMINATING": return AppTheme.warning
        default: return .gray
        }
    }
}

// MARK: - Terminate with verification code

struct TerminateInstanceSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let instance: OciInstance
    @State private var code = ""
    @State private var sending = false
    @State private var terminating = false
    @State private var localError: String?

    private var detailId: String { instance.id }
    private var ociId: String { instance.instanceId ?? instance.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("终止实例")
                .font(.title3.weight(.semibold))
                .foregroundColor(AppTheme.text(scheme))
            Text("即将终止「\(instance.displayName ?? ociId)」。此操作不可撤销，需验证码确认。")
                .font(.callout)
                .foregroundColor(AppTheme.muted(scheme))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("验证码", text: $code)
                    .textFieldStyle(.roundedBorder)
                Button(action: { Task { await sendCode() } }) {
                    Text(sending ? "发送中…" : "发送验证码")
                }
                .disabled(sending)
            }

            if let localError = localError {
                Text(localError).font(.caption).foregroundColor(AppTheme.danger)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss.wrappedValue.dismiss() }
                    .keyboardShortcut(.escape)
                Button("确认终止") {
                    Task { await doTerminate() }
                }
                .buttonStyle(ProminentButton())
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || terminating)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func sendCode() async {
        sending = true
        localError = nil
        defer { sending = false }
        // Server binds verification to instance detail id (Long)
        let ok = await appState.sendTerminateCode(detailId)
        if !ok { localError = "验证码发送失败，请检查消息通道配置" }
    }

    private func doTerminate() async {
        terminating = true
        localError = nil
        defer { terminating = false }
        await appState.terminateInstance(detailId, verificationCode: code.trimmingCharacters(in: .whitespaces))
        if appState.errorMessage == nil {
            dismiss.wrappedValue.dismiss()
        }
    }
}
