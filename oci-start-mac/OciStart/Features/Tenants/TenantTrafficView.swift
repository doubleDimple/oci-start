import SwiftUI

/// Web 整页「流量查询」`/monitor/homePage` → `oci_monitor.ftl` + `oci_monitor.css`
/// 布局对齐：筛选栏 → 四统计卡 → 三占比环图 → 总体趋势折线 → 实例柱状趋势
struct TenantTrafficView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController

    @State private var regionMenuOpen = false

    private var dark: Bool { appearance.isDarkEffective }
    private var tenant: TenantItem? { model.trafficParent }

    // Web CSS tokens (oci_monitor.css)
    private var accentGreen: Color { AppTheme.sidebarActive } // #1abc9c
    private var accentBlue: Color { Color(hex: "4d9eff") }
    private var accentRed: Color { Color(hex: "f87171") }
    private var surface: Color { dark ? Color(hex: "1a1d27") : Color.white }
    private var surface2: Color { dark ? Color(hex: "1f2233") : Color(hex: "f8f9fa") }
    private var cardBorder: Color { dark ? Color(hex: "2a2d3a") : Color(hex: "e2e8f0") }
    private var primaryText: Color { dark ? Color(hex: "e2e8f0") : Color(hex: "222222") }
    private var secondaryText: Color { dark ? Color(hex: "8892a4") : Color(hex: "555555") }
    private var pageBg: Color { dark ? Color(hex: "0f1117") : Color(hex: "f3f6fa") }
    private var inColor: Color { Color(hex: "34d399") }
    private var outColor: Color { Color(hex: "f87171") }

    // MARK: - Aggregations (mirror oci_monitor.js)

    private var totalIngress: Double {
        model.tqRows.reduce(0) { $0 + $1.ingressBytes }
    }
    private var totalEgress: Double {
        model.tqRows.reduce(0) { $0 + $1.egressBytes }
    }
    private var totalAll: Double { totalIngress + totalEgress }

    /// Time-bucketed series for overall trend (GB).
    private var trendSeries: (times: [String], ingress: [Double], egress: [Double], total: [Double]) {
        var bucket: [String: (inB: Double, outB: Double)] = [:]
        for r in model.tqRows {
            let key = normalizeTimeKey(r.timePoint)
            guard !key.isEmpty else { continue }
            var cur = bucket[key] ?? (0, 0)
            cur.inB += r.ingressBytes
            cur.outB += r.egressBytes
            bucket[key] = cur
        }
        let times = bucket.keys.sorted()
        let ingress = times.map { (bucket[$0]?.inB ?? 0) / 1_073_741_824.0 }
        let egress = times.map { (bucket[$0]?.outB ?? 0) / 1_073_741_824.0 }
        let total = zip(ingress, egress).map { $0 + $1 }
        return (times, ingress, egress, total)
    }

    /// Per-instance samples for bar charts.
    private var instanceGroups: [(id: String, name: String, ip: String, samples: [TenantTrafficRow])] {
        var map: [String: [TenantTrafficRow]] = [:]
        var meta: [String: (name: String, ip: String)] = [:]
        for r in model.tqRows {
            let key = r.instanceId.isEmpty ? r.title : r.instanceId
            map[key, default: []].append(r)
            if meta[key] == nil {
                meta[key] = (r.title, r.ipText)
            }
        }
        return map.keys.sorted().compactMap { key in
            guard let samples = map[key] else { return nil }
            let sorted = samples.sorted { $0.timePoint < $1.timePoint }
            let m = meta[key] ?? (key, "")
            return (key, m.name, m.ip, sorted)
        }
    }

    private var regionDisplayText: String {
        let selected = model.tqSelectedRegionIds
        if selected.isEmpty { return "请选择区域" }
        let names = model.tqRegions
            .filter { selected.contains($0.id) }
            .map { regionLabel($0) }
        if names.isEmpty {
            return selected.count == 1 ? "已选 1 个区域" : "已选 \(selected.count) 个区域"
        }
        if names.count <= 2 { return names.joined(separator: "、") }
        return names.prefix(2).joined(separator: "、") + " +\(names.count - 2)"
    }

    var body: some View {
        PageScaffold(
            title: "实例流量监控",
            subtitle: tenant.map { $0.displayName },
            systemImage: "chart.bar.xaxis",
            toolbar: { toolbar },
            content: { mainContent }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "返回", systemImage: "chevron.left", kind: .secondary) {
                model.closeTrafficPage()
            }
        }
    }

    // MARK: - Main

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filterControls
                statsCards
                alertChartsRow
                trendCard
                instanceSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(pageBg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter (Web .filter-controls)

    private var filterControls: some View {
        HStack(alignment: .center, spacing: 14) {
            // Region multi-select
            regionMultiSelect
                .frame(width: 240)

            // Time presets
            HStack(spacing: 8) {
                Text("时间范围：")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryText)
                presetBtn("今天", value: "today")
                presetBtn("本月", value: "month")
                presetBtn("自定义", value: "custom")
            }

            if model.tqTimePreset == "custom" {
                HStack(spacing: 8) {
                    dateField(text: $model.tqStart)
                    Text("至")
                        .font(.system(size: 12))
                        .foregroundColor(secondaryText)
                    dateField(text: $model.tqEnd)
                }
            }

            Button(action: {
                guard let t = tenant else { return }
                Task { await model.queryTraffic(t) }
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

            Button(action: { model.closeTrafficPage() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(accentGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(accentGreen, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(14)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
    }

    private func presetBtn(_ title: String, value: String) -> some View {
        let active = model.tqTimePreset == value
        return Button(action: { model.applyTrafficPreset(value) }) {
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

    // MARK: - Region multi-select (Web .multi-select-container)

    private var regionMultiSelect: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { regionMenuOpen.toggle() }) {
                HStack {
                    Text(regionDisplayText)
                        .font(.system(size: 13))
                        .foregroundColor(primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: regionMenuOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(dark ? Color(hex: "161820") : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(cardBorder, lineWidth: 1)
                )
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())

            if regionMenuOpen {
                VStack(alignment: .leading, spacing: 0) {
                    regionOptionRow(
                        title: model.tqSelectedRegionIds.count == model.tqRegions.count && !model.tqRegions.isEmpty
                            ? "取消全选" : "全选",
                        selected: false,
                        isAction: true
                    ) {
                        if model.tqSelectedRegionIds.count == model.tqRegions.count && !model.tqRegions.isEmpty {
                            model.clearTrafficRegions()
                        } else {
                            model.selectAllTrafficRegions()
                        }
                    }
                    Divider().background(cardBorder)
                    if model.tqRegions.isEmpty {
                        Text("暂无区域（将使用当前租户）")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryText)
                            .padding(10)
                    } else {
                        ForEach(model.tqRegions) { reg in
                            regionOptionRow(
                                title: regionLabel(reg),
                                selected: model.tqSelectedRegionIds.contains(reg.id),
                                isAction: false
                            ) {
                                model.toggleTrafficRegion(reg.id)
                            }
                        }
                    }
                }
                .background(surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(cardBorder, lineWidth: 1)
                )
                .cornerRadius(4)
                .shadow(color: Color.black.opacity(dark ? 0.35 : 0.08), radius: 6, y: 2)
                .padding(.top, 4)
            }
        }
        .zIndex(regionMenuOpen ? 20 : 0)
    }

    private func regionOptionRow(title: String, selected: Bool, isAction: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !isAction {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundColor(selected ? accentGreen : secondaryText)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(primaryText)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func regionLabel(_ r: TenantRegionOption) -> String {
        if !r.region.isEmpty { return r.region }
        if !r.tenancyName.isEmpty { return r.tenancyName }
        return r.id
    }

    // MARK: - Stats cards (Web .stats-cards)

    private var statsCards: some View {
        HStack(spacing: 16) {
            statCard(icon: "chart.bar", title: "总流量", value: formatGB(totalAll), iconColor: accentGreen)
            statCard(icon: "arrow.down", title: "入站流量", value: formatGB(totalIngress), iconColor: accentGreen)
            statCard(icon: "arrow.up", title: "出站流量", value: formatGB(totalEgress), iconColor: accentGreen)
            statCard(icon: "bell.fill", title: "预警阈值", value: formatTBorGB(model.tqThresholdGB), iconColor: accentRed)
        }
    }

    private func statCard(icon: String, title: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(secondaryText)
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(dark ? 0.25 : 0.05), radius: 3, y: 1)
    }

    // MARK: - Alert donut charts (Web .alert-charts-container)

    private var alertChartsRow: some View {
        HStack(spacing: 16) {
            alertDonutCard(
                title: "总流量占比",
                usedGB: totalAll / 1_073_741_824.0,
                usedColor: accentBlue
            )
            alertDonutCard(
                title: "入站流量占比",
                usedGB: totalIngress / 1_073_741_824.0,
                usedColor: inColor
            )
            alertDonutCard(
                title: "出站流量占比",
                usedGB: totalEgress / 1_073_741_824.0,
                usedColor: outColor
            )
        }
    }

    private func alertDonutCard(title: String, usedGB: Double, usedColor: Color) -> some View {
        let threshold = max(model.tqThresholdGB, 0.001)
        let remain = max(threshold - usedGB, 0)
        let pct = min(100, (usedGB / threshold) * 100)
        return VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(primaryText)
            TrafficDonutView(
                used: usedGB,
                remain: remain,
                usedColor: usedColor,
                remainColor: dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                centerText: String(format: "%.1f%%", pct),
                dark: dark
            )
            .frame(height: 180)
            HStack(spacing: 16) {
                legendItem(usedColor, "已用 \(String(format: "%.2f", usedGB)) GB")
                legendItem(remainColor, "剩余 \(String(format: "%.2f", remain)) GB")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(dark ? 0.25 : 0.05), radius: 3, y: 1)
    }

    private var remainColor: Color {
        dark ? Color.white.opacity(0.25) : Color.black.opacity(0.2)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(secondaryText)
                .lineLimit(1)
        }
    }

    // MARK: - Overall trend (Web #trafficWaveChart)

    private var trendCard: some View {
        let series = trendSeries
        return VStack(spacing: 0) {
            Text("总体流量趋势")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(Rectangle().frame(height: 1).foregroundColor(cardBorder), alignment: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    legendItem(inColor, "入站流量")
                    legendItem(outColor, "出站流量")
                    legendItem(accentBlue, "总流量")
                    Spacer()
                    Text("流量 (GB)")
                        .font(.system(size: 11))
                        .foregroundColor(secondaryText)
                }

                if series.times.isEmpty {
                    emptyChartPlaceholder("暂无趋势数据，请选择区域后查询")
                        .frame(height: 280)
                } else {
                    TrafficLineChart(
                        times: series.times,
                        series: [
                            (series.ingress, inColor),
                            (series.egress, outColor),
                            (series.total, accentBlue)
                        ],
                        dark: dark,
                        yUnit: "GB"
                    )
                    .frame(height: 300)
                }
            }
            .padding(16)
        }
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(dark ? 0.25 : 0.05), radius: 3, y: 1)
    }

    // MARK: - Instance bar charts (Web .instance-charts-container)

    private var instanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("实例展示流量趋势")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity)

            if instanceGroups.isEmpty {
                emptyChartPlaceholder("暂无实例流量数据")
                    .frame(height: 120)
            } else {
                // 2-column wrap similar to Web flex wrap of 550px cards
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 420, maximum: 560), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(instanceGroups, id: \.id) { group in
                        instanceCard(group)
                    }
                }
            }
        }
        .padding(16)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(dark ? 0.25 : 0.05), radius: 3, y: 1)
    }

    private func instanceCard(_ group: (id: String, name: String, ip: String, samples: [TenantTrafficRow])) -> some View {
        // Aggregate by day label for bars (Web uses timePoint date part, MB units)
        let buckets = instanceDayBuckets(group.samples)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryText)
                    .lineLimit(1)
                Spacer()
                Text(group.ip.isEmpty ? "IP: —" : "IP: \(group.ip)")
                    .font(.system(size: 12))
                    .foregroundColor(secondaryText)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                legendItem(inColor, "入站流量 (MB)")
                legendItem(outColor, "出站流量 (MB)")
                Spacer()
                Text("流量 (MB)")
                    .font(.system(size: 10))
                    .foregroundColor(secondaryText)
            }
            if buckets.labels.isEmpty {
                emptyChartPlaceholder("无时间序列")
                    .frame(height: 200)
            } else {
                TrafficBarChart(
                    labels: buckets.labels,
                    ingress: buckets.ingressMB,
                    egress: buckets.egressMB,
                    inColor: inColor,
                    outColor: outColor,
                    dark: dark
                )
                .frame(height: 260)
            }
        }
        .padding(14)
        .background(surface2)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
        .cornerRadius(10)
    }

    private func instanceDayBuckets(_ samples: [TenantTrafficRow]) -> (labels: [String], ingressMB: [Double], egressMB: [Double]) {
        var map: [String: (inB: Double, outB: Double)] = [:]
        for s in samples {
            let key = dayLabel(s.timePoint)
            guard !key.isEmpty else {
                // No timePoint: single aggregate bar
                let k = "合计"
                var cur = map[k] ?? (0, 0)
                cur.inB += s.ingressBytes
                cur.outB += s.egressBytes
                map[k] = cur
                continue
            }
            var cur = map[key] ?? (0, 0)
            cur.inB += s.ingressBytes
            cur.outB += s.egressBytes
            map[key] = cur
        }
        let labels = map.keys.sorted()
        let ingress = labels.map { (map[$0]?.inB ?? 0) / 1_048_576.0 }
        let egress = labels.map { (map[$0]?.outB ?? 0) / 1_048_576.0 }
        return (labels, ingress, egress)
    }

    // MARK: - Helpers

    private func emptyChartPlaceholder(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 28))
                .foregroundColor(secondaryText.opacity(0.45))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatGB(_ bytes: Double) -> String {
        String(format: "%.2f GB", bytes / 1_073_741_824.0)
    }

    private func formatTBorGB(_ valueGB: Double) -> String {
        if valueGB >= 1024 {
            return String(format: "%.2f TB", valueGB / 1024.0)
        }
        return String(format: "%.2f GB", valueGB)
    }

    private func normalizeTimeKey(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        // Accept "yyyy-MM-dd'T'HH:mm:ss" or "yyyy-MM-dd HH:mm:ss"
        return raw.replacingOccurrences(of: "T", with: " ")
    }

    private func dayLabel(_ raw: String) -> String {
        let n = normalizeTimeKey(raw)
        guard n.count >= 10 else { return n }
        return String(n.prefix(10))
    }
}

