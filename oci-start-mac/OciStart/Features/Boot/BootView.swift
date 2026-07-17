import SwiftUI
import AppKit

/// 原生开机管理（对齐 Web `/boot/fullBootList` · `full_machine_list.ftl`）。
struct BootView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = BootViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    private let wIndex: CGFloat = 40
    private let wTenant: CGFloat = 120
    private let wRemark: CGFloat = 90
    private let wRegion: CGFloat = 90
    private let wStatus: CGFloat = 72
    private let wNum: CGFloat = 56
    private let wArch: CGFloat = 56
    private let wTime: CGFloat = 100
    private let wAction: CGFloat = 48
    private let hPad: CGFloat = 12

    var body: some View {
        PageScaffold(
            title: "开机管理",
            subtitle: "抢机任务列表 · 启停 / 详情 / 批量操作",
            systemImage: "play.circle",
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
            BootSheetHost(sheet: sheet, model: model)
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
            AppButton(title: "批量启动", systemImage: "play.circle", kind: .primary) {
                model.batchStart()
            }
            AppButton(title: "批量停止", systemImage: "stop.circle", kind: .secondary) {
                model.batchStop()
            }
            AppButton(title: "重置失败", systemImage: "arrow.counterclockwise", kind: .secondary) {
                model.batchResetFail()
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
                        options: model.parentTenants.map {
                            SelectOption(id: $0.id, title: model.tenantLabel($0))
                        },
                        selection: Binding(
                            get: { model.selectedParentId.isEmpty ? nil : model.selectedParentId },
                            set: { model.onParentChanged($0) }
                        ),
                        placeholder: "选择租户…",
                        width: 200,
                        allowClear: true
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
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - List

    private var listBody: some View {
        Group {
            if model.rows.isEmpty && !model.isLoading {
                EmptyStateView(
                    icon: "play.circle",
                    title: "暂无开机任务",
                    subtitle: "可在租户管理中创建抢机配置"
                )
            } else {
                GeometryReader { geo in
                    let flex = max(0, geo.size.width - fixedWidth)
                    ScrollView([.vertical, .horizontal]) {
                        VStack(spacing: 0) {
                            headerRow(flex: flex)
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { idx, item in
                                dataRow(index: idx, item: item, flex: flex)
                                Divider().opacity(0.25)
                            }
                        }
                        .frame(minWidth: max(geo.size.width, fixedWidth + 200))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fixedWidth: CGFloat {
        wIndex + wTenant + wRemark + wRegion + wStatus
            + wNum * 7 + wArch + wTime + wAction + hPad * 2 + 20
    }

    private func headerRow(flex: CGFloat) -> some View {
        HStack(spacing: 0) {
            Group {
                h("№", wIndex)
                h("租户", wTenant + flex * 0.35)
                h("备注", wRemark + flex * 0.25)
                h("区域", wRegion + flex * 0.2)
                h("状态", wStatus)
            }
            Group {
                h("任务数", wNum)
                h("执行中", wNum)
                h("总次数", wNum)
                h("昨日", wNum)
                h("今日", wNum)
            }
            Group {
                h("失败", wNum)
                h("成功", wNum)
                h("架构", wArch)
                h("创建时间", wTime + flex * 0.2)
                h("", wAction)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarBg(dark).opacity(0.65))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .bottom
        )
    }

    private func h(_ t: String, _ w: CGFloat) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.sidebarText(dark))
            .frame(width: w, alignment: .leading)
    }

    private func dataRow(index: Int, item: BootTaskItem, flex: CGFloat) -> some View {
        HStack(spacing: 0) {
            Group {
                cell("\(index + 1 + model.pageState.page * model.pageState.size)", wIndex)
                cell(model.namesHidden ? item.maskedTenant : item.displayTenant, wTenant + flex * 0.35, bold: true)
                cell(item.remarkText, wRemark + flex * 0.25)
                cell(item.regionName.isEmpty ? "—" : item.regionName, wRegion + flex * 0.2)
                StatusBadge(text: item.taskStatusText, tone: item.taskStatusTone)
                    .frame(width: wStatus, alignment: .leading)
            }
            Group {
                cell("\(item.recordCount)", wNum)
                cell("\(item.executingCount)", wNum)
                cell(formatNum(item.totalCount), wNum)
                cell(formatNum(Int64(item.yesterdayAttemptCount)), wNum)
                cell(formatNum(Int64(item.currentAttemptCount)), wNum)
            }
            Group {
                cell(formatNum(Int64(item.failCount)), wNum)
                cell(formatNum(Int64(item.successCount)), wNum)
                cell(item.archText, wArch)
                cell(item.createText, wTime + flex * 0.2)
                BootEllipsisButton(dark: dark, item: item, model: model)
                    .frame(width: wAction, height: 26)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 8)
        .background(index % 2 == 0 ? Color.clear : AppTheme.pageBg(dark).opacity(0.35))
    }

    private func cell(_ t: String, _ w: CGFloat, bold: Bool = false) -> some View {
        Text(t)
            .font(.system(size: 12, weight: bold ? .semibold : .regular))
            .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
            .lineLimit(1)
            .frame(width: w, alignment: .leading)
            .help(t)
    }

    private func formatNum(_ n: Int64) -> String {
        if n >= 10_000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            return f.string(from: NSNumber(value: n)) ?? "\(n)"
        }
        return "\(n)"
    }
}

// MARK: - Row action menu

struct BootActionItem {
    let title: String
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
        return [
            BootActionItem(title: "克隆开机", isDanger: false, action: run { model.confirmClone(item) }),
            BootActionItem(title: "启动", isDanger: false, action: run { model.confirmStart(item) }),
            BootActionItem(title: "停止", isDanger: false, action: run { model.confirmStop(item) }),
            BootActionItem(title: "开机详情", isDanger: false, action: run { model.openDetail(item) }),
            BootActionItem(title: "添加抢机配置", isDanger: false, action: run { model.openAddConfig(item) }),
            BootActionItem(title: "手动抢机", isDanger: false, action: run { model.confirmManual(item) }),
            BootActionItem(title: "删除", isDanger: true, action: run { model.confirmDelete(item) })
        ]
    }
}

private struct BootEllipsisButton: NSViewRepresentable {
    let dark: Bool
    let item: BootTaskItem
    @ObservedObject var model: BootViewModel

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
        var item: BootTaskItem
        var model: BootViewModel
        weak var button: NSButton?
        private var handlers: [Int: () -> Void] = [:]

        init(item: BootTaskItem, model: BootViewModel) {
            self.item = item
            self.model = model
        }

        @objc func showMenu(_ sender: NSButton) {
            let actions = BootActionPanel.actions(for: item, model: model)
            let menu = NSMenu()
            handlers.removeAll()
            for (idx, act) in actions.enumerated() {
                let mi = NSMenuItem(title: act.title, action: #selector(runAction(_:)), keyEquivalent: "")
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
                if act.title == "开机详情" || act.title == "手动抢机" {
                    menu.addItem(NSMenuItem.separator())
                }
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
        }

        @objc func runAction(_ sender: NSMenuItem) {
            handlers[sender.tag]?()
        }
    }
}
