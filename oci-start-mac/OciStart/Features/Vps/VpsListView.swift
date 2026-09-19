import SwiftUI
import AppKit

/// Resource management follows the Vue table and canonical APIs.
struct VpsListView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var navigation: NavigationState
    @State private var guardOwner = UUID()
    @StateObject private var model = VpsViewModel()
    @StateObject private var quality = NetworkQualityViewModel()
    @AppStorage("appLocale") private var locale = "zh_CN"
    @State private var qualityOpen = false
    @State private var qualityInstance: String?
    @State private var details: VpsCardItem?
    @State private var horizontalOffset: CGFloat = 0
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        Group {
            if let item = model.sshItem {
                InstanceSSHView(item: item, onBack: { model.closeSSH() })
            } else if qualityOpen {
                NetworkQualityView(instanceID: qualityInstance, onBack: {
                    qualityOpen = false
                    Task { await quality.refresh() }
                })
            } else { resourcePage }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            FloatingMenuDismiss.all()
            model.start()
            installLeaveGuard()
            Task { await quality.refresh() }
        }
        .onDisappear { navigation.removeLeaveGuard(owner: guardOwner); model.teardown(); quality.stop() }
        .onChange(of: qualityOpen) { _ in installLeaveGuard() }
        .onChange(of: model.sshItem?.id) { _ in installLeaveGuard() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            guard model.sshItem == nil, !qualityOpen else { return }
            Task { await model.reload(); await quality.refresh() }
        }
        .sheet(item: $details) { card in
            resourceDetails(card).environmentObject(appearance)
        }
    }

    private var resourcePage: some View {
        PageScaffold(title: vpsText("资源管理", "Resources"), subtitle: "", systemImage: "server.rack", content: {
            VStack(spacing: 0) {
                controls
                if model.requiresReview {
                    reviewBar(loaded: model.reviewLoaded, refresh: { Task { await model.reload() } }, acknowledge: { model.acknowledgeReview() })
                }
                table
                PaginationBar(state: $model.pageState, onChange: { model.updatePagination() })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        .onChange(of: model.searchText) { _ in model.updatePagination(reset: true) }
        .onChange(of: model.offlineOnly) { _ in model.updatePagination(reset: true) }
        .onChange(of: model.provider) { _ in model.updatePagination(reset: true) }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                AppTextField(text: $model.searchText, placeholder: vpsText("搜索名称、IP、租户或区域", "Search name, IP, tenant or region"), leadingSystemImage: "magnifyingglass")
                    .frame(minWidth: 180, maxWidth: 340)
                SelectMenu(options: [
                    SelectOption(id: "", title: vpsText("全部厂商", "All providers")),
                    SelectOption(id: "1", title: "Oracle Cloud"), SelectOption(id: "2", title: "Google Cloud"),
                    SelectOption(id: "3", title: "Azure"), SelectOption(id: "4", title: "AWS")
                ], selection: stringSelection($model.provider), width: 145, allowClear: false)
                Toggle(vpsText("仅离线", "Offline only"), isOn: $model.offlineOnly).toggleStyle(CheckboxToggleStyle())
                Spacer(minLength: 0)
                errorButton(model.errorText)
                errorButton(quality.errorText)
                AppButton(title: "", systemImage: "arrow.clockwise", kind: .secondary, isLoading: model.isLoading) {
                    Task { await model.reload(); await quality.refresh() }
                }.help(vpsText("刷新", "Refresh"))
            }
            HStack(spacing: 8) {
                Text(vpsText("共 \(model.totalCount) 台 · 在线 \(model.onlineCount) · 离线 \(model.offlineCount)",
                             "\(model.totalCount) resources · \(model.onlineCount) online · \(model.offlineCount) offline"))
                    .font(.system(size: 13))
                Spacer(minLength: 0)
                Toggle("IP", isOn: $model.showIP).toggleStyle(CheckboxToggleStyle())
                Toggle(vpsText("租户", "Tenant"), isOn: $model.showTenant).toggleStyle(CheckboxToggleStyle())
                AppButton(title: model.isLatencyTesting ? vpsText("停止", "Stop") : vpsText("HTTP 延迟", "HTTP latency"),
                          systemImage: model.isLatencyTesting ? "stop" : "speedometer", kind: .primary) {
                    if model.isLatencyTesting { model.stopLatencyTest() } else { model.runLatencyTest() }
                }.disabled(model.cards.isEmpty || model.isLoading)
                Menu {
                    Button(vpsText("检测任务", "Network tasks")) { openQuality(nil) }
                    Button(vpsText("网络质量趋势", "Network history")) { openQuality(model.visibleCards.first?.id) }
                    Divider()
                    Button(vpsText("开启全部 OCI 自动 Ping", "Enable automatic Ping for all OCI")) { model.enablePing() }
                    Button(vpsText("关闭全部 OCI 自动 Ping", "Disable automatic Ping for all OCI")) { model.disablePing() }
                    Button(vpsText("检测全部 OCI", "Ping all OCI")) { model.manualPing() }
                } label: { Image(systemName: "ellipsis").frame(width: 30, height: 32) }
                .menuStyle(BorderlessButtonMenuStyle())
                .fixedSize()
                .disabled(model.isBusy || model.requiresReview)
                .help(vpsText("更多操作", "More actions"))
            }
        }
        .foregroundColor(AppTheme.textPrimary(dark))
        .padding(16)
    }

    private var table: some View {
        GeometryReader { viewport in
            let width = max(CGFloat(1470), viewport.size.width)
            let shift = min(CGFloat(0), viewport.size.width - width - horizontalOffset)
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    tableHeader(width: width, shift: shift)
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(model.visibleCards) { card in resourceRow(card, width: width, shift: shift) }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .overlay(Group {
                        if model.visibleCards.isEmpty {
                            EmptyStateView(icon: "server.rack",
                                           title: model.isLoading ? vpsText("加载中…", "Loading…") : vpsText("暂无资源", "No resources"),
                                           subtitle: model.errorText == nil ? vpsText("调整筛选或刷新列表", "Adjust filters or refresh") : vpsText("请查看工具栏中的错误详情", "See the toolbar for error details"))
                        }
                    })
                }
                .frame(width: width, height: viewport.size.height)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: VpsHorizontalOffset.self, value: geometry.frame(in: .named("resourceHorizontal")).minX)
                })
            }
            .coordinateSpace(name: "resourceHorizontal")
            .onPreferenceChange(VpsHorizontalOffset.self) { horizontalOffset = $0 }
        }
        .font(.system(size: 14))
        .foregroundColor(AppTheme.textPrimary(dark))
    }

    private func tableHeader(width: CGFloat, shift: CGFloat) -> some View {
        HStack(spacing: 0) {
            Group {
            cell(vpsText("实例", "Instance"), width: width - 1190)
            cell(vpsText("IP / 区域", "IP / Region"), width: 150)
            cell(vpsText("监控", "Agent"), width: 95)
            cell("CPU", width: 72)
            cell(vpsText("内存", "Memory"), width: 72)
            cell(vpsText("磁盘", "Disk"), width: 72)
            }
            Group {
            cell(vpsText("收 / 发 · 采样字节", "RX / TX · sample bytes"), width: 140)
            cell(vpsText("HTTP 延迟", "HTTP latency"), width: 99)
            cell(vpsText("电信", "Telecom"), width: 130)
            cell(vpsText("联通", "Unicom"), width: 130)
            cell(vpsText("移动", "Mobile"), width: 130)
            Color.clear.frame(width: 100)
            }
        }
        .frame(height: 42)
        .background(AppTheme.hover(dark))
        .overlay(cell(vpsText("操作", "Actions"), width: 100).frame(height: 42).background(AppTheme.hover(dark)).offset(x: shift), alignment: .trailing)
    }

    private func resourceRow(_ card: VpsCardItem, width: CGFloat, shift: CGFloat) -> some View {
        HStack(spacing: 0) {
            Group {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.item.displayName.isEmpty ? "—" : card.item.displayName).fontWeight(.medium)
                Text(model.showTenant ? empty(card.item.tenancyName) : card.item.maskedTenancyName).font(.system(size: 13))
            }.lineLimit(1).padding(.horizontal, 12).frame(width: width - 1190, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.showIP ? card.displayIP : card.maskedIP)
                Text(empty(card.item.regionName)).font(.system(size: 13))
            }.lineLimit(1).padding(.horizontal, 12).frame(width: 150, alignment: .leading)
            cell(model.agentLabel(card), width: 95)
            metricCell(card.metrics.cpuPercent, width: 72, stale: card.monitorWarning)
            metricCell(card.metrics.memPercent, width: 72, stale: card.monitorWarning)
            metricCell(card.metrics.diskPercent, width: 72, stale: card.monitorWarning)
            }
            Group {
            cell("\(card.metrics.netRx)\n\(card.metrics.netTx)", width: 140)
            cell(VpsFormat.latencyLabel(card.latencyMs), width: 99)
            carrierCell(card.id, operatorCode: "telecom")
            carrierCell(card.id, operatorCode: "unicom")
            carrierCell(card.id, operatorCode: "mobile")
            Color.clear.frame(width: 100)
            }
        }
        .frame(height: 68)
        .background(AppTheme.cardBg(dark))
        .overlay(rowActions(card).frame(width: 100, height: 68).background(AppTheme.cardBg(dark)).offset(x: shift), alignment: .trailing)
        .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .bottom)
    }

    private func rowActions(_ card: VpsCardItem) -> some View {
        HStack(spacing: 10) {
            Button { details = card } label: { Image(systemName: "info.circle") }
                .buttonStyle(PlainButtonStyle()).help(vpsText("资源详情", "Resource details"))
            Menu {
                Button(vpsText("SSH 终端", "SSH terminal")) { model.openSSH(card) }
                Button(vpsText("网络质量趋势", "Network history")) { openQuality(card.id) }
                Button(vpsText("复制 IP", "Copy IP")) { model.copyIP(card) }
                Divider()
                Button(vpsText("安装 / 升级探针", "Install / upgrade agent")) { model.installMonitor(card) }
                Button(vpsText("卸载探针", "Uninstall agent")) { model.uninstallMonitor(card) }
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
            .menuStyle(BorderlessButtonMenuStyle()).fixedSize()
            .disabled(model.isBusy || model.requiresReview)
        }
        .foregroundColor(AppTheme.brand(dark))
    }

    private func carrierCell(_ id: String, operatorCode: String) -> some View {
        let entries: [(NetworkQualityTask, NetworkQualityResult?)] = (quality.overview?.tasks ?? [])
            .filter { $0.operatorCode == operatorCode && $0.instanceIds.contains(id) }
            .map { task in (task, quality.overview?.latest.first { $0.instanceId == id && $0.taskId == task.id && $0.revision == task.version }) }
        let summary = entries.map { task, result in
            "\(task.name) · \(task.type.uppercased())\n\(result.map { VpsFormat.metric($0.avgMs, suffix: " ms") + " / " + VpsFormat.metric($0.lossPercent) + " · " + $0.statusLabel } ?? "—")"
        }.joined(separator: "\n")
        return Button { openQuality(id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let first = entries.first {
                    Text(first.0.name).lineLimit(1).font(.system(size: 13))
                    Text(first.1.map { VpsFormat.metric($0.avgMs, suffix: " ms") + " / " + VpsFormat.metric($0.lossPercent) } ?? "—").lineLimit(1)
                    if entries.count > 1 { Text("+\(entries.count - 1)").font(.system(size: 12)) }
                } else { Text("—") }
            }.padding(.horizontal, 12).frame(width: 130, alignment: .leading)
        }.buttonStyle(PlainButtonStyle()).help(summary.isEmpty ? "—" : summary)
    }

    private func resourceDetails(_ card: VpsCardItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(vpsText("资源详情", "Resource details")).font(.system(size: 18, weight: .semibold))
                Spacer()
                AppButton(title: vpsText("关闭", "Close"), kind: .secondary) { details = nil }
            }
            Group {
            KeyValueRow(key: vpsText("实例", "Instance"), value: empty(card.item.displayName))
            KeyValueRow(key: "IP", value: model.showIP ? card.displayIP : card.maskedIP)
            KeyValueRow(key: vpsText("租户", "Tenant"), value: model.showTenant ? empty(card.item.tenancyName) : card.item.maskedTenancyName)
            KeyValueRow(key: vpsText("配置", "Configuration"), value: card.specText)
            KeyValueRow(key: vpsText("区域", "Region"), value: empty(card.item.regionName))
            KeyValueRow(key: vpsText("架构", "Architecture"), value: empty(card.item.architecture))
            KeyValueRow(key: vpsText("负载", "Load"), value: card.metrics.load)
            KeyValueRow(key: vpsText("运行时间", "Uptime"), value: card.metrics.uptime)
            KeyValueRow(key: vpsText("磁盘总量", "Disk total"), value: card.metrics.diskTotalLabel)
            KeyValueRow(key: vpsText("实际上报时间", "Last observed report"), value: VpsFormat.date(card.metrics.lastBeatMs))
            }
            Text(vpsText("收发数据为相邻采样的字节数；HTTP 请求失败不等于服务器离线。",
                         "RX and TX are bytes between samples. A failed HTTP request does not establish that a server is offline."))
                .font(.system(size: 13))
            AppButton(title: vpsText("查看网络质量", "Network history"), kind: .primary) { details = nil; openQuality(card.id) }
        }
        .padding(24).frame(width: 560).foregroundColor(AppTheme.textPrimary(dark)).background(AppTheme.cardBg(dark))
    }

    private func installLeaveGuard() {
        if qualityOpen || model.sshItem != nil { navigation.removeLeaveGuard(owner: guardOwner); return }
        navigation.setLeaveGuard(owner: guardOwner) {
            guard !model.isBusy, !model.requiresReview else {
                ToastCenter.shared.error(vpsText("请等待操作结束，并核对未确认的结果。", "Wait for the operation and review any unconfirmed result."))
                return false
            }
            return true
        }
    }
    private func openQuality(_ id: String?) {
        guard !model.isBusy, !model.requiresReview else { return }
        FloatingMenuDismiss.all(); model.stopLatencyTest(); qualityInstance = id; qualityOpen = true
    }
    private func empty(_ value: String) -> String { value.isEmpty ? "—" : value }
    private func metricCell(_ value: Double?, width: CGFloat, stale: Bool) -> some View {
        cell(VpsFormat.metric(value), width: width).opacity(stale ? 0.6 : 1)
    }
    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text).lineLimit(2).padding(.horizontal, 12).frame(width: width, alignment: .leading).help(text)
    }
}

