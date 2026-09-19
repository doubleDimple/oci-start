import SwiftUI
import AppKit

/// 原生开机管理（对齐 Web `/boot/fullBootList` · `full_machine_list.ftl`）。
/// 列表视觉对齐实例列表：摘要 chip · 卡片表 · 行悬停 · 三点操作菜单 · 窗内两列菜单。
struct BootView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = BootViewModel()

    @State private var hoveredRowId: Int64?

    private var dark: Bool { appearance.isDarkEffective }

    // 固定列宽；租户/备注/区域吃剩余宽度。操作列仅三点菜单。
    private let wIndex: CGFloat = 36
    private let wTenant: CGFloat = 108
    private let wRemark: CGFloat = 80
    private let wRegion: CGFloat = 84
    private let wArch: CGFloat = 60
    private let wStatus: CGFloat = 68
    private let wNum: CGFloat = 48
    private let wTime: CGFloat = 100
    private let wAction: CGFloat = 48
    private let hPad: CGFloat = 12
    private let minFlex: CGFloat = 72

    private var fixedColsWidth: CGFloat {
        wIndex + wTenant + wRemark + wRegion + wArch + wStatus
            + wNum * 7 + wTime + wAction + hPad * 2 + minFlex
    }

    var body: some View {
        Group {
            if model.detailParent != nil {
                BootDetailView(model: model)
                    .environmentObject(appearance)
                    .environmentObject(session)
            } else {
                listPage
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onDisappear { model.stopBootLogIfLeaving() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            if model.detailParent != nil {
                if let p = model.detailParent {
                    Task { await model.loadDetail(p) }
                }
                return
            }
            Task { await model.reload() }
        }
        .sheet(item: $model.activeSheet) { sheet in
            BootSheetHost(sheet: sheet, model: model)
                .environmentObject(appearance)
                .environmentObject(session)
        }
        .environmentObject(appearance)
    }

    private var listPage: some View {
        GeometryReader { proxy in
            PageScaffold(
                title: "开机管理",
                subtitle: filterSubtitle,
                systemImage: "play.circle",
                content: {
                    VStack(spacing: 0) {
                        filterBar(width: proxy.size.width - AppTheme.pagePadding * 2)
                        listBody
                        PaginationBar(state: $model.pageState, disabled: model.isLoading) {
                            model.onPageChange()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appLoading(model.isLoading && !model.rows.isEmpty)
                }
            )
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
    }

    private var filterSubtitle: String {
        if model.hasActiveFilter {
            return "已筛选 · 共 \(model.pageState.totalElements) 组抢机任务"
        }
        return "抢机任务 · 启停 / 详情 / 批量操作 · 共 \(model.pageState.totalElements) 组"
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let error = model.errorText, !error.isEmpty {
                PageErrorIndicator(message: error, retry: { Task { await model.reload() } })
            }
            AppButton(
                title: model.namesHidden ? "显示名称" : "隐藏名称",
                systemImage: model.namesHidden ? "eye" : "eye.slash",
                kind: .secondary
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.namesHidden.toggle()
                }
            }
            AppButton(title: "批量启动", systemImage: "play.circle", kind: .primary) {
                model.batchStart()
            }
            AppButton(title: "批量停止", systemImage: "stop.circle", kind: .secondary) {
                model.batchStop()
            }
            AppButton(title: "重置失败", systemImage: "arrow.counterclockwise", kind: .secondary) {
                model.batchResetFail()
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.isLoading
            ) {
                Task { await model.reload() }
            }
        }
    }

    // MARK: - Filter

    private func filterBar(width: CGFloat) -> some View {
        AdaptiveListToolbar(
            compactBelow: 1160,
            availableWidth: width,
            filters: {
                HStack(spacing: 10) {
                    SelectMenu(
                        options: model.parentTenants.map {
                            SelectOption(id: $0.id, title: model.tenantLabel($0))
                        },
                        selection: Binding(
                            get: { model.selectedParentId.isEmpty ? nil : model.selectedParentId },
                            set: { model.onParentChanged($0) }
                        ),
                        placeholder: "选择租户…",
                        width: 160,
                        allowClear: true,
                        searchable: true
                    )
                    SelectMenu(
                        options: model.regions.map {
                            SelectOption(id: $0.id, title: model.regionLabel($0))
                        },
                        selection: Binding(
                            get: { model.selectedRegionId.isEmpty ? nil : model.selectedRegionId },
                            set: { model.onRegionChanged($0) }
                        ),
                        placeholder: model.selectedParentId.isEmpty ? "先选租户" : "选择区域…",
                        width: 160,
                        enabled: !model.selectedParentId.isEmpty,
                        allowClear: true,
                        searchable: true
                    )
                }
                HStack(spacing: 8) {
                    if model.hasActiveFilter {
                        AppButton(title: "重置", systemImage: "xmark", kind: .secondary) {
                            model.resetFilter()
                        }
                    }
                    AppButton(
                        title: "查询",
                        systemImage: "magnifyingglass",
                        kind: .secondary,
                        enabled: model.canQuery || model.hasActiveFilter
                    ) {
                        model.applyFilter()
                    }
                }
            },
            actions: { toolbar }
        )
    }

    // MARK: - Error


    // MARK: - List

    @ViewBuilder
    private var listBody: some View {
        if model.isLoading && model.rows.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text("加载开机任务…")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(dark))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tableCardBackground)
        } else if model.rows.isEmpty {
            EmptyStateView(
                icon: "play.circle",
                title: "暂无开机任务",
                subtitle: model.hasActiveFilter
                    ? "当前筛选条件下没有抢机配置"
                    : "可在租户管理中创建抢机配置，或调整筛选后查询",
                actionTitle: "刷新",
                action: { Task { await model.reload() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tableCardBackground)
        } else {
            GeometryReader { geo in
                let totalW = max(geo.size.width, fixedColsWidth)
                let flex = max(0, totalW - fixedColsWidth + minFlex)
                let wTenantFlex = wTenant + flex * 0.4
                let wRemarkFlex = wRemark + flex * 0.3
                let wRegionFlex = wRegion + flex * 0.3
                let table = VStack(spacing: 0) {
                    headerRow(
                        wTenant: wTenantFlex,
                        wRemark: wRemarkFlex,
                        wRegion: wRegionFlex,
                        width: totalW
                    )
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { idx, item in
                                dataRow(
                                    index: idx,
                                    item: item,
                                    wTenant: wTenantFlex,
                                    wRemark: wRemarkFlex,
                                    wRegion: wRegionFlex,
                                    width: totalW
                                )
                            }
                        }
                    }
                }
                .frame(width: totalW, height: geo.size.height, alignment: .topLeading)

                NativeFixedTrailingTable(contentWidth: totalW, viewportWidth: geo.size.width, height: geo.size.height) { table }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keep row actions outside clipping; the shared scaffold owns the card.
            .background(tableCardBackground)
        }
    }

    private var tableCardBackground: some View {
        AppTheme.cardBg(dark)
    }

    private func headerRow(
        wTenant: CGFloat,
        wRemark: CGFloat,
        wRegion: CGFloat,
        width: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Group {
                colHeader("#", wIndex)
                colHeader("租户", wTenant)
                colHeader("备注", wRemark)
                colHeader("区域", wRegion)
                colHeader("架构", wArch)
            }
            Group {
                colHeader("状态", wStatus)
                colHeader("任务数", wNum)
                colHeader("执行中", wNum)
                colHeader("总次数", wNum)
                colHeader("昨日", wNum)
            }
            Group {
                colHeader("今日", wNum)
                colHeader("失败", wNum)
                colHeader("成功", wNum)
                colHeader("创建时间", wTime)
                Color.clear.frame(width: wAction, height: 1)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.inputBg(dark))
        .modifier(NativeFixedTableActions(width: wAction, trailingPadding: hPad, background: AppTheme.inputBg(dark)) {
            colHeader("操作", wAction, align: .center)
        })
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .bottom
        )
    }

    private func dataRow(
        index: Int,
        item: BootTaskItem,
        wTenant: CGFloat,
        wRemark: CGFloat,
        wRegion: CGFloat,
        width: CGFloat
    ) -> some View {
        let hovered = hoveredRowId == item.id
        return HStack(spacing: 0) {
            Group {
                cellText("\(model.pageState.page * model.pageState.size + index + 1)", wIndex, muted: true)
                tenantCell(item, width: wTenant)
                cellText(item.remarkText, wRemark)
                cellText(item.regionName.isEmpty ? "—" : item.regionName, wRegion)
                archChip(item.archText)
                    .frame(width: wArch, alignment: .leading)
                    .clipped()
            }
            Group {
                StatusBadge(text: item.taskStatusText, tone: item.taskStatusTone)
                    .frame(width: wStatus, alignment: .leading)
                    .clipped()
                numCell(item.recordCount, wNum)
                numCell(item.executingCount, wNum, accent: item.executingCount > 0 ? Color(hex: "f0881a") : nil)
                numCell(item.totalCount, wNum)
                cellText(formatNum(Int64(item.yesterdayAttemptCount)), wNum, muted: true)
            }
            Group {
                cellText(formatNum(Int64(item.currentAttemptCount)), wNum)
                cellText(formatNum(Int64(item.failCount)), wNum)
                successCell(item.successCount, wNum)
                cellText(item.createText, wTime, muted: true)
                Color.clear.frame(width: wAction, height: 26)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground(index: index, hovered: hovered))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.28)),
            alignment: .bottom
        )
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredRowId = inside ? item.id : (hoveredRowId == item.id ? nil : hoveredRowId)
            }
        }
        .onTapGesture(count: 2) {
            model.openDetail(item)
        }
        .modifier(NativeFixedTableActions(width: wAction, trailingPadding: hPad,
                                         background: hovered ? AppTheme.mix(AppTheme.sidebarActive, fraction: dark ? 0.12 : 0.08, with: AppTheme.cardBg(dark)) : index % 2 == 1 ? AppTheme.hover(dark) : AppTheme.cardBg(dark)) {
            actionBar(item).frame(width: wAction, alignment: .center)
        })
    }

    private func rowBackground(index: Int, hovered: Bool) -> Color {
        if hovered {
            return AppTheme.sidebarActive.opacity(dark ? 0.12 : 0.08)
        }
        return index % 2 == 1
            ? AppTheme.hover(dark)
            : Color.clear
    }

    // MARK: - Cells

    private func colHeader(_ title: String, _ width: CGFloat, align: Alignment = .leading) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.textSecondary(dark))
            .lineLimit(1)
            .frame(width: width, alignment: align)
            .clipped()
    }

    private func cellText(_ text: String, _ width: CGFloat, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(
                muted
                    ? AppTheme.textSecondary(dark)
                    : (AppTheme.textPrimary(dark))
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
            .clipped()
            .help(text)
    }

    private func numCell(_ n: Int64, _ width: CGFloat, accent: Color? = nil) -> some View {
        Text(formatNum(n))
            .font(.system(size: 14, weight: accent != nil ? .semibold : .regular, design: .monospaced))
            .foregroundColor(
                accent ?? (AppTheme.textPrimary(dark))
            )
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .clipped()
    }

    private func successCell(_ n: Int, _ width: CGFloat) -> some View {
        Text(formatNum(Int64(n)))
            .font(.system(size: 14, weight: n > 0 ? .semibold : .regular, design: .monospaced))
            .foregroundColor(n > 0 ? Color(hex: "3fb950") : (AppTheme.textPrimary(dark)))
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .clipped()
    }

    private func tenantCell(_ item: BootTaskItem, width: CGFloat) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { model.namesHidden.toggle() }
        }) {
            Text(model.namesHidden ? item.maskedTenant : item.displayTenant)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(dark))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(item.displayTenant + "\n点击切换名称显示")
    }

    private func archChip(_ text: String) -> some View {
        let t = text.isEmpty || text == "—" ? "—" : text
        let isARM = t.uppercased().contains("ARM")
        let c = isARM ? Color(hex: "a371f7") : Color(hex: "58a6ff")
        return Text(t)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(t == "—" ? AppTheme.textSecondary(dark) : c)
            .padding(.horizontal, t == "—" ? 0 : 7)
            .padding(.vertical, t == "—" ? 0 : 2)
            .background(
                Group {
                    if t != "—" {
                        Capsule().fill(c.opacity(0.14))
                    }
                }
            )
    }

    private func formatNum(_ n: Int64) -> String {
        if n >= 10_000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            return f.string(from: NSNumber(value: n)) ?? "\(n)"
        }
        return "\(n)"
    }

    // MARK: - Row actions

    private func actionBar(_ item: BootTaskItem) -> some View {
        BootActionMoreButton(dark: dark, item: item, model: model)
            .environmentObject(appearance)
            .frame(width: 28, height: 26)
    }
}

