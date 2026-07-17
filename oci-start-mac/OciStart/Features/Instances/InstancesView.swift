import SwiftUI
import AppKit

/// 原生实例列表（对齐 Web `/oci/list` · `oci_machine_list.ftl`）。
struct InstancesView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = InstancesViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    // 固定列宽；名称/IP 分剩余宽度
    private let wIndex: CGFloat = 40
    private let wTenant: CGFloat = 110
    private let wRegion: CGFloat = 100
    private let wCpu: CGFloat = 64
    private let wArch: CGFloat = 72
    private let wVol: CGFloat = 88
    private let wIpv6: CGFloat = 52
    private let wTime: CGFloat = 96
    private let wAction: CGFloat = 48
    private let hPad: CGFloat = 12
    private let minName: CGFloat = 120
    private let minIp: CGFloat = 100

    private var fixedColsWidth: CGFloat {
        wIndex + wTenant + wRegion + wCpu + wArch + wVol + wIpv6 + wTime + wAction
            + minName + minIp + hPad * 2
    }

    var body: some View {
        PageScaffold(
            title: "实例列表",
            subtitle: "OCI 实例管理",
            systemImage: "server.rack",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    filterBar
                    if let err = model.errorText, !err.isEmpty { errorBanner(err) }
                    listBody
                    PaginationBar(state: $model.pageState) {
                        model.onPageChange()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.isLoading)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reload() }
        }
        .sheet(item: $model.activeSheet) { sheet in
            InstanceSheetHost(sheet: sheet, model: model)
                .environmentObject(appearance)
                .environmentObject(session)
        }
        .environmentObject(appearance)
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
            AppButton(title: "导出", systemImage: "square.and.arrow.down", kind: .secondary) {
                model.exportInstances()
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
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
                        allowClear: true
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
                        allowClear: true
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

    private func parentLabel(_ t: TenantRegionOption) -> String {
        if !t.tenancyName.isEmpty { return t.tenancyName }
        if !t.userName.isEmpty { return t.userName }
        return t.id
    }

    private func regionLabel(_ r: TenantRegionOption) -> String {
        var s = r.region.isEmpty ? (r.tenancyName.isEmpty ? r.id : r.tenancyName) : r.region
        if r.isHomeRegion { s += " · 主" }
        return s
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reload() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
    }

    // MARK: - Table

    @ViewBuilder
    private var listBody: some View {
        if model.rows.isEmpty && !model.isLoading {
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
        } else {
            GeometryReader { geo in
                let totalW = max(geo.size.width, fixedColsWidth)
                let flex = max(0, totalW - fixedColsWidth)
                let wName = minName + flex * 0.55
                let wIp = minIp + flex * 0.45

                VStack(spacing: 0) {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headerRow(wName: CGFloat, wIp: CGFloat, width: CGFloat) -> some View {
        // ViewBuilder 最多 10 个子视图，拆成两组（对齐 TenantsView）
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
                colHeader("IPv6", wIpv6)
                colHeader("创建时间", wTime)
                colHeader("操作", wAction)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .bottom
        )
    }

    private func dataRow(index: Int, item: InstanceItem, wName: CGFloat, wIp: CGFloat, width: CGFloat) -> some View {
        let grp = tenantGroupIndex(for: index)
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
                cellText(item.publicIps.isEmpty ? "—" : item.publicIps, wIp)
                ipv6Cell(item, width: wIpv6)
                cellText(item.createDateText, wTime, muted: true)
                actionCell(item, width: wAction)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.3)),
            alignment: .bottom
        )
        .background(
            grp % 2 == 1
                ? Color(hex: "63b3ed").opacity(dark ? 0.05 : 0.07)
                : Color.clear
        )
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

    private func colHeader(_ title: String, _ width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.sidebarText(dark))
            .frame(width: width, alignment: .leading)
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
        Button(action: { model.namesHidden.toggle() }) {
            Text(model.namesHidden ? item.maskedTenancyName : (item.tenancyName.isEmpty ? "—" : item.tenancyName))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(dark ? Color.white.opacity(0.88) : Color.primary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .help(item.tenancyName)
    }

    private func nameCell(_ item: InstanceItem, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(item))
                .frame(width: 7, height: 7)
            Text(item.displayName.isEmpty ? "—" : item.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .help("\(item.stateLabel) · \(item.displayName)")
    }

    private func statusColor(_ item: InstanceItem) -> Color {
        switch item.stateLower {
        case "running": return Color(hex: "3fb950")
        case "stopped": return Color(hex: "f85149")
        case "starting", "stopping": return Color(hex: "d29922")
        case "terminated", "terminating": return Color(hex: "8b949e")
        default: return Color(hex: "8b949e")
        }
    }

    private func ipv6Cell(_ item: InstanceItem, width: CGFloat) -> some View {
        Group {
            if item.hasIpv6 {
                Text("已开")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "3fb950"))
            } else {
                Text("无")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
        }
        .frame(width: width, alignment: .center)
    }

    private func actionCell(_ item: InstanceItem, width: CGFloat) -> some View {
        InstanceEllipsisButton(dark: dark, item: item, model: model)
            .frame(width: width, height: 26)
    }
}

// MARK: - Action menu (NSMenu)

struct InstanceActionItem {
    let title: String
    let isDanger: Bool
    let action: () -> Void
}

enum InstanceActionPanel {
    /// 菜单动作通过 `Task { @MainActor in }` 派发，兼容 Swift 5.5 / Xcode 13。
    static func actions(for item: InstanceItem, model: InstancesViewModel) -> [InstanceActionItem] {
        func run(_ body: @escaping @MainActor () -> Void) -> () -> Void {
            return {
                Task { @MainActor in
                    body()
                }
            }
        }
        var list: [InstanceActionItem] = []
        if item.isStopped {
            list.append(InstanceActionItem(title: "启动", isDanger: false, action: run { model.confirmStart(item) }))
        } else if item.isRunning {
            list.append(InstanceActionItem(title: "停止", isDanger: false, action: run { model.confirmStop(item) }))
        }
        list.append(contentsOf: [
            InstanceActionItem(title: "终止实例", isDanger: true, action: run { model.openTerminate(item) }),
            InstanceActionItem(title: "修改备注", isDanger: false, action: run { model.openUpdateRemark(item) }),
            InstanceActionItem(title: "修改名称", isDanger: false, action: run { model.openUpdateName(item) }),
            InstanceActionItem(title: "修改配置", isDanger: false, action: run { model.openUpdateConfig(item) }),
            InstanceActionItem(title: "扩容引导卷", isDanger: false, action: run { model.openUpdateBoot(item) }),
            InstanceActionItem(title: "修改 VPU", isDanger: false, action: run { model.openUpdateVpu(item) }),
            InstanceActionItem(title: "复制 IPv4", isDanger: false, action: run { model.copyText(item.publicIps, label: "IPv4") }),
            InstanceActionItem(title: "更换 IP", isDanger: false, action: run { model.openChangeIp(item) })
        ])
        if item.hasIpv6 {
            list.append(InstanceActionItem(title: "复制 IPv6", isDanger: false, action: run {
                model.copyText(item.ipv6Addresses, label: "IPv6")
            }))
            list.append(InstanceActionItem(title: "管理 IPv6", isDanger: false, action: run {
                model.enableIpv6(item)
            }))
        } else {
            list.append(InstanceActionItem(title: "开启 IPv6", isDanger: false, action: run {
                model.enableIpv6(item)
            }))
        }
        list.append(contentsOf: [
            InstanceActionItem(title: "SSH 连接", isDanger: false, action: run { model.openSSH(item) }),
            InstanceActionItem(title: "控制台", isDanger: false, action: run { model.openConsole(item) }),
            InstanceActionItem(title: "网络管理", isDanger: false, action: run { model.openVnic(item) }),
            InstanceActionItem(title: "删除本地记录", isDanger: true, action: run { model.confirmDeleteRecord(item) })
        ])
        return list
    }
}

private struct InstanceEllipsisButton: NSViewRepresentable {
    let dark: Bool
    let item: InstanceItem
    @ObservedObject var model: InstancesViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item, model: model)
    }

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        b.bezelStyle = .rounded
        b.isBordered = true
        b.title = "···"
        b.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        b.target = context.coordinator
        b.action = #selector(Coordinator.showMenu(_:))
        b.setButtonType(.momentaryPushIn)
        context.coordinator.button = b
        return b
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.item = item
        context.coordinator.model = model
    }

    final class Coordinator: NSObject {
        var item: InstanceItem
        var model: InstancesViewModel
        weak var button: NSButton?
        private var handlers: [Int: () -> Void] = [:]

        init(item: InstanceItem, model: InstancesViewModel) {
            self.item = item
            self.model = model
        }

        @objc func showMenu(_ sender: NSButton) {
            let actions = InstanceActionPanel.actions(for: item, model: model)
            let menu = NSMenu()
            handlers.removeAll()
            for (idx, act) in actions.enumerated() {
                let mi = NSMenuItem(
                    title: act.title,
                    action: #selector(runAction(_:)),
                    keyEquivalent: ""
                )
                mi.target = self
                mi.tag = idx
                if act.isDanger {
                    mi.attributedTitle = NSAttributedString(
                        string: act.title,
                        attributes: [
                            .foregroundColor: NSColor.systemRed,
                            .font: NSFont.menuFont(ofSize: 0)
                        ]
                    )
                }
                handlers[idx] = act.action
                menu.addItem(mi)
                // 分隔：终止后、删除前
                if act.title == "终止实例" || act.title == "网络管理" {
                    menu.addItem(NSMenuItem.separator())
                }
            }
            let pt = NSPoint(x: 0, y: sender.bounds.height + 2)
            menu.popUp(positioning: nil, at: pt, in: sender)
        }

        @objc func runAction(_ sender: NSMenuItem) {
            handlers[sender.tag]?()
        }
    }
}
