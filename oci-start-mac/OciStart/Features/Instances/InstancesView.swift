import SwiftUI
import AppKit

/// 原生实例列表（对齐 Web `/oci/list` · `oci_machine_list.ftl`）。
struct InstancesView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = InstancesViewModel()

    @State private var hoveredRowId: String?

    private var dark: Bool { appearance.isDarkEffective }

    // 固定列宽；名称/IP 分剩余宽度
    private let wIndex: CGFloat = 40
    private let wTenant: CGFloat = 108
    private let wRegion: CGFloat = 96
    private let wCpu: CGFloat = 64
    private let wArch: CGFloat = 68
    private let wVol: CGFloat = 86
    private let wIpv6: CGFloat = 52
    private let wTime: CGFloat = 92
    private let wAction: CGFloat = 132
    private let hPad: CGFloat = 14
    private let minName: CGFloat = 120
    private let minIp: CGFloat = 100

    private var fixedColsWidth: CGFloat {
        wIndex + wTenant + wRegion + wCpu + wArch + wVol + wIpv6 + wTime + wAction
            + minName + minIp + hPad * 2
    }

    var body: some View {
        Group {
            if let item = model.sshItem {
                InstanceSSHView(item: item, onBack: { model.closeSSH() })
                    .environmentObject(appearance)
                    .environmentObject(session)
            } else if let item = model.consoleItem {
                InstanceConsoleView(item: item, onBack: { model.closeConsole() })
                    .environmentObject(appearance)
                    .environmentObject(session)
            } else if let item = model.vnicItem {
                InstanceVnicView(item: item, onBack: { model.closeVnic() })
                    .environmentObject(appearance)
                    .environmentObject(session)
            } else {
                listPage
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            if model.sshItem != nil || model.consoleItem != nil || model.vnicItem != nil { return }
            Task { await model.reload() }
        }
        .sheet(item: $model.activeSheet) { sheet in
            InstanceSheetHost(sheet: sheet, model: model)
                .environmentObject(appearance)
                .environmentObject(session)
        }
        .environmentObject(appearance)
    }

    private var listPage: some View {
        PageScaffold(
            title: "实例列表",
            subtitle: filterSubtitle,
            systemImage: "server.rack",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    filterBar
                    if let err = model.errorText, !err.isEmpty { errorBanner(err) }
                    summaryBar
                    listBody
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    PaginationBar(state: $model.pageState) {
                        model.onPageChange()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.isLoading && !model.rows.isEmpty)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private var filterSubtitle: String {
        if model.hasActiveFilter {
            return "已筛选 · 共 \(model.pageState.totalElements) 台"
        }
        return "OCI 实例管理 · 共 \(model.pageState.totalElements) 台"
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(
                title: model.namesHidden ? "显示名称" : "隐藏名称",
                systemImage: model.namesHidden ? "eye" : "eye.slash",
                kind: .secondary
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.namesHidden.toggle()
                }
            }
            AppButton(title: "导出", systemImage: "square.and.arrow.down", kind: .secondary) {
                model.exportInstances()
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

    private var filterBar: some View {
        FilterBar(
            leading: {
                HStack(spacing: 10) {
                    SelectMenu(
                        options: model.parentTenants.map { SelectOption(id: $0.id, title: parentLabel($0)) },
                        selection: Binding(
                            get: { model.selectedParentId.isEmpty ? nil : model.selectedParentId },
                            set: { model.onParentChanged($0) }
                        ),
                        placeholder: "选择租户…",
                        width: 200,
                        allowClear: true,
                        searchable: true
                    )
                    SelectMenu(
                        options: model.regions.map { SelectOption(id: $0.id, title: regionLabel($0)) },
                        selection: Binding(
                            get: { model.selectedRegionId.isEmpty ? nil : model.selectedRegionId },
                            set: { model.onRegionChanged($0) }
                        ),
                        placeholder: model.selectedParentId.isEmpty ? "先选租户" : "选择区域…",
                        width: 200,
                        enabled: !model.selectedParentId.isEmpty,
                        allowClear: true,
                        searchable: true
                    )
                }
            },
            trailing: {
                HStack(spacing: 8) {
                    if model.hasActiveFilter {
                        AppButton(title: "重置", systemImage: "xmark", kind: .secondary) {
                            model.resetFilter()
                        }
                    }
                    AppButton(
                        title: "查询",
                        systemImage: "magnifyingglass",
                        kind: .primary,
                        enabled: model.canQuery || model.hasActiveFilter
                    ) {
                        model.applyFilter()
                    }
                }
            }
        )
    }

    /// 对齐 Web：`userName || tenancyName || id`
    private func parentLabel(_ t: TenantRegionOption) -> String {
        if !t.userName.isEmpty { return t.userName }
        if !t.tenancyName.isEmpty { return t.tenancyName }
        return t.id
    }

    private func regionLabel(_ r: TenantRegionOption) -> String {
        var s = r.region.isEmpty ? (r.tenancyName.isEmpty ? r.id : r.tenancyName) : r.region
        if r.isHomeRegion { s += " · 主" }
        return s
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(spacing: 10) {
            summaryChip(icon: "server.rack", title: "本页", value: "\(model.rows.count)", accent: AppTheme.sidebarActive)
            summaryChip(icon: "play.circle.fill", title: "运行中", value: "\(model.runningCount)", accent: Color(hex: "3fb950"))
            summaryChip(icon: "stop.circle.fill", title: "已停止", value: "\(model.stoppedCount)", accent: Color(hex: "f85149"))
            if model.otherStateCount > 0 {
                summaryChip(icon: "ellipsis.circle", title: "其他", value: "\(model.otherStateCount)", accent: Color(hex: "d29922"))
            }
            Spacer(minLength: 0)
            Text("快捷：启停 · 复制IP · SSH · 更多")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark).opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
            Button("重试") { Task { await model.reload() } }
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
        if model.isLoading && model.rows.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text("加载实例…")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tableCardBackground)
        } else if model.rows.isEmpty {
            EmptyStateView(
                icon: "server.rack",
                title: "暂无实例",
                subtitle: model.hasActiveFilter
                    ? "当前筛选条件下没有实例"
                    : "可从租户同步实例，或调整筛选后查询",
                actionTitle: "刷新",
                action: { Task { await model.reload() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tableCardBackground)
        } else {
            GeometryReader { geo in
                let totalW = max(geo.size.width, fixedColsWidth)
                let flex = max(0, totalW - fixedColsWidth)
                let wName = minName + flex * 0.55
                let wIp = minIp + flex * 0.45
                let needsHScroll = totalW > geo.size.width + 0.5

                let table = VStack(spacing: 0) {
                    headerRow(wName: wName, wIp: wIp, width: totalW)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { idx, row in
                                dataRow(index: idx, item: row, wName: wName, wIp: wIp, width: totalW)
                            }
                        }
                    }
                }
                .frame(width: totalW, height: geo.size.height, alignment: .topLeading)

                Group {
                    if needsHScroll {
                        ScrollView(.horizontal, showsIndicators: true) { table }
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        table
                    }
                }
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

    private func headerRow(wName: CGFloat, wIp: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                colHeader("#", wIndex)
                colHeader("租户", wTenant)
                colHeader("区域", wRegion)
                colHeader("实例名称", wName)
                colHeader("CPU/MEM", wCpu)
                colHeader("架构", wArch)
            }
            HStack(spacing: 0) {
                colHeader("磁盘/VPU", wVol)
                colHeader("公网 IPv4", wIp)
                colHeader("IPv6", wIpv6, align: .center)
                colHeader("创建时间", wTime)
                colHeader("操作", wAction, align: .center)
            }
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

    private func dataRow(index: Int, item: InstanceItem, wName: CGFloat, wIp: CGFloat, width: CGFloat) -> some View {
        let grp = tenantGroupIndex(for: index)
        let hovered = hoveredRowId == item.id
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                cellText("\(model.pageState.page * model.pageState.size + index + 1)", wIndex, muted: true)
                tenantCell(item, width: wTenant)
                cellText(item.regionName.isEmpty ? "—" : item.regionName, wRegion)
                nameCell(item, width: wName)
                cellText(item.cpuAndMem, wCpu)
                cellText(item.architecture.isEmpty ? "—" : item.architecture, wArch)
            }
            HStack(spacing: 0) {
                cellText(item.volumeText, wVol)
                ipCell(item, width: wIp)
                ipv6Cell(item, width: wIpv6)
                cellText(item.createDateText, wTime, muted: true)
                actionBar(item)
                    .frame(width: wAction, alignment: .center)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground(group: grp, hovered: hovered))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.28)),
            alignment: .bottom
        )
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredRowId = inside ? item.id : (hoveredRowId == item.id ? nil : hoveredRowId)
            }
        }
    }

    private func rowBackground(group: Int, hovered: Bool) -> Color {
        if hovered {
            return AppTheme.sidebarActive.opacity(dark ? 0.12 : 0.08)
        }
        return group % 2 == 1
            ? Color(hex: "63b3ed").opacity(dark ? 0.05 : 0.07)
            : Color.clear
    }

    /// 同租户连续行分组（对齐 Web tgrp-a/b）
    private func tenantGroupIndex(for index: Int) -> Int {
        guard index < model.rows.count else { return 0 }
        var grp = 0
        var prev = model.rows[0].tenantId
        for i in 0...index {
            let tid = model.rows[i].tenantId
            if i > 0, tid != prev {
                grp += 1
                prev = tid
            }
        }
        return grp
    }

    // MARK: - Cells

    private func colHeader(_ title: String, _ width: CGFloat, align: Alignment = .leading) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.sidebarText(dark))
            .frame(width: width, alignment: align)
    }

    private func cellText(_ text: String, _ width: CGFloat, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(
                muted
                    ? AppTheme.sidebarText(dark)
                    : (dark ? Color.white.opacity(0.9) : Color.primary)
            )
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    private func tenantCell(_ item: InstanceItem, width: CGFloat) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { model.namesHidden.toggle() }
        }) {
            Text(model.namesHidden ? item.maskedTenancyName : (item.tenancyName.isEmpty ? "—" : item.tenancyName))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(dark ? Color.white.opacity(0.88) : Color.primary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(item.tenancyName)
    }

    private func nameCell(_ item: InstanceItem, width: CGFloat) -> some View {
        let remark = item.remark.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRemark = !remark.isEmpty && remark != "未设置" && remark != "—"
        return HStack(spacing: 6) {
            Circle()
                .fill(statusColor(item))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName.isEmpty ? "—" : item.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.stateLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(statusColor(item))
                        .lineLimit(1)
                    if hasRemark {
                        Text(remark)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.sidebarText(dark))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.openUpdateName(item)
        }
        .help(hasRemark
              ? "\(item.stateLabel) · \(item.displayName)\n备注：\(remark)\n双击修改名称"
              : "\(item.stateLabel) · \(item.displayName)\n双击修改名称")
    }

    private func statusColor(_ item: InstanceItem) -> Color {
        StatusTone.fromState(item.state).color(dark: dark)
    }

    private func ipCell(_ item: InstanceItem, width: CGFloat) -> some View {
        let priv = item.privateIps.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPriv = !priv.isEmpty && priv != "—" && priv != "-"
        return Button(action: { model.copyText(item.publicIps, label: "IPv4") }) {
            Text(item.publicIps.isEmpty ? "—" : item.publicIps)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(item.publicIps.isEmpty ? AppTheme.sidebarText(dark) : AppTheme.sidebarActive)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(
            item.publicIps.isEmpty
                ? (hasPriv ? "无公网 IP · 内网 \(priv)" : "无公网 IP")
                : (hasPriv ? "点击复制 IPv4 · 内网 \(priv)" : "点击复制 IPv4")
        )
    }

    private func ipv6Cell(_ item: InstanceItem, width: CGFloat) -> some View {
        Group {
            if item.hasIpv6 {
                Button(action: { model.copyText(item.ipv6Addresses, label: "IPv6") }) {
                    Text("已开")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "3fb950"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "3fb950").opacity(0.14)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("点击复制 IPv6：\(item.ipv6Addresses)")
            } else {
                Text("无")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
        }
        .frame(width: width, alignment: .center)
    }

    /// 行内快捷：启停 / 复制IP / SSH + 更多
    private func actionBar(_ item: InstanceItem) -> some View {
        HStack(spacing: 4) {
            if item.isStopped {
                quickIcon(systemImage: "play.fill", help: "启动", accent: true) {
                    model.confirmStart(item)
                }
            } else if item.isRunning {
                quickIcon(systemImage: "stop.fill", help: "停止", accent: false) {
                    model.confirmStop(item)
                }
            }
            quickIcon(systemImage: "doc.on.doc", help: "复制 IPv4", accent: false) {
                model.copyText(item.publicIps, label: "IPv4")
            }
            quickIcon(systemImage: "terminal", help: "SSH 连接", accent: false) {
                model.openSSH(item)
            }
            InstanceActionMoreButton(dark: dark, item: item, model: model)
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
                .font(.system(size: 11, weight: .semibold))
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
}

// MARK: - Action menu data

struct InstanceActionItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isDanger: Bool
    let action: () -> Void
}

enum InstanceActionPanel {
    /// 扁平操作列表（每行两个，无模块分区）
    static func actions(for row: InstanceItem, model: InstancesViewModel) -> [InstanceActionItem] {
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
        ) -> InstanceActionItem {
            InstanceActionItem(
                id: id, title: title, systemImage: icon,
                isDanger: danger, action: run(body)
            )
        }

        var items: [InstanceActionItem] = []
        if row.isStopped {
            items.append(make("start", "启动", "play.fill") { model.confirmStart(row) })
        } else if row.isRunning {
            items.append(make("stop", "停止", "stop.fill") { model.confirmStop(row) })
        }
        items.append(contentsOf: [
            make("remark", "修改备注", "note.text") { model.openUpdateRemark(row) },
            make("name", "修改名称", "tag") { model.openUpdateName(row) },
            make("cfg", "修改配置", "cpu") { model.openUpdateConfig(row) },
            make("boot", "扩容引导卷", "externaldrive") { model.openUpdateBoot(row) },
            make("vpu", "修改 VPU", "slider.horizontal.3") { model.openUpdateVpu(row) },
            make("copy4", "复制 IPv4", "doc.on.doc") {
                model.copyText(row.publicIps, label: "IPv4")
            },
            make("chgip", "更换 IP", "arrow.triangle.2.circlepath") {
                model.openChangeIp(row)
            }
        ])
        if row.hasIpv6 {
            items.append(make("copy6", "复制 IPv6", "doc.on.doc") {
                model.copyText(row.ipv6Addresses, label: "IPv6")
            })
            items.append(make("mg6", "管理 IPv6", "globe") {
                model.enableIpv6(row)
            })
        } else {
            items.append(make("en6", "开启 IPv6", "plus.circle") {
                model.enableIpv6(row)
            })
        }
        if !row.privateIps.isEmpty, row.privateIps != "—", row.privateIps != "-" {
            items.append(make("copypriv", "复制内网 IP", "network") {
                model.copyText(row.privateIps, label: "内网 IP")
            })
        }
        items.append(contentsOf: [
            make("ssh", "SSH 连接", "terminal") { model.openSSH(row) },
            make("console", "控制台", "tv") { model.openConsole(row) },
            make("vnic", "网络管理", "network") { model.openVnic(row) },
            make("dd", "系统重装", "arrow.counterclockwise") { model.openOsReset(row) },
            make("term", "终止实例", "xmark.octagon", danger: true) {
                model.openTerminate(row)
            },
            make("del", "删除本地记录", "trash", danger: true) {
                model.confirmDeleteRecord(row)
            }
        ])
        return items
    }
}

// MARK: - 窗内操作菜单（不使用 NSMenu/NSPopover，保证在应用窗口内）

private enum InstanceActionMenuLayout {
    static let width: CGFloat = 340
    static let vPad: CGFloat = 12
    static let titleH: CGFloat = 18
    static let gridGap: CGFloat = 8
    static let rowH: CGFloat = 36
    static let cols = 2
    static let margin: CGFloat = 10
    static let minHeight: CGFloat = 160
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

        let spaceAbove = bounds.maxY - btn.maxY
        let spaceBelow = btn.minY - bounds.minY
        var y: CGFloat

        if spaceBelow < h * 0.35 {
            y = btn.maxY + gap
            if y + h > bounds.maxY { h = max(minHeight, bounds.maxY - y) }
            if y + h > bounds.maxY { y = bounds.maxY - h }
        } else if spaceAbove < h * 0.35 {
            y = btn.minY - h - gap
            if y < bounds.minY {
                y = bounds.minY
                h = max(minHeight, min(ideal, btn.minY - gap - bounds.minY))
            }
        } else {
            y = btn.midY - h / 2
            if y < bounds.minY { y = bounds.minY }
            if y + h > bounds.maxY { y = bounds.maxY - h }
        }

        if h > bounds.height { h = bounds.height }
        if y < bounds.minY { y = bounds.minY }
        if y + h > bounds.maxY { y = bounds.maxY - h }

        return NSRect(x: x, y: y, width: width, height: h)
    }
}

/// 实例行操作菜单（窗内浮层）。
/// 注意：禁止用全窗口 ClickCatcher NSView 吞鼠标——若 dismiss 失败会整窗假死（进控制台后按钮全无响应）。
@MainActor
final class InstanceActionMenuPresenter {
    static let shared = InstanceActionMenuPresenter()

    /// 强引用直到 dismiss，避免 weak 丢失后浮层残留
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
        item: InstanceItem,
        model: InstancesViewModel,
        appearance: AppearanceController,
        dark: Bool
    ) {
        if isPresented {
            dismiss()
            return
        }
        guard let window = button.window, let content = window.contentView else { return }
        // 先清掉可能残留的浮层
        dismiss()

        let actions = InstanceActionPanel.actions(for: item, model: model)
        let frame = InstanceActionMenuLayout.panelFrame(
            button: button,
            in: content,
            itemCount: actions.count
        )

        let root = InstanceActionMenuContent(
            title: item.displayName,
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

        // Esc 关闭
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }

        // 点击菜单外关闭：只监视、不吞事件，避免挡死顶栏/侧栏/返回按钮
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let host = self.panelHost else { return event }
            let loc = event.locationInWindow
            let frameInWindow = host.convert(host.bounds, to: nil)
            if !frameInWindow.contains(loc) {
                // 异步 dismiss，让本次点击继续落到下层控件
                DispatchQueue.main.async { self.dismiss() }
            }
            return event
        }
    }
}