// MARK: - Action menu data

struct BootActionItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isDanger: Bool
    let action: () -> Void
}

enum BootActionPanel {
    static func actions(for item: BootTaskItem, model: BootViewModel) -> [BootActionItem] {
        func run(_ body: @escaping @MainActor () -> Void) -> () -> Void {
            return {
                Task { @MainActor in body() }
            }
        }
        func make(
            _ id: String,
            _ title: String,
            _ icon: String,
            danger: Bool = false,
            _ body: @escaping @MainActor () -> Void
        ) -> BootActionItem {
            BootActionItem(
                id: id, title: title, systemImage: icon,
                isDanger: danger, action: run(body)
            )
        }
        return [
            make("clone", "克隆开机", "doc.on.doc") { model.confirmClone(item) },
            make("start", "启动", "play.fill") { model.confirmStart(item) },
            make("stop", "停止", "stop.fill") { model.confirmStop(item) },
            make("detail", "开机详情", "list.bullet.rectangle") { model.openDetail(item) },
            make("log", "开机日志", "text.alignleft") { model.openBootLog(for: item) },
            make("add", "添加抢机配置", "plus.circle") { model.openAddConfig(item) },
            make("manual", "手动抢机", "hand.raised") { model.confirmManual(item) },
            make("del", "删除", "trash", danger: true) { model.confirmDelete(item) }
        ]
    }
}

