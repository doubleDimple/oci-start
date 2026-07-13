import SwiftUI
import AppKit

/// Web 整页「租户详情」`/tenants/regionList` → `tenant_region_list.ftl`
/// 从租户列表进入，非弹框。
struct TenantDetailView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession

    private var dark: Bool { appearance.isDarkEffective }
    private var parent: TenantItem? { model.detailParent }

    // 列宽
    private let wIndex: CGFloat = 44
    private let wTask: CGFloat = 72
    private let wRegion: CGFloat = 100
    private let wHome: CGFloat = 72
    private let wSync: CGFloat = 72
    private let wTime: CGFloat = 140
    private let wAction: CGFloat = 52
    private let minName: CGFloat = 120
    private let minDef: CGFloat = 100
    private let hPad: CGFloat = 12

    var body: some View {
        PageScaffold(
            title: "租户详情",
            subtitle: parent.map { "\($0.displayName) · \($0.region.isEmpty ? "—" : $0.region)" },
            systemImage: "key.fill",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.detailError, !err.isEmpty {
                        errorBanner(err)
                    }
                    listBody
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
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
                model.detailNamesHidden.toggle()
            }
            AppButton(title: "API 导入", systemImage: "bolt.fill", kind: .primary) {
                model.openAdd()
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                Task { await model.reloadDetail() }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reloadDetail() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
    }

    // MARK: - Table

    @ViewBuilder
    private var listBody: some View {
        if model.detailLoading && model.detailRows.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Text("加载区域列表…")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.detailRows.isEmpty {
            EmptyStateView(
                icon: "globe",
                title: "暂无区域",
                subtitle: "该租户下没有可展示的区域",
                actionTitle: "返回",
                action: { model.closeDetail() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.detailRows.enumerated()), id: \.element.id) { idx, row in
                                dataRow(index: idx, item: row, wName: wName, wDef: wDef, width: totalW)
                            }
                        }
                    }
                }
                .frame(width: totalW, height: geo.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .bottom
        )
    }

    private func dataRow(index: Int, item: TenantItem, wName: CGFloat, wDef: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            cell("\(index + 1)", wIndex, muted: true)
            nameCell(item, width: wName)
            cell(item.defNameText, wDef)
            StatusBadge(text: item.openTaskText, tone: item.openBootFlag ? .success : .neutral)
                .frame(width: wTask, alignment: .leading)
            regionCell(item, width: wRegion)
            homeBadge(item)
                .frame(width: wHome, alignment: .leading)
            StatusBadge(text: item.isActive ? "已同步" : "未同步", tone: item.isActive ? .success : .danger)
                .frame(width: wSync, alignment: .leading)
            cell(item.createdAt.isEmpty ? "—" : item.createdAt, wTime, muted: true)
            actionCell(item)
                .frame(width: wAction, height: 28)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(index % 2 == 1 ? AppTheme.sidebarHover(dark).opacity(0.18) : Color.clear)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.3)),
            alignment: .bottom
        )
    }

    private func nameCell(_ item: TenantItem, width: CGFloat) -> some View {
        Button(action: { model.detailNamesHidden.toggle() }) {
            Text(model.detailNamesHidden ? item.maskedName : item.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func regionCell(_ item: TenantItem, width: CGFloat) -> some View {
        Text(item.region.isEmpty ? "—" : item.region)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(AppTheme.sidebarActive)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .help("实例列表（对应 Web /oci/list?tenantId=）")
            .onTapGesture {
                // 实例列表尚未原生化：提示
                ToastCenter.shared.error("请从侧栏「实例列表」查看，或等待该页原生化")
            }
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

    private func actionCell(_ item: TenantItem) -> some View {
        TenantDetailActionButton(dark: dark, item: item, model: model)
            .environmentObject(appearance)
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

// MARK: - 详情页行操作（对齐 Web dropdown：同步/开机/引导卷/规则/实例/MySQL/AI）

private struct TenantDetailActionButton: NSViewRepresentable {
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
        b.action = #selector(Coordinator.toggle(_:))
        b.setButtonType(.momentaryPushIn)
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