// MARK: - Donut chart (Web ECharts pie radius 50%–75%)

private struct TrafficDonutView: View {
    let used: Double
    let remain: Double
    let usedColor: Color
    let remainColor: Color
    let centerText: String
    let dark: Bool

    var body: some View {
        let total = max(used + remain, 0.0001)
        let usedFrac = CGFloat(used / total)
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineW = size * 0.14
            ZStack {
                Circle()
                    .stroke(remainColor, lineWidth: lineW)
                    .frame(width: size * 0.78, height: size * 0.78)
                Circle()
                    .trim(from: 0, to: usedFrac)
                    .stroke(usedColor, style: StrokeStyle(lineWidth: lineW, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size * 0.78, height: size * 0.78)
                Text(centerText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(dark ? Color(hex: "e2e8f0") : Color(hex: "222222"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Line chart (Web ECharts smooth line)

private struct TrafficLineChart: View {
    let times: [String]
    let series: [(values: [Double], color: Color)]
    let dark: Bool
    var yUnit: String = "GB"

    private var maxY: Double {
        let m = series.flatMap { $0.values }.max() ?? 0
        return max(m * 1.15, 0.01)
    }

    var body: some View {
        GeometryReader { geo in
            let padL: CGFloat = 44
            let padR: CGFloat = 10
            let padT: CGFloat = 12
            let padB: CGFloat = 28
            let w = geo.size.width - padL - padR
            let h = geo.size.height - padT - padB
            let gridColor = dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)
            let labelColor = dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45)

            ZStack(alignment: .topLeading) {
                // Grid + Y labels
                ForEach(0..<5, id: \.self) { g in
                    let frac = CGFloat(g) / 4
                    let y = padT + h - frac * h
                    Path { p in
                        p.move(to: CGPoint(x: padL, y: y))
                        p.addLine(to: CGPoint(x: padL + w, y: y))
                    }
                    .stroke(gridColor, lineWidth: 1)
                    Text(String(format: "%.1f", maxY * Double(g) / 4))
                        .font(.system(size: 9))
                        .foregroundColor(labelColor)
                        .position(x: padL - 18, y: y)
                }

                // Series lines
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
                        .stroke(s.color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    } else if s.values.count == 1 {
                        let y = padT + h - CGFloat(s.values[0] / maxY) * h
                        Circle()
                            .fill(s.color)
                            .frame(width: 6, height: 6)
                            .position(x: padL + w / 2, y: y)
                    }
                }

                // X labels (skip to avoid overlap)
                xLabels(padL: padL, padT: padT, w: w, h: h, labelColor: labelColor)
            }
        }
    }

    @ViewBuilder
    private func xLabels(padL: CGFloat, padT: CGFloat, w: CGFloat, h: CGFloat, labelColor: Color) -> some View {
        let n = times.count
        let step = max(1, n / 8)
        ForEach(Array(stride(from: 0, to: n, by: step)), id: \.self) { i in
            let x = padL + (n > 1 ? CGFloat(i) / CGFloat(n - 1) * w : w / 2)
            Text(shortTime(times[i]))
                .font(.system(size: 9))
                .foregroundColor(labelColor)
                .position(x: x, y: padT + h + 14)
        }
    }

    private func shortTime(_ t: String) -> String {
        // "yyyy-MM-dd HH:mm:ss" → "MM-dd" or keep short
        let s = t.replacingOccurrences(of: "T", with: " ")
        if s.count >= 10 {
            let day = String(s.prefix(10))
            if day.count == 10 { return String(day.dropFirst(5)) } // MM-dd
        }
        return s
    }
}

// MARK: - Grouped bar chart (Web instance ECharts bar)

private struct TrafficBarChart: View {
    let labels: [String]
    let ingress: [Double]
    let egress: [Double]
    let inColor: Color
    let outColor: Color
    let dark: Bool

    private var maxY: Double {
        let m = max(ingress.max() ?? 0, egress.max() ?? 0)
        return max(m * 1.15, 0.01)
    }

    var body: some View {
        GeometryReader { geo in
            let padL: CGFloat = 40
            let padR: CGFloat = 8
            let padT: CGFloat = 10
            let padB: CGFloat = 36
            let w = geo.size.width - padL - padR
            let h = geo.size.height - padT - padB
            let n = max(labels.count, 1)
            let groupW = w / CGFloat(n)
            let barW = max(4, min(28, groupW * 0.32))
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
                    Text(String(format: "%.0f", maxY * Double(g) / 4))
                        .font(.system(size: 9))
                        .foregroundColor(labelColor)
                        .position(x: padL - 16, y: y)
                }

                ForEach(0..<labels.count, id: \.self) { i in
                    let cx = padL + groupW * (CGFloat(i) + 0.5)
                    let inH = CGFloat(ingress[i] / maxY) * h
                    let outH = CGFloat(egress[i] / maxY) * h
                    // Ingress bar (left)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(inColor.opacity(0.9))
                        .frame(width: barW, height: max(1, inH))
                        .position(x: cx - barW * 0.55, y: padT + h - inH / 2)
                    // Egress bar (right)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(outColor.opacity(0.9))
                        .frame(width: barW, height: max(1, outH))
                        .position(x: cx + barW * 0.55, y: padT + h - outH / 2)

                    Text(shortLabel(labels[i]))
                        .font(.system(size: 9))
                        .foregroundColor(labelColor)
                        .rotationEffect(.degrees(-35))
                        .frame(width: groupW + 8)
                        .position(x: cx, y: padT + h + 18)
                }
            }
        }
    }

    private func shortLabel(_ t: String) -> String {
        if t.count >= 10 { return String(t.dropFirst(5)) } // MM-dd
        return t
    }
}