// MARK: - 窗内操作菜单（对齐实例列表，扁平两列 + 悬停）

private enum BootActionMenuLayout {
    static let width: CGFloat = 340
    static let vPad: CGFloat = 12
    static let titleH: CGFloat = 18
    static let gridGap: CGFloat = 8
    static let rowH: CGFloat = 36
    static let cols = 2
    static let margin: CGFloat = 10
    static let minHeight: CGFloat = 140
    static let gap: CGFloat = 6

    static func idealHeight(itemCount: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(itemCount) / Double(cols))))
        return vPad * 2 + titleH + 8
            + CGFloat(rows) * rowH + CGFloat(max(0, rows - 1)) * gridGap
    }

    static func panelFrame(button: NSView, in container: NSView, itemCount: Int) -> NSRect {
        let ideal = idealHeight(itemCount: itemCount)
        let btn = button.convert(button.bounds, to: container)
        let bounds = container.bounds.insetBy(dx: margin, dy: margin)
        var h = min(ideal, bounds.height)
        h = max(minHeight, h)

        var x = btn.minX - width - gap
        if x < bounds.minX { x = btn.maxX + gap }
        if x + width > bounds.maxX { x = bounds.maxX - width }
        x = max(bounds.minX, x)

        var y = btn.midY - h / 2
        if y < bounds.minY { y = bounds.minY }
        if y + h > bounds.maxY { y = bounds.maxY - h }
        return NSRect(x: x, y: y, width: width, height: h)
    }
}