private struct VpsHorizontalOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private func stringSelection(_ value: Binding<String>) -> Binding<String?> {
    Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0 ?? "" })
}

@ViewBuilder
private func errorButton(_ message: String?) -> some View {
    if let message = message, !message.isEmpty {
        Button {
            let alert = NSAlert()
            alert.messageText = vpsText("操作详情", "Operation details")
            alert.informativeText = message
            alert.addButton(withTitle: vpsText("关闭", "Close"))
            alert.runModal()
        } label: { Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).frame(width: 28, height: 30) }
        .buttonStyle(PlainButtonStyle())
        .help(vpsText("查看错误详情", "Show error details"))
    }
}

private func reviewBar(loaded: Bool, refresh: @escaping () -> Void, acknowledge: @escaping () -> Void) -> some View {
    HStack(spacing: 10) {
        Text(vpsText("操作结果未确认。请刷新并核对实际记录后继续。", "The operation is unconfirmed. Refresh and review the actual records before continuing."))
            .font(.system(size: 13))
        Spacer()
        AppButton(title: vpsText("刷新核对", "Refresh to review"), kind: .secondary, action: refresh)
        AppButton(title: vpsText("已核对", "Reviewed"), kind: .secondary, enabled: loaded, action: acknowledge)
    }.padding(12)
}

