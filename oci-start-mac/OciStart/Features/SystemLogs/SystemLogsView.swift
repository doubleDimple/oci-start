import SwiftUI
import AppKit

/// 原生系统日志（对齐 Web `/system/logs` · `sys_log.ftl`）。
/// 终端风格：历史 JSON + SSE 实时尾随（isBootLog=false）。
struct SystemLogsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = SystemLogsViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(
            title: "系统日志",
            subtitle: "应用运行日志 · 历史 + SSE 实时流",
            systemImage: "doc.plaintext",
            layout: .workspace,
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                    }
                    terminalCard
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppTheme.pagePadding)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            model.reloadHistory()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            connectionBadge
            AppButton(title: "清空", systemImage: "trash", kind: .secondary) {
                if AppAlert.confirm(title: "清空日志", message: "仅清空当前视图中的日志，不影响服务端文件。") {
                    model.clearLogs()
                }
            }
            AppButton(title: "重连", systemImage: "bolt.horizontal.circle", kind: .secondary) {
                model.reconnectNow()
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.isLoadingHistory
            ) {
                model.reloadHistory()
            }
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(model.connection.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(dark))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.inputBg(dark))
        )
    }

    private var connectionColor: Color {
        switch model.connection {
        case .connected: return Color(hex: "1abc9c")
        case .connecting: return Color(hex: "f39c12")
        case .disconnected: return Color(hex: "ff6b6b")
        }
    }

    private var terminalCard: some View {
        VStack(spacing: 0) {
            terminalHeader
            terminalBody
            terminalFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(hex: "4fc3f7").opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(6)
        .shadow(color: Color(hex: "4fc3f7").opacity(0.12), radius: 8, x: 0, y: 2)
    }

    private var terminalHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "4fc3f7"))
            Text("系统控制台")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: "4fc3f7"))
            Text("▌")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(hex: "4fc3f7").opacity(0.7))
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 7, height: 7)
                Text(model.connection.label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "0a0a0a"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "4fc3f7").opacity(0.25)),
            alignment: .bottom
        )
    }

    private var terminalBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if model.entries.isEmpty && !model.isLoadingHistory {
                        Text("// 暂无日志 — 等待系统输出…")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.35))
                            .padding(.vertical, 8)
                            .id("empty")
                    }
                    ForEach(model.entries) { entry in
                        Text(entry.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(entry.level.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
            .onChange(of: model.scrollToken) { _ in
                guard model.autoScroll else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                if model.autoScroll {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalFooter: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(model.clockText.isEmpty ? "--:--:--" : model.clockText)
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundColor(Color.white.opacity(0.55))

            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10))
                Text("\(model.entries.count) log entries")
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundColor(Color.white.opacity(0.55))

            Spacer()

            Toggle(isOn: $model.autoScroll) {
                Text("自动滚动")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.7))
            }
            .toggleStyle(SystemLogCheckboxToggleStyle())
            .foregroundColor(Color.white.opacity(0.7))

            Text(model.connection == .connected ? "实时更新中" : "等待连接")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.45))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: "0a0a0a"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "4fc3f7").opacity(0.2)),
            alignment: .top
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f39c12"))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textPrimary(dark))
                .lineLimit(2)
            Spacer()
            Button("重试") { model.reconnectNow() }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(AppTheme.sidebarActive)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "f39c12").opacity(0.12))
        )
        .padding(.bottom, 8)
    }
}

private struct SystemLogCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(configuration.isOn ? Color(hex: "4fc3f7") : Color.white.opacity(0.45))
                configuration.label
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}