/// 开机管理操作菜单。不用全窗 ClickCatcher 吞事件，避免 dismiss 失败后整页点不动。
@MainActor
final class BootActionMenuPresenter {
    static let shared = BootActionMenuPresenter()
    private var panelHost: NSView?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private init() {}

    var isPresented: Bool { panelHost != nil }

    func dismiss() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        panelHost?.removeFromSuperview()
        panelHost = nil
    }

    func toggle(
        from button: NSButton,
        item: BootTaskItem,
        model: BootViewModel,
        appearance: AppearanceController,
        dark: Bool
    ) {
        if isPresented {
            dismiss()
            return
        }
        guard let window = button.window, let content = window.contentView else { return }
        dismiss()

        let actions = BootActionPanel.actions(for: item, model: model)
        let frame = BootActionMenuLayout.panelFrame(
            button: button,
            in: content,
            itemCount: actions.count
        )
        let root = BootActionMenuContent(
            title: item.displayTenant,
            dark: dark,
            panelHeight: frame.height,
            actions: actions,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        .environmentObject(appearance)

        let host = NSHostingView(rootView: root)
        host.frame = frame
        host.wantsLayer = true
        if let layer = host.layer {
            layer.cornerRadius = 12
            layer.masksToBounds = false
            layer.borderWidth = 1
            layer.borderColor = (dark
                ? NSColor(calibratedWhite: 1, alpha: 0.12)
                : NSColor(calibratedWhite: 0, alpha: 0.10)).cgColor
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = Float(dark ? 0.45 : 0.18)
            layer.shadowRadius = 14
            layer.shadowOffset = CGSize(width: 0, height: -3)
        }

        content.addSubview(host)
        panelHost = host

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let host = self.panelHost else { return event }
            let loc = event.locationInWindow
            let frameInWindow = host.convert(host.bounds, to: nil)
            if !frameInWindow.contains(loc) {
                DispatchQueue.main.async { self.dismiss() }
            }
            return event
        }
    }
}