struct InstanceActionMenuContent: View {
    var title: String = ""
    let dark: Bool
    var panelHeight: CGFloat = 420
    let actions: [InstanceActionItem]
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }

            ScrollView {
                // 扁平两列，无分区标题
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(actions) { act in
                        actionButton(act)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: InstanceActionMenuLayout.width, height: panelHeight, alignment: .topLeading)
        .background(AppTheme.pageBg(dark))
        .cornerRadius(12)
    }

    private func actionButton(_ act: InstanceActionItem) -> some View {
        let hovered = hoveredId == act.id
        return Button(action: {
            // 先关浮层再执行业务，避免 catcher/浮层残留挡死下一页
            let run = act.action
            onDismiss()
            DispatchQueue.main.async {
                run()
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
            .foregroundColor(
                act.isDanger
                    ? Color(hex: "f85149")
                    : (dark ? Color.white.opacity(0.92) : Color.primary)
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

    private func buttonFill(act: InstanceActionItem, hovered: Bool) -> Color {
        if hovered {
            if act.isDanger {
                return Color(hex: "f85149").opacity(dark ? 0.22 : 0.16)
            }
            return AppTheme.sidebarActive.opacity(dark ? 0.22 : 0.14)
        }
        // 默认轻底，悬停时明显高亮
        if act.isDanger {
            return Color(hex: "f85149").opacity(0.06)
        }
        return dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }
}

private struct InstanceActionMoreButton: NSViewRepresentable {
    let dark: Bool
    let item: InstanceItem
    @ObservedObject var model: InstancesViewModel
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
        var item: InstanceItem
        var model: InstancesViewModel
        var appearance: AppearanceController
        var dark: Bool

        init(item: InstanceItem, model: InstancesViewModel, appearance: AppearanceController, dark: Bool) {
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
                InstanceActionMenuPresenter.shared.toggle(
                    from: btn, item: it, model: m, appearance: ap, dark: d
                )
            }
        }
    }
}
