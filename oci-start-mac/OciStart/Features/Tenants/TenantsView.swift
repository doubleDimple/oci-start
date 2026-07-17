import SwiftUI
import AppKit

/// 原生租户管理（AppKit 壳 + SwiftUI 内容，与 Dashboard/Regions 同一路径）。
struct TenantsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = TenantsViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    // 固定列（合计外的剩余宽度分给名称/自定义名/主区域）
    private let wIndex: CGFloat = 40
    private let wCost: CGFloat = 56
    private let wDays: CGFloat = 56
    private let wTask: CGFloat = 72
    private let wMulti: CGFloat = 56
    private let wType: CGFloat = 96
    private let wCreate: CGFloat = 68
    private let wTime: CGFloat = 128
    private let wStatus: CGFloat = 56
    private let wAction: CGFloat = 52
    private let hPad: CGFloat = 12
    private let minName: CGFloat = 88
    private let minDef: CGFloat = 96
    private let minRegion: CGFloat = 88

    private var fixedColsWidth: CGFloat {
        wIndex + wCost + wDays + wTask + wMulti + wType + wCreate + wTime + wStatus + wAction
            + minName + minDef + minRegion + hPad * 2
    }

    var body: some View {
        Group {
            if model.bootPageParent != nil {
                TenantBootCreateView(model: model)
            } else if model.userManageParent != nil {
                TenantUserManageView(model: model)
            } else if model.regionSubParent != nil {
                TenantRegionSubView(model: model)
            } else if model.detailParent != nil {
                // Web 整页：/tenants/regionList → 租户详情
                TenantDetailView(model: model)
            } else if model.trafficParent != nil {
                // Web 整页：/monitor/homePage → 实例流量监控
                TenantTrafficView(model: model)
            } else if model.auditParent != nil {
                // 审计日志：从弹框改为整页（对齐用户管理/流量查询）
                TenantAuditLogView(model: model)
            } else if model.costParent != nil {
                // Web 整页：/cost/costPage → 费用统计
                TenantCostView(model: model)
            } else if model.quotaParent != nil {
                // 账号配额：从弹框改为整页（对齐审计日志/费用统计）
                TenantQuotaView(model: model)
            } else {
                listPage
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            if let p = model.userManageParent {
                Task { await model.loadUsersAndGroups(p) }
            } else if let p = model.regionSubParent {
                Task { await model.refreshRegionSub(p) }
            } else if model.detailParent != nil {
                Task { await model.reloadDetail() }
            } else if let t = model.trafficParent {
                Task { await model.queryTraffic(t) }
            } else if let t = model.auditParent {
                Task { await model.loadAuditLogs(t, append: false) }
            } else if let t = model.costParent {
                Task { await model.queryCost(t) }
            } else if model.quotaParent != nil {
                // 账号配额不自动查询，需用户点击「查询」
            } else {
                Task { await model.reload() }
            }
        }
        .sheet(item: $model.activeSheet) { sheet in
            TenantSheetHost(sheet: sheet, model: model)
                .environmentObject(appearance)
                .environmentObject(session)
        }
        .environmentObject(appearance)
    }

    private var listPage: some View {
        PageScaffold(
            title: "租户管理",
            subtitle: "OCI API 配置与账号列表",
            systemImage: "person.2",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    filterBar
                    if let err = model.errorText, !err.isEmpty { errorBanner(err) }
                    listBody
                    PaginationBar(state: $model.pageState) {
                        Task { await model.reload() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(
                title: model.namesHidden ? "显示名称" : "隐藏名称",
                systemImage: model.namesHidden ? "eye" : "eye.slash",
                kind: .secondary
            ) {
                model.namesHidden.toggle()
            }
            AppButton(title: "API 导入", systemImage: "bolt.fill", kind: .primary) {
                model.openAdd()
            }
            AppButton(title: "导出", systemImage: "square.and.arrow.down", kind: .secondary) {
                model.openExportAll()
            }
            AppButton(title: "导入", systemImage: "square.and.arrow.up", kind: .secondary) {
                model.importJSON()
            }
            AppButton(title: "账号检测", systemImage: "checkmark.circle", kind: .secondary) {
                model.startAccountCheck()
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                Task { await model.reload() }
            }
        }
    }

    private var filterBar: some View {
        FilterBar(
            leading: {
                SearchField(
                    text: $model.searchText,
                    placeholder: "搜索租户名称…",
                    onSubmit: { model.onSearchSubmit() },
                    maxWidth: 320
                )
                .onChange(of: model.searchText) { _ in model.onSearchChanged() }
            },
            trailing: {
                if model.isLoading {
                    ProgressView().scaleEffect(0.7).frame(width: 20, height: AppInputStyle.height)
                } else {
                    Color.clear.frame(width: 1, height: AppInputStyle.height)
                }
            }
        )
        .zIndex(40)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reload() } }.buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
    }

    // MARK: - List（铺满内容区）

    @ViewBuilder
    private var listBody: some View {
        if model.rows.isEmpty && !model.isLoading {
            EmptyStateView(
                icon: "person.2",
                title: "暂无租户",
                subtitle: model.searchText.isEmpty ? "点击「API 导入」添加 OCI 凭据" : "无匹配结果",
                actionTitle: model.searchText.isEmpty ? "API 导入" : "清除搜索",
                action: {
                    if model.searchText.isEmpty { model.openAdd() }
                    else { model.searchText = ""; model.onSearchSubmit() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.rows.isEmpty && model.isLoading {
            VStack {
                Spacer()
                ProgressView()
                Text("加载中…").font(.system(size: 12)).foregroundColor(AppTheme.sidebarText(dark)).padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let totalW = max(geo.size.width, fixedColsWidth)
                let flexPool = max(0, totalW - fixedColsWidth)
                // 名称 / 自定义名 / 主区域 分剩余宽度
                let wName = minName + flexPool * 0.40
                let wDef = minDef + flexPool * 0.35
                let wRegion = minRegion + flexPool * 0.25
                let cols = TenantColWidths(
                    index: wIndex, name: wName, def: wDef, cost: wCost, days: wDays,
                    task: wTask, region: wRegion, multi: wMulti, type: wType,
                    create: wCreate, time: wTime, status: wStatus, action: wAction, hPad: hPad
                )

                VStack(spacing: 0) {
                    headerRow(cols: cols, width: totalW)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { idx, row in
                                tenantRow(index: idx, item: row, cols: cols, width: totalW)
                            }
                        }
                    }
                }
                .frame(width: totalW, height: geo.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headerRow(cols: TenantColWidths, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                colHeader("#", cols.index)
                colHeader("名称", cols.name)
                colHeader("自定义名", cols.def)
                colHeader("费用", cols.cost)
                colHeader("活跃天", cols.days)
                colHeader("开机任务", cols.task)
                colHeader("主区域", cols.region)
            }
            HStack(spacing: 0) {
                colHeader("多区域", cols.multi)
                colHeader("类型", cols.type)
                colHeader("创建", cols.create)
                colHeader("创建时间", cols.time)
                colHeader("状态", cols.status)
                colHeader("操作", cols.action, align: .center)
            }
        }
        .padding(.horizontal, cols.hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .bottom
        )
    }

    private func tenantRow(index: Int, item: TenantItem, cols: TenantColWidths, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                cell("\(model.pageState.page * model.pageState.size + index + 1)", cols.index, muted: true)
                nameCell(item, width: cols.name)
                defNameCell(item, width: cols.def)
                costCell(item, width: cols.cost)
                cell(item.activeDaysText, cols.days)
                StatusBadge(text: item.openTaskText, tone: item.openBootFlag ? .success : .neutral)
                    .frame(width: cols.task, alignment: .leading)
                cell(item.region.isEmpty ? "—" : item.region, cols.region)
            }
            HStack(spacing: 0) {
                cell(item.multiRegionText, cols.multi)
                typeCell(item, width: cols.type)
                bootCell(item, width: cols.create)
                cell(item.createdAt.isEmpty ? "—" : item.createdAt, cols.time, muted: true)
                StatusBadge(text: item.statusText, tone: item.isActive ? .success : .danger)
                    .frame(width: cols.status, alignment: .leading)
                actionCell(item, width: cols.action)
            }
        }
        .padding(.horizontal, cols.hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.3)),
            alignment: .bottom
        )
        .background(
            (index % 2 == 1)
                ? AppTheme.sidebarHover(dark).opacity(0.18)
                : Color.clear
        )
    }

    // MARK: - Cells

    private func nameCell(_ item: TenantItem, width: CGFloat) -> some View {
        Button(action: { model.namesHidden.toggle() }) {
            Text(model.namesHidden ? item.maskedName : item.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func defNameCell(_ item: TenantItem, width: CGFloat) -> some View {
        Button(action: { model.openEditName(item) }) {
            Text(item.defNameText)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarActive)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func costCell(_ item: TenantItem, width: CGFloat) -> some View {
        Button(action: { model.openEditCost(item) }) {
            Text(item.costText)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarActive)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func typeCell(_ item: TenantItem, width: CGFloat) -> some View {
        if item.accountTypeName != "未知", !item.accountTypeName.isEmpty {
            Button(action: { model.activeSheet = .accountDetail(item) }) {
                Text(item.typeText)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarActive)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            cell(item.typeText, width, muted: true)
        }
    }

    @ViewBuilder
    private func bootCell(_ item: TenantItem, width: CGFloat) -> some View {
        if item.cloudType == 1 {
            Button(action: { model.openBoot(item) }) {
                Text("创建")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.sidebarActive)
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: width, alignment: .leading)
        } else {
            cell("—", width, muted: true)
        }
    }

    /// AppKit 三点按钮 + 窗内浮层（不使用 NSPopover，避免超出应用窗口）
    private func actionCell(_ item: TenantItem, width: CGFloat) -> some View {
        TenantActionEllipsisButton(dark: dark, item: item, model: model)
            .environmentObject(appearance)
            .frame(width: width, height: 28)
    }

    private func colHeader(_ title: String, _ w: CGFloat, align: Alignment = .leading) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.sidebarText(dark))
            .frame(width: w, alignment: align)
    }

    private func cell(_ text: String, _ w: CGFloat, bold: Bool = false, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: bold ? .semibold : .regular))
            .foregroundColor(muted ? AppTheme.sidebarText(dark) : (dark ? Color.white.opacity(0.9) : Color.primary))
            .lineLimit(1)
            .frame(width: w, alignment: .leading)
    }
}