/// Native task management and history pages, optionally scoped to a local resource ID.
struct NetworkQualityView: View {
    var instanceID: String? = nil
    let onBack: () -> Void
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var navigation: NavigationState
    @State private var guardOwner = UUID()
    @StateObject private var model = NetworkQualityViewModel()
    @AppStorage("appLocale") private var locale = "zh_CN"
    @State private var showHistory = false
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(title: vpsText("网络质量", "Network quality"), subtitle: "", systemImage: "network", layout: .workspace,
                     toolbar: { toolbar }, content: {
            VStack(spacing: 0) {
                if model.requiresReview {
                    reviewBar(loaded: model.reviewLoaded, refresh: { Task { await model.refresh() } }, acknowledge: { model.acknowledgeReview() })
                }
                if model.editor != nil { editor }
                else if showHistory { historyPage }
                else { tasksPage }
            }
            .padding(AppTheme.pagePadding)
            .foregroundColor(AppTheme.textPrimary(dark))
            .font(.system(size: 14))
        })
        .onAppear {
            navigation.setLeaveGuard(owner: guardOwner) { canLeavePage() }
            Task {
                await model.refresh()
                if let instanceID = instanceID {
                    showHistory = true
                    model.openHistory(instance: instanceID)
                }
            }
        }
        .onDisappear { navigation.removeLeaveGuard(owner: guardOwner); model.stop() }
        .onChange(of: model.query) { _ in model.updatePagination(reset: true) }
        .onChange(of: model.selectedInstance) { _ in model.updatePagination(reset: true); Task { await model.loadHistory() } }
        .onChange(of: model.selectedTask) { _ in Task { await model.loadHistory() } }
        .onChange(of: model.hours) { _ in Task { await model.loadHistory() } }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: vpsText("返回", "Back"), systemImage: "chevron.left", kind: .secondary) {
                guard !model.busy else { return }
                if model.editor != nil { model.closeEditor() }
                else if showHistory { showHistory = false; model.selectedInstance = ""; model.updatePagination(reset: true) }
                else if canLeavePage() { onBack() }
            }
            Spacer()
            errorButton(model.errorText)
            AppButton(title: vpsText("刷新", "Refresh"), systemImage: "arrow.clockwise", kind: .secondary, isLoading: model.loading) {
                Task { await model.refresh(); if showHistory { await model.loadHistory() } }
            }.disabled(model.busy)
            if model.editor == nil {
                AppButton(title: vpsText("创建任务", "Create task"), systemImage: "plus", enabled: model.canMutate) {
                    model.create(instance: model.selectedInstance.isEmpty ? nil : model.selectedInstance)
                }
            }
        }
    }

    private var tasksPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppTextField(text: $model.query, placeholder: vpsText("搜索任务、目标或运营商", "Search tasks, targets or carriers"), leadingSystemImage: "magnifyingglass").frame(maxWidth: 360)
                Spacer()
                Text(vpsText("检测任务", "Network tasks")).font(.system(size: 16, weight: .semibold))
                Text("\(model.filteredTasks.count)")
            }.padding(16)
            HStack {
                Text(vpsText("任务 / 目标", "Task / Target")).frame(maxWidth: .infinity, alignment: .leading)
                Text(vpsText("运营商", "Carrier")).frame(width: 90)
                Text(vpsText("间隔 / 样本", "Interval / Samples")).frame(width: 110)
                Text(vpsText("实例", "Instances")).frame(width: 80)
                Text(vpsText("操作", "Actions")).frame(width: 170)
            }.padding(12).background(AppTheme.hover(dark))
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleTasks) { task in taskRow(task) }
                    if model.visibleTasks.isEmpty {
                        EmptyStateView(icon: "network", title: model.loading ? vpsText("加载中…", "Loading…") : vpsText("暂无检测任务", "No network tasks"),
                                       subtitle: vpsText("创建 ICMP、TCP 或 HTTP 检测并分配实例", "Create ICMP, TCP or HTTP checks and assign resources"))
                            .padding(24)
                    }
                }
            }
            PaginationBar(state: $model.pageState, onChange: { model.updatePagination() })
        }
        .background(AppTheme.cardBg(dark)).cornerRadius(AppTheme.cardRadius)
    }

    private func taskRow(_ task: NetworkQualityTask) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.name).fontWeight(.medium)
                Text("\(task.type.uppercased()) · \(task.target)").font(.system(size: 13)).lineLimit(1).help(task.target)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 5) { Text(task.operatorLabel); Text(task.region.isEmpty ? "—" : task.region).font(.system(size: 13)) }.frame(width: 90)
            Text("\(task.intervalSeconds)s / \(task.sampleCount)\n" + (task.enabled ? vpsText("运行", "Active") : vpsText("暂停", "Paused"))).frame(width: 110)
            Text("\(task.instanceIds.count)").frame(width: 80)
            HStack(spacing: 14) {
                Button { if let id = task.instanceIds.first { showHistory = true; model.openHistory(instance: id, task: task) } } label: { Image(systemName: "chart.xyaxis.line") }
                    .help(vpsText("查看趋势", "Show history"))
                Button { model.run(task) } label: { Image(systemName: "play.circle") }.help(vpsText("立即执行", "Run now"))
                Button { model.edit(task) } label: { Image(systemName: "pencil") }.help(vpsText("编辑", "Edit"))
                Menu {
                    Button(task.enabled ? vpsText("暂停", "Pause") : vpsText("恢复", "Resume")) { model.toggle(task) }
                    Button(vpsText("删除", "Delete")) { model.delete(task) }
                } label: { Image(systemName: "ellipsis").frame(width: 20) }
                .menuStyle(BorderlessButtonMenuStyle()).fixedSize()
            }.buttonStyle(PlainButtonStyle()).foregroundColor(AppTheme.brand(dark))
                .disabled(!model.canMutate).frame(width: 170)
        }
        .padding(12).frame(minHeight: 70)
        .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .bottom)
    }

    private var editor: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.editor?.id.isEmpty == true ? vpsText("创建检测任务", "Create network task") : vpsText("编辑检测任务", "Edit network task"))
                    .font(.system(size: 18, weight: .semibold))
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Group {
                        field(vpsText("任务名称", "Task name"), text: editorText(\.name))
                        field(vpsText("城市 / 区域", "City / Region"), text: editorText(\.region))
                        Text(vpsText("运营商", "Carrier"))
                        SelectMenu(options: [
                            SelectOption(id: "telecom", title: vpsText("电信", "Telecom")), SelectOption(id: "unicom", title: vpsText("联通", "Unicom")),
                            SelectOption(id: "mobile", title: vpsText("移动", "Mobile")), SelectOption(id: "custom", title: vpsText("自定义", "Custom"))
                        ], selection: stringSelection(editorText(\.operatorCode)), width: 220, allowClear: false)
                        Text(vpsText("检测协议", "Protocol"))
                        SelectMenu(options: ["icmp", "tcp", "http"].map { SelectOption(id: $0, title: $0.uppercased()) },
                                   selection: stringSelection(editorText(\.type)), width: 220, allowClear: false)
                        field(vpsText("目标", "Target"), text: editorText(\.target))
                        Text(vpsText("ICMP: 主机 · TCP: 主机:端口 · HTTP: 完整 URL", "ICMP: host · TCP: host:port · HTTP: complete URL"))
                            .font(.system(size: 13))
                        }
                        field(vpsText("间隔（30–86400 秒）", "Interval (30–86400 seconds)"), text: editorNumber(\.intervalSeconds))
                        field(vpsText("每次采样数（1–10）", "Samples per run (1–10)"), text: editorNumber(\.sampleCount))
                        Toggle(vpsText("启用任务", "Enable task"), isOn: Binding(get: { model.editor?.enabled ?? false }, set: { model.editor?.enabled = $0 }))
                            .toggleStyle(CheckboxToggleStyle())
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(vpsText("分配实例", "Assign instances")).font(.system(size: 16, weight: .semibold))
                        Text(vpsText("最多 256 台；探针需要支持网络质量检测。", "Up to 256 resources. Agents must support network quality checks.")).font(.system(size: 13))
                        ForEach(model.overview?.agents ?? []) { agent in
                            HStack(spacing: 8) {
                                Toggle(agent.title, isOn: Binding(get: { model.editor?.instanceIds.contains(agent.id) ?? false }, set: { selected in
                                    guard var draft = model.editor else { return }
                                    if selected && !draft.instanceIds.contains(agent.id) { draft.instanceIds.append(agent.id) }
                                    else if !selected { draft.instanceIds.removeAll { $0 == agent.id } }
                                    model.editor = draft
                                })).toggleStyle(CheckboxToggleStyle()).lineLimit(1).help(agent.title)
                                Spacer()
                                Text(agent.statusLabel).font(.system(size: 12))
                            }.padding(.vertical, 5)
                        }
                        if let draft = model.editor {
                            let unavailable = draft.instanceIds.filter { id in !(model.overview?.agents.contains { $0.id == id } ?? false) }
                            ForEach(unavailable, id: \.self) { id in
                                HStack {
                                    Text(vpsText("已分配但当前列表缺失：", "Assigned but unavailable: ") + id).font(.system(size: 13))
                                    Button(vpsText("移除", "Remove")) { model.editor?.instanceIds.removeAll { $0 == id } }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if model.requiresReview, let saved = model.overview?.tasks.first(where: { $0.id == model.editor?.id }) {
                    Text(vpsText("当前服务端记录：", "Current server record: ") + "\(saved.name) · \(saved.target) · v\(saved.version)")
                        .font(.system(size: 13))
                }
                HStack {
                    Spacer()
                    AppButton(title: vpsText("取消", "Cancel"), kind: .secondary, enabled: !model.busy) { model.closeEditor() }
                    AppButton(title: vpsText("保存任务", "Save task"), isLoading: model.busy, enabled: model.canMutate) { model.save() }
                }
            }
            .padding(24).background(AppTheme.cardBg(dark)).cornerRadius(AppTheme.cardRadius)
            .disabled(model.busy)
        }
    }

    private var historyPage: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                SelectMenu(options: (model.overview?.agents ?? []).map { SelectOption(id: $0.id, title: $0.title) },
                           selection: stringSelection($model.selectedInstance), placeholder: vpsText("选择实例", "Choose resource"), width: 220, allowClear: false)
                SelectMenu(options: (model.overview?.tasks ?? []).filter { $0.instanceIds.contains(model.selectedInstance) }.map { SelectOption(id: $0.id, title: $0.name) },
                           selection: stringSelection($model.selectedTask), placeholder: vpsText("选择任务", "Choose task"), width: 220, allowClear: false)
                SelectMenu(options: ["1", "6", "24", "168"].map { SelectOption(id: $0, title: "\($0) h") },
                           selection: stringSelection($model.hours), width: 100, allowClear: false)
                Spacer()
                if let agent = model.overview?.agents.first(where: { $0.id == model.selectedInstance }) {
                    Text(agent.statusLabel).font(.system(size: 13))
                    if agent.qualityStatus == "not_installed" || agent.qualityStatus == "upgrade_required" {
                        AppButton(title: vpsText("安装 / 升级", "Install / upgrade"), kind: .secondary, enabled: model.canMutate) { model.install(agent) }
                    }
                }
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    if let task = model.task {
                        Text("\(task.name) · \(task.operatorLabel) · \(task.type.uppercased()) · \(task.target)")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    if let history = model.history {
                        historySummary(history)
                        NetworkQualityPlot(history: history).stroke(AppTheme.brand(dark), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                            .frame(height: 180).padding(12).background(AppTheme.hover(dark)).cornerRadius(10)
                        HStack {
                            Text(VpsFormat.date(history.from))
                            Spacer()
                            Text(VpsFormat.date(history.to))
                        }.font(.system(size: 12))
                        Text(vpsText("不同协议与目标分别统计；缺失或不支持的检测不计为丢包。", "Protocols and targets are reported separately. Missing or unsupported checks are not counted as packet loss."))
                            .font(.system(size: 13))
                        if history.truncated {
                            Text(vpsText("图表仅展示最近 \(history.points.count) 条；统计覆盖全部 \(history.totalPoints) 条。",
                                         "Chart shows the latest \(history.points.count) points; statistics cover all \(history.totalPoints) results.")).font(.system(size: 13))
                        }
                        historyRows(history)
                    } else {
                        EmptyStateView(icon: "chart.xyaxis.line",
                                       title: model.historyLoading ? vpsText("加载中…", "Loading…") : vpsText("暂无检测结果", "No results"),
                                       subtitle: vpsText("选择实例和已分配任务；安装后等待真实检测上报。", "Choose a resource and assigned task, then wait for actual reports."))
                            .padding(32)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.background(AppTheme.cardBg(dark)).cornerRadius(AppTheme.cardRadius)
        }
    }

    private func historySummary(_ history: NetworkQualityHistory) -> some View {
        HStack(spacing: 24) {
            historyMetric(vpsText("平均", "Average"), VpsFormat.metric(history.stats.avgMs, suffix: " ms"))
            historyMetric(vpsText("最小", "Minimum"), VpsFormat.metric(history.stats.minMs, suffix: " ms"))
            historyMetric(vpsText("最大", "Maximum"), VpsFormat.metric(history.stats.maxMs, suffix: " ms"))
            historyMetric(model.task?.type == "icmp" ? vpsText("丢包率", "Packet loss") : vpsText("失败率", "Failure rate"), VpsFormat.metric(history.stats.lossPercent))
            historyMetric(vpsText("样本", "Samples"), "\(history.stats.successful) / \(history.stats.attempts)")
            Spacer(minLength: 0)
        }
    }
    private func historyMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13))
            Text(value).font(.system(size: 18, weight: .semibold))
        }
    }
    private func historyRows(_ history: NetworkQualityHistory) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(vpsText("时间", "Time")).frame(width: 180, alignment: .leading)
                Text(vpsText("结果", "Result")).frame(width: 90, alignment: .leading)
                Text(vpsText("平均", "Average")).frame(width: 90, alignment: .leading)
                Text(vpsText("成功 / 采样", "Success / Samples")).frame(width: 120, alignment: .leading)
                Text(vpsText("原因", "Reason")).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).background(AppTheme.hover(dark))
            ForEach(history.points.reversed()) { point in
                HStack {
                    Text(VpsFormat.date(point.updatedAt)).frame(width: 180, alignment: .leading)
                    Text(point.statusLabel).frame(width: 90, alignment: .leading)
                    Text(VpsFormat.metric(point.avgMs, suffix: " ms")).frame(width: 90, alignment: .leading)
                    Text("\(point.successful.map(String.init) ?? "—") / \(point.attempts.map(String.init) ?? "—")").frame(width: 120, alignment: .leading)
                    Text(point.errorMessage ?? point.errorCode ?? "—").lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        .help(point.errorMessage ?? point.errorCode ?? "—")
                }.padding(10).font(.system(size: 13))
                Divider()
            }
        }
    }
    private func editorText(_ key: WritableKeyPath<NetworkQualityTask, String>) -> Binding<String> {
        Binding(get: { model.editor?[keyPath: key] ?? "" }, set: { model.editor?[keyPath: key] = $0 })
    }
    private func canLeavePage() -> Bool {
        guard !model.busy, !model.requiresReview else {
            ToastCenter.shared.error(vpsText("请等待操作结束，并核对未确认的结果。", "Wait for the operation and review any unconfirmed result."))
            return false
        }
        guard model.editor != nil else { return true }
        guard AppAlert.confirm(title: vpsText("放弃未保存的更改？", "Discard unsaved changes?"), message: "") else { return false }
        model.editor = nil
        return true
    }
    private func editorNumber(_ key: WritableKeyPath<NetworkQualityTask, Int>) -> Binding<String> {
        Binding(get: { model.editor.map { String($0[keyPath: key]) } ?? "" }, set: { model.editor?[keyPath: key] = Int($0) ?? 0 })
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title); AppTextField(text: text, placeholder: title) }
    }
}

private struct NetworkQualityPlot: Shape {
    let history: NetworkQualityHistory
    func path(in rect: CGRect) -> Path {
        let maximum = max(1, history.points.compactMap(\.avgMs).max() ?? 1)
        let duration = max(Int64(1), history.to - history.from)
        var path = Path()
        var connected = false
        for result in history.points {
            guard let value = result.avgMs, value.isFinite, value >= 0 else { connected = false; continue }
            let x = rect.minX + rect.width * CGFloat(Double(result.updatedAt - history.from) / Double(duration))
            let y = rect.maxY - rect.height * CGFloat(value / maximum)
            let point = CGPoint(x: x, y: y)
            if connected { path.addLine(to: point) } else { path.move(to: point) }
            connected = true
        }
        return path
    }
}
