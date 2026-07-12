import SwiftUI

/// Native one-click boot task list (Web: /boot/fullBootList)
struct BootTasksView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var taskToDelete: BootTask?
    @State private var showDeleteAlert = false
    @State private var showAddSheet = false

    var filtered: [BootTask] {
        guard !searchText.isEmpty else { return appState.bootTasks }
        let q = searchText.lowercased()
        return appState.bootTasks.filter {
            ($0.displayTenant.lowercased().contains(q)) ||
            ($0.architecture?.lowercased().contains(q) ?? false) ||
            ($0.regionName?.lowercased().contains(q) ?? false) ||
            ($0.remark?.lowercased().contains(q) ?? false) ||
            ($0.publicIp?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            searchBar
            headers
            Divider().background(AppTheme.border(scheme))
            content
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("一键开机")
        .toolbar { toolbar }
        .onAppear {
            if appState.bootTasks.isEmpty { Task { await appState.loadBootTasks() } }
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("删除开机任务"),
                message: Text("确认删除该开机任务？"),
                primaryButton: .destructive(Text("删除")) {
                    if let t = taskToDelete, let id = t.id {
                        Task { await appState.deleteBootTask(id) }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showAddSheet) {
            AddBootTaskView()
                .environmentObject(appState)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 20) {
            labelStat("任务", "\(appState.bootTasks.count)", AppTheme.text(scheme))
            labelStat("抢机中", "\(appState.bootRunningCount)", AppTheme.warning)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surface(scheme))
    }

    private func labelStat(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundColor(AppTheme.muted(scheme))
            Text(value).font(.callout.weight(.semibold)).foregroundColor(color)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(AppTheme.muted(scheme))
            TextField("搜索租户、区域、架构…", text: $searchText).textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(AppTheme.muted(scheme))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(AppTheme.elevated(scheme))
    }

    private var headers: some View {
        HStack(spacing: 0) {
            Text("状态").frame(width: 70, alignment: .leading)
            Text("租户").frame(maxWidth: .infinity, alignment: .leading)
            Text("区域").frame(width: 110, alignment: .leading)
            Text("架构").frame(width: 70, alignment: .leading)
            Text("配置").frame(width: 110, alignment: .leading)
            Text("成功/尝试").frame(width: 90, alignment: .leading)
            Text("操作").frame(width: 160, alignment: .center)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .font(.caption.weight(.semibold))
        .foregroundColor(AppTheme.muted(scheme))
        .background(AppTheme.elevated(scheme))
    }

    @ViewBuilder
    private var content: some View {
        if appState.bootTasksLoading && appState.bootTasks.isEmpty {
            PageLoadingView(message: "加载开机任务…")
        } else if filtered.isEmpty {
            EmptyStateView(icon: "play.circle", title: "暂无开机任务",
                           subtitle: "可在 Web 端「添加开机」后在此管理")
        } else {
            List(filtered) { task in
                BootTaskRow(
                    task: task,
                    onStart: { if let id = task.id { Task { await appState.startBootTask(id) } } },
                    onStop: { if let id = task.id { Task { await appState.stopBootTask(id) } } },
                    onDelete: { taskToDelete = task; showDeleteAlert = true }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(AppTheme.pageBg(scheme))
            }
            .listStyle(.plain)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            if appState.bootTasksLoading { ProgressView().scaleEffect(0.75) }
        }
        ToolbarItem {
            Button(action: { showAddSheet = true }) {
                Label("添加开机", systemImage: "plus")
            }
        }
        ToolbarItem {
            Button(action: { Task { await appState.batchStartBoots() } }) {
                Label("批量启动", systemImage: "play.fill")
            }
        }
        ToolbarItem {
            Button(action: { Task { await appState.batchStopBoots() } }) {
                Label("批量停止", systemImage: "stop.fill")
            }
        }
        ToolbarItem {
            Button(action: { Task { await appState.loadBootTasks() } }) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

private struct BootTaskRow: View {
    @Environment(\.colorScheme) private var scheme
    let task: BootTask
    let onStart: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(task.statusLabel).font(.caption).foregroundColor(AppTheme.muted(scheme))
            }
            .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayTenant).fontWeight(.medium).foregroundColor(AppTheme.text(scheme)).lineLimit(1)
                if let r = task.remark, !r.isEmpty {
                    Text(r).font(.caption2).foregroundColor(AppTheme.muted(scheme)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(task.regionName ?? "—")
                .font(.caption).foregroundColor(AppTheme.muted(scheme))
                .frame(width: 110, alignment: .leading)

            Text(task.architecture ?? "—")
                .font(.caption).foregroundColor(AppTheme.muted(scheme))
                .frame(width: 70, alignment: .leading)

            Text(task.displayShape)
                .font(.caption).foregroundColor(AppTheme.muted(scheme))
                .frame(width: 110, alignment: .leading)

            Text("\(task.successCount ?? 0)/\(task.addCount ?? 0)")
                .font(.caption).foregroundColor(AppTheme.muted(scheme))
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 6) {
                if task.status == 0 || task.status == 2 {
                    Button("启动", action: onStart)
                        .buttonStyle(ProminentButton())
                        .controlSize(.small)
                }
                if task.status == 1 {
                    Button("停止", action: onStop)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(AppTheme.danger)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 160, alignment: .center)
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
    }

    private var statusColor: Color {
        switch task.status {
        case 1: return AppTheme.warning
        case 2: return AppTheme.success
        default: return AppTheme.muted(scheme)
        }
    }
}
