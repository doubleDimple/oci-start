import SwiftUI

/// Web 整页「费用统计」`/cost/costPage` → `oci_cost.ftl` + `oci_cost.js`
/// 布局：筛选栏 → 五统计卡 → 每日趋势折线 → 费用明细表（客户端分页）
struct TenantCostView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var tenant: TenantItem? { model.costParent }

    // tokens（对齐 oci_cost / oci_monitor）
    private var accentGreen: Color { AppTheme.sidebarActive }
    private var computeColor: Color { Color(hex: "4a73ff") }
    private var storageColor: Color { Color(hex: "ff9f40") }
    private var networkColor: Color { Color(hex: "1abc9c") }
    private var otherColor: Color { Color(hex: "6b7280") }
    private var surface: Color { dark ? Color(hex: "1a1d27") : Color.white }
    private var cardBorder: Color { dark ? Color(hex: "2a2d3a") : Color(hex: "e2e8f0") }
    private var primaryText: Color { dark ? Color(hex: "e2e8f0") : Color(hex: "222222") }
    private var secondaryText: Color { dark ? Color(hex: "8892a4") : Color(hex: "555555") }
    private var pageBg: Color { dark ? Color(hex: "0f1117") : Color(hex: "f3f6fa") }

    private let wDay: CGFloat = 110
    private let wType: CGFloat = 120
    private let wCost: CGFloat = 100
    private let minSku: CGFloat = 140
    private let minRes: CGFloat = 160
    private let hPad: CGFloat = 12

    var body: some View {
        PageScaffold(
            title: "费用统计",
            subtitle: tenant.map { $0.displayName },
            systemImage: "creditcard",
            toolbar: { toolbar },
            content: { mainContent }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "返回列表", systemImage: "chevron.left", kind: .secondary) {
                model.closeCost()
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                guard let t = tenant else { return }
                Task { await model.queryCost(t) }
            }
            if model.costLoading {
                ProgressView().scaleEffect(0.7)
            }
        }
    }

    // MARK: - Main

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterControls
                if let err = model.costError, !err.isEmpty {
                    errorBanner(err)
                }
                statsCards
                trendCard
                detailTable
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(pageBg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter

    private var filterControls: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                Text("时间范围：")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryText)
                presetBtn("今天", value: "today")
                presetBtn("本月", value: "month")
                presetBtn("自定义", value: "custom")
            }

            if model.costTimePreset == "custom" {
                HStack(spacing: 8) {
                    dateField(text: $model.costStart)
                    Text("至")
                        .font(.system(size: 12))
                        .foregroundColor(secondaryText)
                    dateField(text: $model.costEnd)
                }
            } else {
                Text("\(model.costStart)  ~  \(model.costEnd)")
                    .font(.system(size: 12))
                    .foregroundColor(secondaryText)
            }

            Button(action: {
                guard let t = tenant else { return }
                Task { await model.queryCost(t) }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                    Text("查询")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(accentGreen)
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer(minLength: 8)
        }
        .padding(14)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
    }

    private func presetBtn(_ title: String, value: String) -> some View {
        let active = model.costTimePreset == value
        return Button(action: { model.applyCostPreset(value) }) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(active ? .white : accentGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? accentGreen : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(accentGreen, lineWidth: 1)
                )
                .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func dateField(text: Binding<String>) -> some View {
        AppTextField(text: text, placeholder: "yyyy-MM-dd")
            .frame(width: 130)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") {
                guard let t = tenant else { return }
                Task { await model.queryCost(t) }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Stats

    private var statsCards: some View {
        HStack(spacing: 12) {
            statCard(title: "总费用", value: money(model.costTotal), color: accentGreen)
            statCard(title: "计算", value: money(model.costCompute), color: computeColor)
            statCard(title: "存储", value: money(model.costStorage), color: storageColor)
            statCard(title: "网络", value: money(model.costNetwork), color: networkColor)
            statCard(title: "其他", value: money(model.costOther), color: otherColor)
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(secondaryText)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Rectangle()
                .fill(color)
                .frame(height: 3)
                .cornerRadius(1.5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(dark ? 0.25 : 0.05), radius: 3, y: 1)
    }

    // MARK: - Trend

    private var trendCard: some View {
        let series = model.costTrendSeries
        return VStack(spacing: 0) {
            HStack {
                Text("每日费用趋势")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(primaryText)
                Spacer()
                HStack(spacing: 6) {
                    chartSwitch("全部", "all")
                    chartSwitch("计算", "compute")
                    chartSwitch("存储", "storage")
                    chartSwitch("网络", "network")
                    chartSwitch("其他", "other")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                chartLegend
                if series.days.isEmpty {
                    Text(model.costLoading ? "加载中…" : "请选择时间范围后查询")
                        .font(.system(size: 13))
                        .foregroundColor(secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                } else {
                    CostLineChart(
                        days: series.days,
                        series: chartSeries(from: series),
                        dark: dark
                    )
                    .frame(height: 260)
                }
            }
            .padding(16)
        }
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
    }

    private var chartLegend: some View {
        HStack(spacing: 14) {
            if model.costChartType == "all" {
                legendDot(computeColor, "计算")
                legendDot(storageColor, "存储")
                legendDot(networkColor, "网络")
                legendDot(otherColor, "其他")
            } else {
                let cat = TenantCostCategory(rawValue: model.costChartType) ?? .other
                legendDot(colorFor(cat), cat.title)
            }
            Spacer()
            Text("USD")
                .font(.system(size: 11))
                .foregroundColor(secondaryText)
        }
    }

    private func chartSwitch(_ title: String, _ value: String) -> some View {
        let active = model.costChartType == value
        return Button(action: { model.costChartType = value }) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(active ? .white : accentGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? accentGreen : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(accentGreen, lineWidth: 1)
                )
                .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func chartSeries(from s: (days: [String], compute: [Double], storage: [Double], network: [Double], other: [Double])) -> [(values: [Double], color: Color)] {
        switch model.costChartType {
        case "compute": return [(s.compute, computeColor)]
        case "storage": return [(s.storage, storageColor)]
        case "network": return [(s.network, networkColor)]
        case "other": return [(s.other, otherColor)]
        default:
            return [
                (s.compute, computeColor),
                (s.storage, storageColor),
                (s.network, networkColor),
                (s.other, otherColor)
            ]
        }
    }

    private func colorFor(_ c: TenantCostCategory) -> Color {
        switch c {
        case .compute: return computeColor
        case .storage: return storageColor
        case .network: return networkColor
        case .other: return otherColor
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(secondaryText)
        }
    }

    // MARK: - Detail table

    private var detailTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("费用明细")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(primaryText)
                Spacer()
                Button(action: { model.toggleCostPositiveFilter() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.horizontal.3.decrease.circle")
                            .font(.system(size: 12))
                        Text(model.costFilterPositiveOnly ? "显示全部" : "仅显示 > 0")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(accentGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(accentGreen, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

            if model.costLoading && model.costItems.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("加载费用…")
                        .font(.system(size: 12))
                        .foregroundColor(secondaryText)
                        .padding(.leading, 8)
                    Spacer()
                }
                .frame(height: 120)
            } else if model.filteredCostItems.isEmpty {
                Text(model.costItems.isEmpty ? "暂无费用数据，请选择时间范围后查询" : "筛选后无数据")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(28)
            } else {
                GeometryReader { geo in
                    let fixed = wDay + wType + wCost + minSku + minRes + hPad * 2
                    let totalW = max(geo.size.width, fixed)
                    let flex = max(0, totalW - fixed)
                    let wSku = minSku + flex * 0.45
                    let wRes = minRes + flex * 0.55

                    VStack(spacing: 0) {
                        costHeader(wSku: wSku, wRes: wRes, width: totalW)
                        ForEach(Array(model.costPageItems.enumerated()), id: \.offset) { idx, item in
                            costRow(index: idx, item: item, wSku: wSku, wRes: wRes, width: totalW)
                        }
                        PaginationBar(state: $model.costPageState) {
                            model.syncCostPagination()
                        }
                    }
                    .frame(width: totalW, alignment: .topLeading)
                }
                .frame(minHeight: CGFloat(44 + model.costPageItems.count * 36 + 52))
            }
        }
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
    }

    private func costHeader(wSku: CGFloat, wRes: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            colHeader("日期", wDay)
            colHeader("资源类型", wType)
            colHeader("SKU", wSku)
            colHeader("资源 ID", wRes)
            colHeader("费用", wCost, align: .trailing)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
    }

    private func costRow(index: Int, item: TenantCostItem, wSku: CGFloat, wRes: CGFloat, width: CGFloat) -> some View {
        let positive = item.cost > 0
        let stripe = index % 2 == 1 ? AppTheme.sidebarHover(dark).opacity(0.18) : Color.clear
        return HStack(spacing: 0) {
            cell(item.day.isEmpty ? "—" : item.day, wDay, muted: true)
            cell(item.resourceType.isEmpty ? "—" : item.resourceType, wType)
            cell(item.skuName.isEmpty ? "—" : item.skuName, wSku, muted: true)
            cell(item.resourceId.isEmpty ? "—" : item.resourceId, wRes, muted: true, mono: true)
            Text(money6(item.cost))
                .font(.system(size: 12, weight: positive ? .semibold : .regular, design: .monospaced))
                .foregroundColor(positive ? accentGreen : secondaryText)
                .frame(width: wCost, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 8)
        .frame(width: width, alignment: .leading)
        .background(stripe)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(cardBorder.opacity(0.6)),
            alignment: .bottom
        )
    }

    private func colHeader(_ title: String, _ w: CGFloat, align: Alignment = .leading) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.sidebarText(dark))
            .frame(width: w, alignment: align)
    }

    private func cell(_ text: String, _ w: CGFloat, muted: Bool = false, mono: Bool = false) -> some View {
        Text(text)
            .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 12))
            .foregroundColor(muted ? secondaryText : primaryText)
            .lineLimit(1)
            .help(text)
            .frame(width: w, alignment: .leading)
    }

    private func money(_ v: Double) -> String {
        String(format: "$%.4f", v)
    }

    private func money6(_ v: Double) -> String {
        String(format: "$%.6f", v)
    }
}

// MARK: - Line chart（对齐流量页 TrafficLineChart，独立副本避免耦合）

private struct CostLineChart: View {
    let days: [String]
    let series: [(values: [Double], color: Color)]
    let dark: Bool

    private var maxY: Double {
        let m = series.flatMap { $0.values }.max() ?? 0
        return max(m * 1.15, 0.0001)
    }

    var body: some View {
        GeometryReader { geo in
            let padL: CGFloat = 52
            let padR: CGFloat = 10
            let padT: CGFloat = 12
            let padB: CGFloat = 28
            let w = geo.size.width - padL - padR
            let h = geo.size.height - padT - padB
            let gridColor = dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)
            let labelColor = dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45)

            ZStack(alignment: .topLeading) {
                ForEach(0..<5, id: \.self) { g in
                    let frac = CGFloat(g) / 4
                    let y = padT + h - frac * h
                    Path { p in
                        p.move(to: CGPoint(x: padL, y: y))
                        p.addLine(to: CGPoint(x: padL + w, y: y))
                    }
                    .stroke(gridColor, lineWidth: 1)
                    Text(formatY(maxY * Double(g) / 4))
                        .font(.system(size: 9))
                        .foregroundColor(labelColor)
                        .position(x: padL - 24, y: y)
                }

                ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                    if s.values.count >= 2 {
                        Path { p in
                            for (i, v) in s.values.enumerated() {
                                let x = padL + CGFloat(i) / CGFloat(s.values.count - 1) * w
                                let y = padT + h - CGFloat(v / maxY) * h
                                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                                else { p.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(s.color, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                    } else if s.values.count == 1 {
                        let y = padT + h - CGFloat(s.values[0] / maxY) * h
                        Circle()
                            .fill(s.color)
                            .frame(width: 6, height: 6)
                            .position(x: padL + w / 2, y: y)
                    }
                }

                xLabels(padL: padL, padT: padT, w: w, h: h, labelColor: labelColor)
            }
        }
    }

    @ViewBuilder
    private func xLabels(padL: CGFloat, padT: CGFloat, w: CGFloat, h: CGFloat, labelColor: Color) -> some View {
        let n = days.count
        let step = max(1, n / 8)
        ForEach(Array(stride(from: 0, to: n, by: step)), id: \.self) { i in
            let x = padL + (n > 1 ? CGFloat(i) / CGFloat(n - 1) * w : w / 2)
            Text(shortDay(days[i]))
                .font(.system(size: 9))
                .foregroundColor(labelColor)
                .position(x: x, y: padT + h + 14)
        }
    }

    private func shortDay(_ d: String) -> String {
        if d.count >= 10 { return String(d.dropFirst(5)) } // MM-dd
        return d
    }

    private func formatY(_ v: Double) -> String {
        if v >= 1 { return String(format: "%.2f", v) }
        if v >= 0.01 { return String(format: "%.3f", v) }
        return String(format: "%.4f", v)
    }
}