/// Native counterpart of Vue `/system/auditLogs`, entered from the account menu.
struct AuditLogsView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var navigation: NavigationState
    @StateObject private var model = GlobalAuditLogsViewModel()
    @ObservedObject private var language = LanguageManager.shared
    @State private var leaveGuardID = UUID()
    private var dark: Bool { appearance.isDarkEffective }
    private var controlsEnabled: Bool { !model.loading && !model.busy }
    private var canRemove: Bool { controlsEnabled && !model.needsReview }
    private let tableWidth: CGFloat = 1450

    var body: some View {
        VStack(spacing: 0) {
            filters
                .padding(16)
                .background(AppTheme.cardBg(dark))
            if let error = model.error {
                HStack(alignment: .top, spacing: 12) {
                    Text(error).font(.system(size: AppTheme.secondarySize))
                    Spacer()
                    AppButton(title: text("刷新核对", "Refresh and review"), kind: .secondary,
                              enabled: controlsEnabled) { Task { await model.load() } }
                }
                .foregroundColor(AppTheme.danger)
                .padding(12)
                .background(AppTheme.danger.opacity(0.08))
            }
            GeometryReader { geometry in
                NativeHorizontalTable(contentWidth: max(tableWidth, geometry.size.width), viewportWidth: geometry.size.width, height: geometry.size.height) {
                    table(width: max(tableWidth, geometry.size.width))
                }
            }
            PaginationBar(state: $model.pageState) { Task { await model.load() } }
                .disabled(!controlsEnabled)
        }
        .background(AppTheme.cardBg(dark))
        .cornerRadius(AppTheme.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.border(dark), lineWidth: 1))
        .padding(AppTheme.pagePadding)
        .background(AppTheme.pageBg(dark))
        .onAppear {
            navigation.setLeaveGuard(owner: leaveGuardID) {
                guard model.busy else { return true }
                AppAlert.info(title: text("正在删除审计记录", "Deleting audit records"),
                              message: text("请等待当前请求完成。", "Wait for the current request to finish."))
                return false
            }
            Task { await model.load() }
        }
        .onDisappear { model.stop(); navigation.removeLeaveGuard(owner: leaveGuardID) }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.load() }
        }
        .sheet(item: $model.detail) { row in auditDetail(row) }
    }

    private func text(_ zh: String, _ en: String) -> String { language.text(zh, en) }

    private var filters: some View {
        SingleLineToolbar(spacing: 12) {
            HStack(spacing: 10) {
                AppButton(title: text("返回", "Back"), systemImage: "chevron.left", kind: .secondary,
                          enabled: !model.busy) { navigation.select(.dashboard) }
                SearchField(text: $model.keyword,
                            placeholder: text("搜索标题、路径、操作人、IP…", "Search title, path, user or IP…"),
                            onSubmit: { if controlsEnabled { model.search() } }, maxWidth: 360)
                    .frame(width: 260)
                    .disabled(!controlsEnabled)
                AppButton(title: text("搜索", "Search"), systemImage: "magnifyingglass", kind: .secondary,
                          enabled: controlsEnabled) { model.search() }
                Spacer(minLength: 0)
                AppButton(title: text("刷新", "Refresh"), systemImage: "arrow.clockwise", kind: .secondary,
                          isLoading: model.loading, enabled: !model.busy) { Task { await model.load() } }
                Menu {
                    Button(text("批量删除（\(model.selectedIDs.count)）", "Delete selected (\(model.selectedIDs.count))"), action: confirmBatchDelete)
                        .disabled(model.selectedIDs.isEmpty || !canRemove)
                    Button(text("清空全部审计日志", "Clear all audit logs"), action: confirmClear)
                        .disabled(!canRemove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 32)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .fixedSize()
                .help(text("更多操作", "More actions"))
                .disabled(model.busy)
            }
            .fixedSize(horizontal: true, vertical: false)
            Group {
                HStack(spacing: 10) {
                    SelectMenu(options: ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].map { SelectOption(id: $0, title: $0) },
                               selection: $model.method, placeholder: text("全部请求方式", "All methods"), width: 140, searchable: false)
                    SelectMenu(options: [SelectOption(id: "1", title: text("成功", "Success")), SelectOption(id: "0", title: text("失败", "Failure"))],
                               selection: $model.status, placeholder: text("全部状态", "All statuses"), width: 125, searchable: false)
                    DatePicker(text("开始", "From"), selection: $model.startDate, displayedComponents: .date)
                    DatePicker(text("结束", "To"), selection: $model.endDate, displayedComponents: .date)
                    Menu(text("最近 30 天", "Date shortcuts")) {
                        ForEach([1, 7, 30], id: \.self) { days in
                            Button(text("最近 \(days) 天", "Last \(days) days")) {
                                model.endDate = Date()
                                model.startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                                model.search()
                            }
                        }
                    }.fixedSize()
                    AppButton(title: text("应用筛选", "Apply filters"), kind: .secondary) { model.search() }
                    AppButton(title: text("重置", "Reset"), kind: .plain) { model.reset() }
                }
                .font(.system(size: AppTheme.bodySize))
                .foregroundColor(AppTheme.textPrimary(dark))
                .disabled(!controlsEnabled)
                .fixedSize(horizontal: true, vertical: false)
            }
            if !model.selectedIDs.isEmpty {
                HStack(spacing: 12) {
                    Text(text("已选择 \(model.selectedIDs.count) 条记录", "\(model.selectedIDs.count) records selected"))
                    Button(text("批量删除", "Delete selected"), action: confirmBatchDelete).disabled(!canRemove)
                    Button(text("取消选择", "Clear selection")) { model.selectedIDs.removeAll() }.disabled(model.busy)
                }
                .font(.system(size: AppTheme.secondarySize))
                .foregroundColor(AppTheme.textPrimary(dark))
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func table(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                selectionButton(allSelected, title: text("选择本页", "Select this page"), action: togglePage)
                column("ID", width: 64)
                column(text("操作标题 / 执行方法", "Title / action"), width: 200)
                column(text("方式", "Method"), width: 70)
                column(text("请求路径", "Request path"), width: 210)
                }
                Group {
                column(text("操作人", "User"), width: 100)
                column("IP", width: 126)
                column(text("归属地", "Location"), width: 110)
                column(text("状态", "Status"), width: 72)
                column(text("耗时", "Duration"), width: 82)
                column(text("记录时间", "Created"), width: 170)
                column(text("操作", "Actions"), width: 100)
                Spacer(minLength: 0)
                }
            }
            .font(.system(size: AppTheme.bodySize, weight: .medium))
            .frame(height: 42)
            .background(AppTheme.inputBg(dark))
            .disabled(!controlsEnabled)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    if model.rows.isEmpty {
                        VStack(spacing: 12) {
                            if model.loading { ProgressView() }
                            Text(model.loading ? text("正在读取审计记录…", "Loading audit records…") :
                                 (model.error != nil ? text("审计记录读取未完成", "Could not load audit records") : text("暂无匹配的审计日志", "No matching audit logs")))
                                .font(.system(size: AppTheme.bodySize))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 48)
                    } else {
                        ForEach(model.rows) { row in auditRow(row) }
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .foregroundColor(AppTheme.textPrimary(dark))
    }

    private func auditRow(_ row: GlobalAuditLog) -> some View {
        HStack(spacing: 0) {
            Group {
            selectionButton(model.selectedIDs.contains(row.id), title: text("选择记录 #\(row.id)", "Select record #\(row.id)")) {
                if !model.selectedIDs.insert(row.id).inserted { model.selectedIDs.remove(row.id) }
            }
            column("#\(row.id)", width: 64)
            Button(action: { model.detail = row }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title.isEmpty ? "—" : row.title).font(.system(size: AppTheme.bodySize, weight: .medium)).lineLimit(1)
                    Text(row.actionMethod).font(.system(size: AppTheme.secondarySize)).lineLimit(1)
                }
                .frame(width: 184, alignment: .leading).padding(.horizontal, 8)
                .contentShape(Rectangle())
            }.buttonStyle(PlainButtonStyle()).help(row.title + "\n" + row.actionMethod)
            column(row.method, width: 70)
            column(row.requestUri, width: 210)
            }
            Group {
            column(row.username, width: 100)
            column(row.ip, width: 126)
            column(row.location, width: 110)
            column(statusTitle(row.status), width: 72)
                .foregroundColor(row.status == 1 ? AppTheme.success : row.status == 0 ? AppTheme.danger : AppTheme.textPrimary(dark))
            column("\(row.costTime) ms", width: 82)
            column(row.createTime, width: 170)
            HStack(spacing: 12) {
                Button(action: { model.detail = row }) { Image(systemName: "eye") }
                    .help(text("查看详情", "View details"))
                Button(action: { confirmDelete(row) }) { Image(systemName: "trash").foregroundColor(AppTheme.danger) }
                    .disabled(!canRemove).help(text("删除记录", "Delete record"))
            }.buttonStyle(PlainButtonStyle()).frame(width: 100)
            Spacer(minLength: 0)
            }
        }
        .font(.system(size: AppTheme.bodySize))
        .frame(minHeight: 58)
        .background(model.selectedIDs.contains(row.id) ? AppTheme.brand(dark).opacity(0.07) : Color.clear)
        .overlay(Rectangle().fill(AppTheme.border(dark).opacity(0.6)).frame(height: 1), alignment: .bottom)
        .disabled(model.busy)
    }

    private func column(_ value: String, width: CGFloat) -> some View {
        Text(value.isEmpty ? "—" : value).lineLimit(1)
            .frame(width: width - 16, alignment: .leading).padding(.horizontal, 8)
            .help(value)
    }

    private var allSelected: Bool { !model.rows.isEmpty && model.rows.allSatisfy { model.selectedIDs.contains($0.id) } }
    private func togglePage() {
        let ids = model.rows.map(\.id)
        if allSelected { model.selectedIDs.subtract(ids) } else { model.selectedIDs.formUnion(ids) }
    }
    private func selectionButton(_ selected: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: selected ? "checkmark.square.fill" : "square")
                .foregroundColor(selected ? AppTheme.brand(dark) : AppTheme.textPrimary(dark))
                .frame(width: 40, height: 36)
        }.buttonStyle(PlainButtonStyle()).help(title).accessibilityLabel(title)
    }
    private func statusTitle(_ status: Int) -> String {
        status == 1 ? text("成功", "Success") : status == 0 ? text("失败", "Failure") : text("未知", "Unknown")
    }

    private func confirmDelete(_ row: GlobalAuditLog) {
        guard canRemove, AppAlert.confirm(title: text("删除审计记录", "Delete audit record"),
            message: text("永久删除 #\(row.id) · \(row.title) 的操作记录。此操作无法撤销。", "Permanently delete audit record #\(row.id) · \(row.title). This cannot be undone."),
            confirmTitle: text("删除", "Delete"), cancelTitle: text("取消", "Cancel")) else { return }
        Task { await model.remove(.single(row.id)) }
    }
    private func confirmBatchDelete() {
        let ids = model.selectedIDs.sorted()
        guard canRemove, !ids.isEmpty,
              AppAlert.confirm(title: text("批量删除审计记录", "Delete selected audit records"),
                message: text("将永久删除选中的 \(ids.count) 条记录，包含其他分页中的已选记录。此操作无法撤销。", "Permanently delete \(ids.count) selected records, including selections on other pages. This cannot be undone."),
                confirmTitle: text("删除", "Delete"), cancelTitle: text("取消", "Cancel")) else { return }
        Task { await model.remove(.selected(ids)) }
    }
    private func confirmClear() {
        guard canRemove,
              let value = AppAlert.prompt(title: text("清空全部审计日志", "Clear all audit logs"),
                message: text("将永久清空服务器全部历史审计记录，包含当前筛选范围以外的记录。此操作无法撤销。请输入 CLEAR 确认。", "Permanently clear all audit logs on the server, including records outside the current filters. This cannot be undone. Type CLEAR to confirm."),
                placeholder: "CLEAR", confirmTitle: text("清空全部", "Clear all"), cancelTitle: text("取消", "Cancel")),
              value.trimmingCharacters(in: .whitespacesAndNewlines) == "CLEAR" else { return }
        Task { await model.remove(.all) }
    }

    private func auditDetail(_ row: GlobalAuditLog) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(text("审计日志详情 · #\(row.id)", "Audit log details · #\(row.id)"))
                    .font(.system(size: AppTheme.dialogTitleSize, weight: .semibold))
                Spacer()
                AppButton(title: text("关闭", "Close"), kind: .secondary) { model.detail = nil }
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                    detailField(text("操作标题", "Title"), row.title)
                    detailField(text("请求方式与状态", "Method and status"), "\(row.method) · \(statusTitle(row.status)) · HTTP \(row.responseStatus)")
                    detailField(text("请求路径", "Request path"), row.requestUri)
                    detailField(text("后端执行方法", "Backend action"), row.actionMethod)
                    detailField(text("操作人", "User"), row.username)
                    }
                    Group {
                    detailField("IP · " + text("归属地", "Location"), row.ip + " · " + row.location)
                    detailField(text("耗时", "Duration"), "\(row.costTime) ms")
                    detailField(text("记录时间", "Created"), row.createTime)
                    if !row.userAgent.isEmpty { detailField("User-Agent", row.userAgent) }
                    if !row.params.isEmpty { detailField(text("请求参数", "Request parameters"), prettyJSON(row.params), copyable: true) }
                    if !row.errorMsg.isEmpty { detailField(text("错误异常追踪", "Error trace"), row.errorMsg, copyable: true) }
                    }
                }.padding(20)
            }
        }
        .foregroundColor(AppTheme.textPrimary(dark))
        .frame(width: 640, height: 620)
        .background(AppTheme.cardBg(dark))
    }

    private func detailField(_ title: String, _ value: String, copyable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: AppTheme.secondarySize, weight: .medium))
                Spacer()
                if copyable {
                    Button(text("复制", "Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }.font(.system(size: AppTheme.secondarySize))
                }
            }
            Text(value.isEmpty ? "—" : value)
                .font(copyable ? .system(size: AppTheme.bodySize, design: .monospaced) : .system(size: AppTheme.bodySize))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func prettyJSON(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: formatted, encoding: .utf8) else { return value }
        return string
    }
}
