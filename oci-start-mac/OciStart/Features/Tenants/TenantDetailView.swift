import SwiftUI
import AppKit

/// Web 整页「租户详情」`/tenants/regionList` → `tenant_region_list.ftl`
/// 从租户列表进入，非弹框。布局对齐列表页 + 质量管理页的间距/圆角体系。
struct TenantDetailView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession

    @State private var hoveredRowId: Int64?

    private var dark: Bool { appearance.isDarkEffective }
    private var parent: TenantItem? { model.detailParent }

    // 列宽
    private let wIndex: CGFloat = 40
    private let wTask: CGFloat = 72
    private let wRegion: CGFloat = 110
    private let wHome: CGFloat = 64
    private let wSync: CGFloat = 72
    private let wTime: CGFloat = 132
    private let wAction: CGFloat = 168
    private let minName: CGFloat = 120
    private let minDef: CGFloat = 96
    private let hPad: CGFloat = 14

    private var syncedCount: Int {
        model.detailRows.filter(\.apiSynced).count
    }
    private var bootTaskCount: Int {
        model.detailRows.filter(\.openBootFlag).count
    }
    private var homeCount: Int {
        model.detailRows.filter(\.isHomeRegion).count
    }

    var body: some View {
        PageScaffold(
            title: "租户详情",
            subtitle: parent.map {
                let region = $0.region.isEmpty ? "—" : $0.region
                return "\($0.displayName) · \(region)"
            },
            systemImage: "key.fill",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.detailError, !err.isEmpty {
                        errorBanner(err)
                    }
                    summaryBar
                    listBody
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .appLoading(model.detailLoading && !model.detailRows.isEmpty)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "返回列表", systemImage: "chevron.left", kind: .secondary) {
                model.closeDetail()
            }
            AppButton(
                title: model.detailNamesHidden ? "显示名称" : "隐藏名称",
                systemImage: model.detailNamesHidden ? "eye" : "eye.slash",
                kind: .secondary
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.detailNamesHidden.toggle()
                }
            }
            AppButton(title: "API 导入", systemImage: "bolt.fill", kind: .primary) {
                model.openAdd()
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.detailLoading
            ) {
                Task { await model.reloadDetail() }
            }
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(spacing: 10) {
            summaryChip(
                icon: "globe",
                title: "区域",
                value: "\(model.detailRows.count)",
                accent: AppTheme.sidebarActive
            )
            summaryChip(
                icon: "arrow.2.circlepath",
                title: "已同步",
                value: "\(syncedCount)",
                accent: Color(hex: "3fb950")
            )
            summaryChip(
                icon: "play.circle",
                title: "开机任务",
                value: "\(bootTaskCount)",
                accent: Color(hex: "d29922")
            )
            summaryChip(
                icon: "house",
                title: "主区域",
                value: "\(homeCount)",
                accent: Color(hex: "a371f7")
            )
            Spacer(minLength: 0)
            Text("行内快捷：同步 · 开机 · 实例 · 更多")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark).opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func summaryChip(icon: String, title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.sidebarText(dark))
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.sidebarBg(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1)
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reloadDetail() } }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Table

    @ViewBuilder
    private var listBody: some View {
        if model.detailLoading && model.detailRows.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text("加载区域列表…")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tableCardBackground)
        } else if model.detailRows.isEmpty {
            EmptyStateView(
                icon: "globe",
                title: "暂无区域",
                subtitle: "该租户下没有可展示的区域",
                actionTitle: "返回",
                action: { model.closeDetail() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tableCardBackground)
        } else {
            GeometryReader { geo in
                let fixed = wIndex + wTask + wRegion + wHome + wSync + wTime + wAction + minName + minDef + hPad * 2
                let totalW = max(geo.size.width, fixed)
                let flex = max(0, totalW - fixed)
                let wName = minName + flex * 0.55
                let wDef = minDef + flex * 0.45

                VStack(spacing: 0) {
                    headerRow(wName: wName, wDef: wDef, width: totalW)
                    ScrollView {
                        // 必须用 offset 做 identity：regionList 在异常/兜底数据下可能出现重复 id，
                        // macOS 11 SwiftUI 会 fatalError「each layout item may only occur once」直接退出。
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.detailRows.enumerated()), id: \.offset) { idx, row in
                                dataRow(index: idx, item: row, wName: wName, wDef: wDef, width: totalW)
                                    .id("detail-row-\(idx)-\(row.id)")
                            }
                        }
                    }
                }
                .frame(width: totalW, height: geo.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tableCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(dark ? 0.22 : 0.06), radius: 8, x: 0, y: 2)
        }
    }

    private var tableCardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(AppTheme.sidebarBg(dark))
    }

    private func headerRow(wName: CGFloat, wDef: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            colHeader("#", wIndex)
            colHeader("名称", wName)
            colHeader("自定义名", wDef)
            colHeader("开机任务", wTask)
            colHeader("区域", wRegion)
            colHeader("主区域", wHome)
            colHeader("同步", wSync)
            colHeader("创建时间", wTime)
            colHeader("操作", wAction, align: .center)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .bottom
        )
    }

    private func dataRow(index: Int, item: TenantItem, wName: CGFloat, wDef: CGFloat, width: CGFloat) -> some View {
        let hovered = hoveredRowId == item.id
        return HStack(spacing: 0) {
            cell("\(index + 1)", wIndex, muted: true)
            nameCell(item, width: wName)
            cell(item.defNameText, wDef)
            taskCell(item)
                .frame(width: wTask, alignment: .leading)
            regionCell(item, width: wRegion)
            homeBadge(item)
                .frame(width: wHome, alignment: .leading)
            StatusBadge(
                text: item.syncStatusText,
                tone: item.apiSynced ? .success : .danger
            )
            .frame(width: wSync, alignment: .leading)
            cell(item.createdAt.isEmpty ? "—" : item.createdAt, wTime, muted: true)
            actionBar(item)
                .frame(width: wAction, alignment: .center)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
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
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }

    private func rowBackground(index: Int, hovered: Bool) -> Color {
        if hovered {
            return AppTheme.sidebarActive.opacity(dark ? 0.12 : 0.08)
        }
        return index % 2 == 1
            ? AppTheme.sidebarHover(dark).opacity(0.18)
            : Color.clear
    }

    private func nameCell(_ item: TenantItem, width: CGFloat) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.detailNamesHidden.toggle()
            }
        }) {
            Text(model.detailNamesHidden ? item.maskedName : item.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(model.detailNamesHidden ? "点击显示名称" : "点击隐藏名称")
    }

    private func taskCell(_ item: TenantItem) -> some View {
        Button(action: { model.openBootTaskList(item) }) {
            StatusBadge(
                text: item.openTaskText,
                tone: item.openBootFlag ? .success : .neutral
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("查看该区域抢机任务")
    }

    private func regionCell(_ item: TenantItem, width: CGFloat) -> some View {
        Button(action: { model.openInstancesList(item) }) {
            HStack(spacing: 4) {
                Text(item.region.isEmpty ? "—" : item.region)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarActive)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppTheme.sidebarActive.opacity(0.75))
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help("打开该区域实例列表")
    }

    private func homeBadge(_ item: TenantItem) -> some View {
        Text(item.isHomeRegion ? "是" : "否")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(item.isHomeRegion ? AppTheme.sidebarActive : AppTheme.sidebarText(dark))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    item.isHomeRegion
                        ? AppTheme.sidebarActive.opacity(0.15)
                        : AppTheme.sidebarHover(dark).opacity(0.5)
                )
            )
    }

    /// 行内快捷：同步 / 创建开机 / 实例 + 更多（对齐 Web 全量菜单）
    private func actionBar(_ item: TenantItem) -> some View {
        HStack(spacing: 4) {
            if item.cloudType == 1 {
                quickIcon(
                    systemImage: "arrow.2.circlepath",
                    help: "同步",
                    accent: false
                ) {
                    model.syncDetailRow(item)
                }
                quickIcon(
                    systemImage: "plus.circle",
                    help: "创建开机",
                    accent: true
                ) {
                    model.openBoot(item)
                }
                quickIcon(
                    systemImage: "desktopcomputer",
                    help: "实例列表",
                    accent: false
                ) {
                    model.openInstancesList(item)
                }
            } else if item.cloudType == 2 {
                quickIcon(
                    systemImage: "plus.circle",
                    help: "创建开机",
                    accent: true
                ) {
                    model.openBoot(item)
                }
                quickIcon(
                    systemImage: "arrow.2.circlepath",
                    help: "同步",
                    accent: false
                ) {
                    model.syncDetailRow(item)
                }
            }
            TenantDetailActionButton(dark: dark, item: item, model: model)
                .environmentObject(appearance)
                .frame(width: 30, height: 26)
        }
    }

    private func quickIcon(
        systemImage: String,
        help: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accent ? .white : (dark ? Color.white.opacity(0.9) : Color.primary))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(accent
                              ? AppTheme.sidebarActive
                              : (dark ? Color(hex: "2c3136") : Color(hex: "eef2f6")))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(AppTheme.border(dark).opacity(accent ? 0 : 0.7), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(help)
    }

    private func colHeader(_ title: String, _ w: CGFloat, align: Alignment = .leading) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.sidebarText(dark))
            .frame(width: w, alignment: align)
    }

    private func cell(_ text: String, _ w: CGFloat, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(muted ? AppTheme.sidebarText(dark) : (dark ? Color.white.opacity(0.9) : Color.primary))
            .lineLimit(1)
            .frame(width: w, alignment: .leading)
    }
}

// MARK: - 详情页「更多」菜单（对齐 Web dropdown 剩余项）

private struct TenantDetailActionButton: NSViewRepresentable {
    let dark: Bool
    let item: TenantItem
    @ObservedObject var model: TenantsViewModel
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
        var item: TenantItem
        var model: TenantsViewModel
        var appearance: AppearanceController
        var dark: Bool

        init(item: TenantItem, model: TenantsViewModel, appearance: AppearanceController, dark: Bool) {
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
                TenantActionMenuPresenter.shared.toggleDetail(
                    from: btn, item: it, model: m, appearance: ap, dark: d
                )
            }
        }
    }
}
