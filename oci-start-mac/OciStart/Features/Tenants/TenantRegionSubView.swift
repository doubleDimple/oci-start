import SwiftUI
import AppKit

/// 区域订阅整页 — 对应 Web `/tenants/region_sub`，从租户列表操作菜单进入，非弹框。
struct TenantRegionSubView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var tenant: TenantItem? { model.regionSubParent }

    private var primaryText: Color { dark ? Color.white.opacity(0.9) : Color.primary }
    private var mutedText: Color { AppTheme.sidebarText(dark) }
    private var panelBg: Color { dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03) }
    private var border: Color { AppTheme.border(dark) }

    var body: some View {
        PageScaffold(
            title: "区域订阅",
            subtitle: tenant.map { "\($0.displayName) · \($0.region.isEmpty ? "—" : $0.region)" },
            systemImage: "globe",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    summaryBar
                    tabBar
                    tabContent
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
                model.closeRegionSub()
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                guard let t = tenant else { return }
                Task { await model.refreshRegionSub(t) }
            }
            if model.regionSubTab == 1 {
                AppButton(title: "全选", systemImage: "checkmark.square", kind: .secondary) {
                    let allKeys = Set(model.unsubscribedRegions.map { $0.key })
                    if model.selectedUnsubKeys == allKeys {
                        model.selectedUnsubKeys = []
                    } else {
                        model.selectedUnsubKeys = allKeys
                    }
                }
                AppButton(
                    title: model.selectedUnsubKeys.isEmpty ? "订阅所选" : "订阅所选（\(model.selectedUnsubKeys.count)）",
                    kind: .primary
                ) {
                    guard let t = tenant else { return }
                    model.subscribeSelected(t)
                }
            }
        }
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack(spacing: 12) {
            statCard(label: "全部区域", value: model.regionSubLoading ? "—" : "\(model.regionTotalCount)", accent: false)
            statCard(label: "已订阅", value: model.regionSubLoading ? "—" : "\(model.regionSubscribedCount)", accent: true)
            statCard(label: "未订阅", value: model.regionSubLoading ? "—" : "\(model.regionUnsubscribedCount)", accent: false)
            Spacer()
            if model.regionSubLoading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("加载中…").font(.system(size: 12)).foregroundColor(mutedText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(panelBg)
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.4)), alignment: .bottom)
    }

    private func statCard(label: String, value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(accent ? AppTheme.sidebarActive : primaryText)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(mutedText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        .cornerRadius(6)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem(title: "已订阅", index: 0)
            tabItem(title: "未订阅", index: 1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .background(dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.3)), alignment: .bottom)
    }

    private func tabItem(title: String, index: Int) -> some View {
        let active = model.regionSubTab == index
        return Button(action: { model.regionSubTab = index }) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundColor(active ? AppTheme.sidebarActive : mutedText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Rectangle()
                    .fill(active ? AppTheme.sidebarActive : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        if model.regionSubTab == 0 {
            subscribedContent
        } else {
            unsubscribedContent
        }
    }

    // MARK: - 已订阅 tab

    private var subscribedContent: some View {
        Group {
            if model.regionSubLoading && model.subscribedRegions.isEmpty {
                loadingPlaceholder("加载区域订阅…")
            } else if model.subscribedRegions.isEmpty {
                EmptyStateView(
                    icon: "globe.badge.chevron.backward",
                    title: "暂无已订阅区域",
                    subtitle: "切换到「未订阅」标签页添加新区域",
                    actionTitle: "去订阅",
                    action: { model.regionSubTab = 1 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let wHome: CGFloat = 80
                    let wStatus: CGFloat = 96
                    let wKey: CGFloat = 180
                    let hPad: CGFloat = 16
                    let fixed = wHome + wStatus + wKey + hPad * 2
                    let totalW = max(geo.size.width, fixed + 160)
                    let wName = max(160, totalW - fixed)

                    VStack(spacing: 0) {
                        subscribedHeader(wName: wName, wKey: wKey, wHome: wHome, wStatus: wStatus, width: totalW, hPad: hPad)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(model.subscribedRegions.enumerated()), id: \.element.id) { idx, r in
                                    subscribedRow(index: idx, r: r, wName: wName, wKey: wKey, wHome: wHome, wStatus: wStatus, width: totalW, hPad: hPad)
                                }
                            }
                        }
                    }
                    .frame(width: totalW, height: geo.size.height, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func subscribedHeader(wName: CGFloat, wKey: CGFloat, wHome: CGFloat, wStatus: CGFloat, width: CGFloat, hPad: CGFloat) -> some View {
        HStack(spacing: 0) {
            colHeader("区域名称", wName)
            colHeader("区域标识", wKey)
            colHeader("主区域", wHome)
            colHeader("状态", wStatus)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.5)), alignment: .bottom)
    }

    private func subscribedRow(index: Int, r: TenantSubscribedRegion, wName: CGFloat, wKey: CGFloat, wHome: CGFloat, wStatus: CGFloat, width: CGFloat, hPad: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(r.regionName.isEmpty ? r.regionKey : r.regionName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(primaryText)
                .lineLimit(1)
                .frame(width: wName, alignment: .leading)
            Text(r.regionKey)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarActive)
                .lineLimit(1)
                .frame(width: wKey, alignment: .leading)
            homeBadge(r.isHomeRegion)
                .frame(width: wHome, alignment: .leading)
            statusBadge(r.status)
                .frame(width: wStatus, alignment: .leading)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(index % 2 == 1 ? AppTheme.sidebarHover(dark).opacity(0.18) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.3)), alignment: .bottom)
    }

    private func homeBadge(_ isHome: Bool) -> some View {
        Text(isHome ? "主区域" : "—")
            .font(.system(size: 11, weight: isHome ? .semibold : .regular))
            .foregroundColor(isHome ? AppTheme.sidebarActive : mutedText)
            .padding(.horizontal, isHome ? 8 : 0)
            .padding(.vertical, isHome ? 3 : 0)
            .background(isHome ? Capsule().fill(AppTheme.sidebarActive.opacity(0.12)) : nil)
    }

    private func statusBadge(_ status: String) -> some View {
        let tone: StatusTone = {
            switch status.uppercased() {
            case "READY": return .success
            case "PENDING": return .warning
            case "FAILED": return .danger
            default: return .neutral
            }
        }()
        return StatusBadge(text: status.isEmpty ? "—" : status, tone: tone)
    }

    // MARK: - 未订阅 tab

    private var unsubscribedContent: some View {
        Group {
            if model.regionSubLoading && model.unsubscribedRegions.isEmpty {
                loadingPlaceholder("加载可订阅区域…")
            } else if model.unsubscribedRegions.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "已订阅全部区域",
                    subtitle: "当前租户已订阅所有可用区域",
                    actionTitle: "查看已订阅",
                    action: { model.regionSubTab = 0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                unsubscribedList
            }
        }
    }

    private var unsubscribedList: some View {
        GeometryReader { geo in
            let hPad: CGFloat = 16
            let totalW = max(geo.size.width, 400)

            VStack(spacing: 0) {
                unsubscribedHeader(width: totalW, hPad: hPad)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.unsubscribedRegions.enumerated()), id: \.element.id) { idx, r in
                            unsubscribedRow(index: idx, r: r, width: totalW, hPad: hPad)
                        }
                    }
                }
            }
            .frame(width: totalW, height: geo.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unsubscribedHeader(width: CGFloat, hPad: CGFloat) -> some View {
        let allKeys = Set(model.unsubscribedRegions.map { $0.key })
        let allSelected = !allKeys.isEmpty && model.selectedUnsubKeys == allKeys
        return HStack(spacing: 10) {
            Button(action: {
                model.selectedUnsubKeys = allSelected ? [] : allKeys
            }) {
                Image(systemName: allSelected ? "checkmark.square.fill" : (model.selectedUnsubKeys.isEmpty ? "square" : "minus.square.fill"))
                    .foregroundColor(AppTheme.sidebarActive)
            }
            .buttonStyle(PlainButtonStyle())
            colHeader("区域", nil)
            Spacer()
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.5)), alignment: .bottom)
    }

    private func unsubscribedRow(index: Int, r: TenantUnsubscribedRegion, width: CGFloat, hPad: CGFloat) -> some View {
        let selected = model.selectedUnsubKeys.contains(r.key)
        return Button(action: { model.toggleUnsubKey(r.key) }) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundColor(AppTheme.sidebarActive)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.cnName.isEmpty ? r.name : r.cnName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(primaryText)
                    Text("\(r.key)  ·  \(r.name)")
                        .font(.system(size: 11))
                        .foregroundColor(mutedText)
                }
                Spacer()
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, 10)
            .frame(width: width, alignment: .leading)
            .background(selected ? AppTheme.sidebarActive.opacity(0.07) : (index % 2 == 1 ? AppTheme.sidebarHover(dark).opacity(0.18) : Color.clear))
            .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.3)), alignment: .bottom)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helpers

    private func loadingPlaceholder(_ text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
            Text(text).font(.system(size: 12)).foregroundColor(mutedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func colHeader(_ title: String, _ w: CGFloat?) -> some View {
        let view = Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(mutedText)
        if let w = w {
            return AnyView(view.frame(width: w, alignment: .leading))
        }
        return AnyView(view)
    }
}
