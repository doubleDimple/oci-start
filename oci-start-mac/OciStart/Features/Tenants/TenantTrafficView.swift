import SwiftUI

/// Web 整页「流量查询」`/m/traffic` → `mobile/traffic.ftl`
struct TenantTrafficView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var tenant: TenantItem? { model.trafficParent }

    // Column widths
    private let wIndex: CGFloat = 32
    private let wState: CGFloat = 76
    private let wRegion: CGFloat = 130
    private let wIP: CGFloat = 108
    private let wIn: CGFloat = 90
    private let wOut: CGFloat = 90
    private let wTotal: CGFloat = 90
    private let minName: CGFloat = 120
    private let hPad: CGFloat = 12

    var body: some View {
        PageScaffold(
            title: "流量查询",
            subtitle: tenant.map { "\($0.displayName)" },
            systemImage: "chart.bar",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    filterBar
                    if !model.tqRows.isEmpty {
                        statsRow
                    }
                    GeometryReader { geo in
                        let fixed = wIndex + wState + wRegion + wIP + wIn + wOut + wTotal + minName + hPad * 2
                        let totalW = max(geo.size.width, fixed)
                        let wName = minName + max(0, totalW - fixed)

                        VStack(spacing: 0) {
                            headerRow(wName: wName, width: totalW)
                            listBody(wName: wName, width: totalW)
                        }
                        .frame(width: totalW, height: geo.size.height, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "返回", systemImage: "chevron.left", kind: .secondary) {
                model.closeTrafficPage()
            }
            AppButton(title: "查询", systemImage: "magnifyingglass", kind: .primary) {
                guard let t = tenant else { return }
                Task { await model.queryTraffic(t) }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("开始日期").font(.system(size: 10)).foregroundColor(mutedText)
                AppTextField(text: $model.tqStart, placeholder: "yyyy-MM-dd")
                    .frame(width: 118)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("结束日期").font(.system(size: 10)).foregroundColor(mutedText)
                AppTextField(text: $model.tqEnd, placeholder: "yyyy-MM-dd")
                    .frame(width: 118)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("统计粒度").font(.system(size: 10)).foregroundColor(mutedText)
                HStack(spacing: 4) {
                    periodBtn("日", value: "1d")
                    periodBtn("小时", value: "1h")
                    periodBtn("5分钟", value: "5m")
                }
            }
            Spacer()
            HStack(spacing: 6) {
                presetBtn("近7天") { applyPreset(days: -7) }
                presetBtn("本月") { applyMonthPreset() }
                presetBtn("近30天") { applyPreset(days: -30) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.sidebarBg(dark).opacity(0.25))
        .overlay(Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.4)), alignment: .bottom)
    }

    private func periodBtn(_ label: String, value: String) -> some View {
        let active = model.tqPeriod == value
        return Button(action: { model.tqPeriod = value }) {
            Text(label)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .white : mutedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? AppTheme.sidebarActive : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(active ? AppTheme.sidebarActive : AppTheme.border(dark), lineWidth: 1)
                )
                .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func presetBtn(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(mutedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(AppTheme.border(dark), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Stats Summary

    private var statsRow: some View {
        let totalBytes = model.tqRows.reduce(0.0) { $0 + $1.totalBytes }
        let inBytes = model.tqRows.reduce(0.0) { $0 + $1.ingressBytes }
        let outBytes = model.tqRows.reduce(0.0) { $0 + $1.egressBytes }
        return HStack(spacing: 0) {
            statCard(icon: "server.rack", label: "实例数",
                     value: "\(model.tqRows.count)", color: AppTheme.sidebarActive)
            Divider().frame(height: 36)
            statCard(icon: "chart.bar.fill", label: "总流量",
                     value: formatBytes(totalBytes), color: AppTheme.sidebarActive)
            Divider().frame(height: 36)
            statCard(icon: "arrow.down.circle.fill", label: "入站",
                     value: formatBytes(inBytes), color: Color(hex: "43b581"))
            Divider().frame(height: 36)
            statCard(icon: "arrow.up.circle.fill", label: "出站",
                     value: formatBytes(outBytes), color: Color(hex: "f04747"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarBg(dark).opacity(0.18))
        .overlay(Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.4)), alignment: .bottom)
    }

    private func statCard(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Table

    private func headerRow(wName: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            colHeader("#", wIndex, align: .center)
            colHeader("实例名称", wName)
            colHeader("区域", wRegion)
            colHeader("IP 地址", wIP)
            colHeader("状态", wState)
            colHeader("入站", wIn, align: .trailing)
            colHeader("出站", wOut, align: .trailing)
            colHeader("总流量", wTotal, align: .trailing)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.5)), alignment: .bottom)
    }

    @ViewBuilder
    private func listBody(wName: CGFloat, width: CGFloat) -> some View {
        if model.tqRows.isEmpty {
            EmptyStateView(
                icon: "chart.bar",
                title: "暂无流量数据",
                subtitle: "调整查询条件后点击「查询」",
                actionTitle: nil,
                action: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let sorted = model.tqRows.sorted { $0.totalBytes > $1.totalBytes }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, row in
                        dataRow(index: idx, row: row, wName: wName, width: width)
                    }
                }
            }
        }
    }

    private func dataRow(index: Int, row: TenantTrafficRow, wName: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            cell("\(index + 1)", wIndex, align: .center, muted: true)
            cell(row.title, wName)
            cell(row.region.isEmpty ? "—" : row.region, wRegion, muted: true)
            cell(row.publicIp.isEmpty ? "—" : row.publicIp, wIP, muted: true)
            stateBadge(row.state)
                .frame(width: wState, alignment: .leading)
            trafficCell(formatBytes(row.ingressBytes), color: Color(hex: "43b581"))
                .frame(width: wIn, alignment: .trailing)
            trafficCell(formatBytes(row.egressBytes), color: Color(hex: "f04747"))
                .frame(width: wOut, alignment: .trailing)
            trafficCell(formatBytes(row.totalBytes), color: AppTheme.sidebarActive)
                .frame(width: wTotal, alignment: .trailing)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(index % 2 == 1 ? AppTheme.sidebarHover(dark).opacity(0.18) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.3)), alignment: .bottom)
    }

    private func stateBadge(_ state: String) -> some View {
        let tone: StatusTone = {
            switch state.uppercased() {
            case "RUNNING": return .success
            case "STOPPED": return .neutral
            default: return state.isEmpty ? .neutral : .warning
            }
        }()
        let label = state.isEmpty ? "—" : state.capitalized
        return StatusBadge(text: label, tone: tone)
    }

    private func trafficCell(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
            .lineLimit(1)
    }

    // MARK: - Helpers

    private var mutedText: Color { AppTheme.sidebarText(dark) }

    private func colHeader(_ title: String, _ w: CGFloat, align: Alignment = .leading) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.sidebarText(dark))
            .frame(width: w, alignment: align)
    }

    private func cell(_ text: String, _ w: CGFloat, align: Alignment = .leading, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(muted ? AppTheme.sidebarText(dark) : (dark ? Color.white.opacity(0.9) : Color.primary))
            .lineLimit(1)
            .frame(width: w, alignment: align)
    }

    private func formatBytes(_ bytes: Double) -> String {
        let gb = bytes / 1_073_741_824.0
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        let mb = bytes / 1_048_576.0
        if mb >= 1 { return String(format: "%.2f MB", mb) }
        let kb = bytes / 1024.0
        if kb >= 1 { return String(format: "%.2f KB", kb) }
        return String(format: "%.0f B", bytes)
    }

    private func applyPreset(days: Int) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let end = Date()
        model.tqEnd = f.string(from: end)
        model.tqStart = f.string(from: Calendar.current.date(byAdding: .day, value: days, to: end) ?? end)
    }

    private func applyMonthPreset() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        model.tqStart = f.string(from: Calendar.current.date(from: comps) ?? now)
        model.tqEnd = f.string(from: now)
    }
}