struct BootActionMenuContent: View {
    var title: String = ""
    let dark: Bool
    var panelHeight: CGFloat = 280
    let actions: [BootActionItem]
    let onDismiss: () -> Void

    @EnvironmentObject private var appearance: AppearanceController
    @State private var hoveredId: String?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary(dark))
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(actions) { act in
                        actionButton(act)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: BootActionMenuLayout.width, height: panelHeight, alignment: .topLeading)
        .background(AppTheme.pageBg(dark))
        .cornerRadius(12)
    }

    private func actionButton(_ act: BootActionItem) -> some View {
        let hovered = hoveredId == act.id
        return Button(action: {
            let run = act.action
            onDismiss()
            DispatchQueue.main.async { run() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: act.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(act.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(
                act.isDanger
                    ? Color(hex: "f85149")
                    : (AppTheme.textPrimary(dark))
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(buttonFill(act: act, hovered: hovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        hovered
                            ? (act.isDanger
                               ? Color(hex: "f85149").opacity(0.45)
                               : AppTheme.sidebarActive.opacity(0.45))
                            : AppTheme.border(dark).opacity(0.4),
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredId = inside ? act.id : (hoveredId == act.id ? nil : hoveredId)
            }
        }
    }

    private func buttonFill(act: BootActionItem, hovered: Bool) -> Color {
        if hovered {
            if act.isDanger {
                return Color(hex: "f85149").opacity(dark ? 0.22 : 0.16)
            }
            return AppTheme.sidebarActive.opacity(dark ? 0.22 : 0.14)
        }
        if act.isDanger {
            return Color(hex: "f85149").opacity(0.06)
        }
        return dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }
}

private struct BootActionMoreButton: NSViewRepresentable {
    let dark: Bool
    let item: BootTaskItem
    @ObservedObject var model: BootViewModel
    @EnvironmentObject var appearance: AppearanceController

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item, model: model, appearance: appearance, dark: dark)
    }

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 26))
        b.bezelStyle = .shadowlessSquare
        b.isBordered = false
        b.title = ""
        b.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多")
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleProportionallyDown
        b.contentTintColor = dark
            ? NSColor.white.withAlphaComponent(0.9)
            : NSColor.labelColor
        b.wantsLayer = true
        if let layer = b.layer {
            layer.cornerRadius = 7
            layer.backgroundColor = (dark
                ? NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.21, alpha: 1)
                : NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)).cgColor
            layer.borderWidth = 1
            layer.borderColor = (dark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.08)).cgColor
        }
        b.target = context.coordinator
        b.action = #selector(Coordinator.toggle(_:))
        b.setButtonType(.momentaryChange)
        b.toolTip = "更多操作"
        return b
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.item = item
        context.coordinator.model = model
        context.coordinator.appearance = appearance
        context.coordinator.dark = dark
        nsView.contentTintColor = dark
            ? NSColor.white.withAlphaComponent(0.9)
            : NSColor.labelColor
        if let layer = nsView.layer {
            layer.backgroundColor = (dark
                ? NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.21, alpha: 1)
                : NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)).cgColor
            layer.borderColor = (dark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.08)).cgColor
        }
    }

    final class Coordinator: NSObject {
        var item: BootTaskItem
        var model: BootViewModel
        var appearance: AppearanceController
        var dark: Bool

        init(item: BootTaskItem, model: BootViewModel, appearance: AppearanceController, dark: Bool) {
            self.item = item
            self.model = model
            self.appearance = appearance
            self.dark = dark
        }

        @objc func toggle(_ sender: NSButton) {
            let btn = sender
            let it = item
            let m = model
            let ap = appearance
            let d = dark
            DispatchQueue.main.async {
                BootActionMenuPresenter.shared.toggle(
                    from: btn, item: it, model: m, appearance: ap, dark: d
                )
            }
        }
    }
}