// MARK: - Column widths

private struct TenantColWidths {
    let index, name, def, cost, days, task, region, multi, type, create, time, status, action, hPad: CGFloat
}

// MARK: - AppKit ellipsis + 窗内浮层（绝不使用 NSPopover，保证在应用窗口内）

private enum TenantActionMenuLayout {
    static let width: CGFloat = 300
    static let vPad: CGFloat = 12
    static let titleH: CGFloat = 18
    static let gridGap: CGFloat = 8
    static let rowH: CGFloat = 36
    static let cols = 2
    static let margin: CGFloat = 10
    static let minHeight: CGFloat = 140
    static let gap: CGFloat = 6

    static func idealHeight(actionCount: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(actionCount) / Double(cols))))
        let gridH = CGFloat(rows) * rowH + CGFloat(max(0, rows - 1)) * gridGap
        return vPad * 2 + titleH + 8 + gridH
    }

    /// 在 `container`（窗口 contentView）坐标系内计算面板 frame，严格夹紧不越界。
    static func panelFrame(button: NSView, in container: NSView, actionCount: Int) -> NSRect {
        let ideal = idealHeight(actionCount: actionCount)
        let btn = button.convert(button.bounds, to: container)
        let bounds = container.bounds.insetBy(dx: margin, dy: margin)

        var h = min(ideal, bounds.height)
        h = max(minHeight, h)

        // 水平：优先按钮左侧；不够则右侧；再夹紧
        var x = btn.minX - width - gap
        if x < bounds.minX {
            x = btn.maxX + gap
        }
        if x + width > bounds.maxX {
            x = bounds.maxX - width
        }
        x = max(bounds.minX, x)

        // 垂直：底部行优先向上展开（面板底对齐按钮上沿附近）；顶部行向下；中间居中。再夹紧。
        let spaceAbove = bounds.maxY - btn.maxY
        let spaceBelow = btn.minY - bounds.minY
        var y: CGFloat

        if spaceBelow < h * 0.35 {
            // 靠近底部：面板在按钮上方，底边贴近按钮顶
            y = btn.maxY + gap
            if y + h > bounds.maxY {
                h = max(minHeight, bounds.maxY - y)
            }
            if y + h > bounds.maxY {
                y = bounds.maxY - h
            }
        } else if spaceAbove < h * 0.35 {
            // 靠近顶部：面板在按钮下方
            y = btn.minY - h - gap
            if y < bounds.minY {
                y = bounds.minY
                h = max(minHeight, min(ideal, btn.minY - gap - bounds.minY))
            }
        } else {
            // 相对按钮垂直居中
            y = btn.midY - h / 2
            if y < bounds.minY { y = bounds.minY }
            if y + h > bounds.maxY { y = bounds.maxY - h }
        }

        // 最终夹紧
        if h > bounds.height { h = bounds.height }
        if y < bounds.minY { y = bounds.minY }
        if y + h > bounds.maxY { y = bounds.maxY - h }

        return NSRect(x: x, y: y, width: width, height: h)
    }
}

/// 全窗透明点击捕获层，用于关闭菜单。
private final class TenantActionClickCatcher: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }
}

/// 全局单例：窗内操作菜单（列表页 / 租户详情页共用），保证不越出应用窗口。
@MainActor
final class TenantActionMenuPresenter {
    static let shared = TenantActionMenuPresenter()

    private weak var catcher: TenantActionClickCatcher?
    private weak var panelHost: NSView?
    private var localMonitor: Any?

    private init() {}

    var isPresented: Bool { panelHost != nil }

    func dismiss() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        catcher?.removeFromSuperview()
        panelHost?.removeFromSuperview()
        catcher = nil
        panelHost = nil
    }

    /// 租户列表行菜单
    func toggle(
        from button: NSButton,
        item: TenantItem,
        model: TenantsViewModel,
        appearance: AppearanceController,
        dark: Bool
    ) {
        present(
            from: button,
            title: item.displayName,
            dark: dark,
            appearance: appearance,
            actions: TenantActionPanel.actions(for: item, model: model)
        )
    }

    /// 租户详情页行菜单（对齐 Web region_list dropdown）
    func toggleDetail(
        from button: NSButton,
        item: TenantItem,
        model: TenantsViewModel,
        appearance: AppearanceController,
        dark: Bool
    ) {
        present(
            from: button,
            title: item.displayName,
            dark: dark,
            appearance: appearance,
            actions: TenantActionPanel.detailActions(for: item, model: model)
        )
    }

    private func present(
        from button: NSButton,
        title: String,
        dark: Bool,
        appearance: AppearanceController,
        actions: [TenantActionItem]
    ) {
        if isPresented {
            dismiss()
            return
        }
        guard let window = button.window, let content = window.contentView else { return }

        let frame = TenantActionMenuLayout.panelFrame(
            button: button,
            in: content,
            actionCount: actions.count
        )

        let root = TenantActionMenuContent(
            title: title,
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

        let catcher = TenantActionClickCatcher(frame: content.bounds)
        catcher.autoresizingMask = [.width, .height]
        catcher.onClick = { [weak self] in self?.dismiss() }

        content.addSubview(catcher)
        content.addSubview(host)
        self.catcher = catcher
        self.panelHost = host

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
    }
}

private struct TenantActionEllipsisButton: NSViewRepresentable {
    let dark: Bool
    let item: TenantItem
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject var appearance: AppearanceController

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item, model: model, appearance: appearance, dark: dark)
    }

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        b.bezelStyle = .rounded
        b.isBordered = true
        b.title = "···"
        b.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        b.target = context.coordinator
        b.action = #selector(Coordinator.toggleMenu(_:))
        b.setButtonType(.momentaryPushIn)
        context.coordinator.button = b
        return b
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.item = item
        context.coordinator.model = model
        context.coordinator.appearance = appearance
        context.coordinator.dark = dark
    }

    final class Coordinator: NSObject {
        var item: TenantItem
        var model: TenantsViewModel
        var appearance: AppearanceController
        var dark: Bool
        weak var button: NSButton?

        init(item: TenantItem, model: TenantsViewModel, appearance: AppearanceController, dark: Bool) {
            self.item = item
            self.model = model
            self.appearance = appearance
            self.dark = dark
        }

        @objc func toggleMenu(_ sender: NSButton) {
            let btn = sender
            let it = item
            let m = model
            let ap = appearance
            let d = dark
            DispatchQueue.main.async {
                TenantActionMenuPresenter.shared.toggle(
                    from: btn, item: it, model: m, appearance: ap, dark: d
                )
            }
        }
    }
}

// MARK: - 操作菜单数据 / UI

struct TenantActionItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isDanger: Bool
    let action: () -> Void
}

@MainActor
enum TenantActionPanel {
    /// 租户列表操作栏
    static func actions(for item: TenantItem, model: TenantsViewModel) -> [TenantActionItem] {
        var list: [TenantActionItem] = []
        if item.cloudType == 1, !item.isTransferred {
            if item.supportAI == 1 {
                list.append(TenantActionItem(id: "ai", title: "AI", systemImage: "sparkles", isDanger: false) {
                    model.openAI(item)
                })
            }
            list.append(contentsOf: [
                TenantActionItem(id: "boot", title: "创建开机", systemImage: "plus.circle", isDanger: false) { model.openBoot(item) },
                TenantActionItem(id: "upd", title: "更新信息", systemImage: "arrow.clockwise", isDanger: false) { model.updateTenantSSE(item) },
                TenantActionItem(id: "region", title: "租户详情", systemImage: "info.circle", isDanger: false) { model.openRegionList(item) },
                TenantActionItem(id: "sub", title: "区域订阅", systemImage: "globe", isDanger: false) { model.openRegionSub(item) },
                TenantActionItem(id: "users", title: "用户管理", systemImage: "person.2", isDanger: false) { model.openUsers(item) },
                TenantActionItem(id: "traffic", title: "流量预警", systemImage: "bell", isDanger: false) { model.openTraffic(item) },
                TenantActionItem(id: "tsearch", title: "流量查询", systemImage: "chart.bar", isDanger: false) { model.openTrafficPage(item) },
                TenantActionItem(id: "audit", title: "审计日志", systemImage: "doc.text", isDanger: false) { model.openAudit(item) },
                TenantActionItem(id: "cost", title: "账号费用", systemImage: "creditcard", isDanger: false) {
                    model.openCost(item)
                },
                TenantActionItem(id: "export", title: "导出租户", systemImage: "square.and.arrow.down", isDanger: false) { model.openExportOne(item) },
                TenantActionItem(id: "email", title: "邮箱服务", systemImage: "envelope", isDanger: false) { model.openEmail(item) },
                TenantActionItem(id: "social", title: "社媒配置", systemImage: "link", isDanger: false) { model.openSocial(item) },
                TenantActionItem(id: "quota", title: "查看配额", systemImage: "chart.bar", isDanger: false) { model.openQuota(item) }
            ])
        } else if item.cloudType == 2 {
            list.append(TenantActionItem(id: "detail", title: "租户详情", systemImage: "info.circle", isDanger: false) {
                model.openRegionList(item)
            })
        }
        list.append(TenantActionItem(id: "del", title: "删除", systemImage: "trash", isDanger: true) {
            model.confirmDelete(item)
        })
        return list
    }

    /// 租户详情页行菜单（Web tenant_region_list dropdown）
    static func detailActions(for item: TenantItem, model: TenantsViewModel) -> [TenantActionItem] {
        var list: [TenantActionItem] = []
        if item.cloudType == 1 {
            if item.supportAI == 1 {
                list.append(TenantActionItem(id: "ai", title: "AI", systemImage: "sparkles", isDanger: false) {
                    model.openAI(item)
                })
            }
            list.append(contentsOf: [
                TenantActionItem(id: "sync", title: "同步", systemImage: "arrow.2.circlepath", isDanger: false) {
                    model.syncDetailRow(item)
                },
                TenantActionItem(id: "boot", title: "创建开机", systemImage: "plus.circle", isDanger: false) {
                    model.openBoot(item)
                },
                TenantActionItem(id: "findboot", title: "抢机任务", systemImage: "server.rack", isDanger: false) {
                    ToastCenter.shared.error("开机管理页尚未原生化，请稍后在侧栏进入")
                },
                TenantActionItem(id: "vol", title: "磁盘管理", systemImage: "externaldrive", isDanger: false) {
                    model.openVolumes(item)
                },
                TenantActionItem(id: "rules", title: "安全规则", systemImage: "shield", isDanger: false) {
                    model.openSecurityRules(item)
                },
                TenantActionItem(id: "ins", title: "实例列表", systemImage: "desktopcomputer", isDanger: false) {
                    ToastCenter.shared.success("请从侧栏打开「实例列表」查看该租户实例")
                },
                TenantActionItem(id: "mysql", title: "数据库", systemImage: "cylinder", isDanger: false) {
                    model.openMysql(item)
                }
            ])
        } else if item.cloudType == 2 {
            list.append(contentsOf: [
                TenantActionItem(id: "boot", title: "创建开机", systemImage: "plus.circle", isDanger: false) {
                    model.openBoot(item)
                },
                TenantActionItem(id: "sync", title: "同步", systemImage: "arrow.2.circlepath", isDanger: false) {
                    model.syncDetailRow(item)
                }
            ])
        }
        return list
    }
}

/// 窗内菜单内容（两列网格，限高可滚动）
struct TenantActionMenuContent: View {
    var title: String = ""
    let dark: Bool
    var panelHeight: CGFloat = 420
    let actions: [TenantActionItem]
    let onDismiss: () -> Void

    @EnvironmentObject private var appearance: AppearanceController

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(actions) { act in
                        Button(action: {
                            onDismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                act.action()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: act.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 14)
                                Text(act.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundColor(act.isDanger ? Color(hex: "f85149") : (dark ? Color.white.opacity(0.9) : Color.primary))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(act.isDanger
                                          ? Color(hex: "f85149").opacity(0.1)
                                          : AppTheme.sidebarHover(dark).opacity(dark ? 0.55 : 0.7))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(12)
        .frame(width: TenantActionMenuLayout.width, height: panelHeight, alignment: .topLeading)
        .background(AppTheme.pageBg(dark))
        .cornerRadius(12)
    }
}
