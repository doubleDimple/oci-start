import SwiftUI

/// Web-parity 系统监控 page (`dashboard.ftl` + `dashboard.css` + `dashboard.js`).
struct DashboardView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = DashboardViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader
                if let err = model.errorText, !err.isEmpty {
                    errorBanner(err)
                }
                statsGrid
                monitorGrid
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DashboardTheme.bg(dark).ignoresSafeArea())
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.refreshAll() }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color(hex: "3b82f6").opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "gauge")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(DashboardTheme.blue(dark))
                }
                Text("系统监控")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DashboardTheme.text(dark))
            }
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(DashboardTheme.green(dark))
                    .frame(width: 7, height: 7)
                Text(model.lastUpdateText)
                    .font(.system(size: 12))
                    .foregroundColor(DashboardTheme.muted(dark))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DashboardTheme.surface(dark))
                    .overlay(Capsule().stroke(DashboardTheme.border(dark), lineWidth: 1))
            )
        }
        .padding(.bottom, 4)
        .overlay(
            Rectangle()
                .fill(DashboardTheme.border(dark))
                .frame(height: 1),
            alignment: .bottom
        )
        .padding(.bottom, 8)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .font(.system(size: 12))
            Spacer()
            Button("重试") {
                Task { await model.refreshAll() }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(DashboardTheme.red(dark))
        .padding(12)
        .background(DashboardTheme.red(dark).opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Stats (5 cards)

    private var statsGrid: some View {
        // 5 equal columns, equal height
        HStack(alignment: .top, spacing: 14) {
            statCard(icon: "slider.horizontal.3", iconBg: Color(hex: "3b82f6"), title: "总API数",
                     value: "\(model.stats.totalApiCalls)", valueColor: nil)
            statCard(icon: "cpu", iconBg: Color(hex: "22c55e"), title: "总Boot实例数",
                     value: "\(model.stats.totalBootInstances)", valueColor: nil)
            statCard(icon: "arrow.triangle.2.circlepath", iconBg: Color(hex: "f97316"), title: "总抢机次数",
                     value: "\(model.stats.totalAttempts)", valueColor: nil)
            statCard(icon: "checkmark.circle.fill", iconBg: Color(hex: "06b6d4"), title: "抢机成功次数",
                     value: "\(model.stats.successfulAttempts)", valueColor: nil)
            statCard(icon: "xmark.circle.fill", iconBg: Color(hex: "ef4444"), title: "抢机失败次数",
                     value: "\(model.stats.failCounts)", valueColor: DashboardTheme.red(dark))
        }
        .frame(height: 118)
    }

    private func statCard(icon: String, iconBg: Color, title: String, value: String, valueColor: Color?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconBg.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconBg)
                }
                Spacer(minLength: 4)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardTheme.muted(dark))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(height: 28, alignment: .topTrailing)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(valueColor ?? DashboardTheme.text(dark))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DashboardTheme.surface(dark))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DashboardTheme.border(dark), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    // MARK: - Monitor grid

    private var monitorGrid: some View {
        // Web layout: 3 columns; network spans 2. Equal height per row.
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                equalCard { cpuCard }
                equalCard { memoryCard }
                equalCard { systemCard }
            }
            .frame(minHeight: 420)

            HStack(alignment: .top, spacing: 16) {
                equalCard { networkCard }
                    .layoutPriority(2)
                equalCard { diskCard }
                    .layoutPriority(1)
            }
            .frame(minHeight: 420)
        }
    }

    /// Stretch card to fill the row height (same size as siblings).
    private func equalCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Cards

    private var cpuCard: some View {
        monitorCard(
            icon: "cpu",
            iconColor: DashboardTheme.blue(dark),
            title: "CPU信息",
            subtitle: model.metrics.cpuModel.isEmpty ? "加载中..." : model.metrics.cpuModel,
            gaugeValue: min(100, model.metrics.cpuUsage),
            gaugeLabel: "\(Int(min(100, model.metrics.cpuUsage.rounded())))%",
            details: [
                ("物理核心", "\(model.metrics.cpuPhysicalCount) C"),
                ("逻辑核心", "\(model.metrics.cpuLogicalCount) C"),
                ("CPU温度", model.metrics.cpuTemperature > 0
                    ? String(format: "%.1f°C", model.metrics.cpuTemperature) : "N/A"),
                ("主频", String(format: "%.2f GHz", model.metrics.cpuFrequency))
            ]
        )
    }

    private var memoryCard: some View {
        let totalGB = model.metrics.totalMemory / 1024
        return monitorCard(
            icon: "rectangle.stack.fill",
            iconColor: DashboardTheme.purple(dark),
            title: "内存使用",
            subtitle: model.metrics.totalMemory > 0
                ? String(format: "总内存: %.1f GB", totalGB) : "加载中...",
            gaugeValue: min(100, model.metrics.memoryUsage),
            gaugeLabel: "\(Int(model.metrics.memoryUsage.rounded()))%",
            details: [
                ("总内存", DashboardFormat.memoryMB(model.metrics.totalMemory)),
                ("已用内存", DashboardFormat.memoryMB(model.metrics.usedMemory)),
                ("可用内存", DashboardFormat.memoryMB(model.metrics.availableMemory)),
                ("交换空间", String(format: "%.0fMB / %.0fMB",
                                   model.metrics.swapUsed, model.metrics.swapTotal))
            ]
        )
    }

    private var systemCard: some View {
        // web: uptime gauge vs half of 10 years
        let maxUptime = 315_360_000.0 / 2
        let uptimePct = min((model.metrics.systemUptime / maxUptime) * 100, 100)
        return monitorCard(
            icon: "desktopcomputer",
            iconColor: DashboardTheme.green(dark),
            title: "系统信息",
            subtitle: model.metrics.hostname.isEmpty ? "加载中..." : model.metrics.hostname,
            gaugeValue: uptimePct,
            gaugeLabel: DashboardFormat.uptimeDays(model.metrics.systemUptime),
            details: [
                ("操作系统", model.metrics.osName.isEmpty ? "-" : model.metrics.osName),
                ("系统架构", model.metrics.osArch.isEmpty ? "-" : model.metrics.osArch),
                ("运行时间", DashboardFormat.uptime(model.metrics.systemUptime)),
                ("进程数", "\(model.metrics.totalProcesses)"),
                ("线程数", "\(model.metrics.threadCount)")
            ]
        )
    }

    private var diskCard: some View {
        monitorCard(
            icon: "externaldrive.fill",
            iconColor: DashboardTheme.orange(dark),
            title: "磁盘使用",
            subtitle: "存储状态监控",
            gaugeValue: min(100, model.metrics.diskUsage),
            gaugeLabel: "\(Int(model.metrics.diskUsage.rounded()))%",
            details: [
                ("总容量", DashboardFormat.size(model.metrics.diskTotal)),
                ("已用空间", DashboardFormat.size(model.metrics.diskUsed)),
                ("可用空间", DashboardFormat.size(model.metrics.diskFree)),
                ("读写速度", "-")
            ]
        )
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(
                icon: "network",
                iconColor: DashboardTheme.cyan(dark),
                title: "网络流量",
                subtitle: "实时流量监控"
            )

            NetworkTrafficChart(samples: model.networkHistory, dark: dark)
                .frame(maxWidth: .infinity)
                .frame(height: 168)
                .padding(.bottom, 12)

            Spacer(minLength: 0)

            detailList([
                ("上传速度", DashboardFormat.speed(model.metrics.uploadSpeed)),
                ("下载速度", DashboardFormat.speed(model.metrics.downloadSpeed)),
                ("总发送", DashboardFormat.size(model.metrics.totalUploadBytes)),
                ("总接收", DashboardFormat.size(model.metrics.totalDownloadBytes))
            ], fixedRows: 5)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DashboardTheme.surface(dark))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DashboardTheme.border(dark), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func monitorCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        gaugeValue: Double,
        gaugeLabel: String,
        details: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle)
            DashboardGauge(value: gaugeValue, label: gaugeLabel, dark: dark)
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            Spacer(minLength: 0)
            // Always 5 rows so CPU / 内存 / 系统 / 磁盘 cards share identical detail area height
            detailList(details, fixedRows: 5)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DashboardTheme.surface(dark))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DashboardTheme.border(dark), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func cardHeader(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DashboardTheme.text(dark))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DashboardTheme.muted(dark))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(height: 52, alignment: .center)
        .padding(.bottom, 16)
    }

    /// Fixed-height detail rows so all cards in a row share the same content box size.
    private func detailList(_ items: [(String, String)], fixedRows: Int = 5) -> some View {
        let rowH: CGFloat = 34
        var rows = items
        while rows.count < fixedRows {
            rows.append(("", ""))
        }
        if rows.count > fixedRows {
            rows = Array(rows.prefix(fixedRows))
        }

        return VStack(spacing: 0) {
            Rectangle()
                .fill(DashboardTheme.border(dark))
                .frame(height: 1)
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .center) {
                    Text(item.0.isEmpty ? " " : item.0)
                        .font(.system(size: 12))
                        .foregroundColor(DashboardTheme.muted(dark))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.1.isEmpty ? " " : item.1)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DashboardTheme.text(dark))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(height: rowH)
                .opacity(item.0.isEmpty && item.1.isEmpty ? 0 : 1)
                if idx < rows.count - 1 {
                    Rectangle()
                        .fill(DashboardTheme.border(dark))
                        .frame(height: 1)
                }
            }
        }
        .frame(height: 1 + CGFloat(fixedRows) * rowH + CGFloat(fixedRows - 1) * 1)
    }
}

// MARK: - Gauge (web conic-gradient style)

struct DashboardGauge: View {
    let value: Double
    let label: String
    let dark: Bool

    private var clamped: Double { min(100, max(0, value)) }

    private var color: Color {
        if clamped <= 60 { return Color(hex: "22c55e") }
        if clamped <= 80 { return Color(hex: "f97316") }
        return Color(hex: "ef4444")
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DashboardTheme.gaugeTrack(dark), lineWidth: 14)
            Circle()
                .trim(from: 0, to: CGFloat(clamped / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(DashboardTheme.gaugeCenter(dark))
                .padding(22)
                .shadow(color: Color.black.opacity(dark ? 0.4 : 0.08), radius: 6, y: 2)
            Text(label)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 28)
        }
    }
}

// MARK: - Network chart

struct NetworkTrafficChart: View {
    let samples: [NetworkSample]
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                legendDot(Color(hex: "3b82f6"), "上传")
                legendDot(Color(hex: "22c55e"), "下载")
                Spacer()
                Text("KB/s")
                    .font(.system(size: 11))
                    .foregroundColor(DashboardTheme.muted(dark))
            }
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let maxY = max(1, samples.map { max($0.upload, $0.download) }.max() ?? 1) * 1.15

                ZStack {
                    // grid
                    Path { p in
                        for i in 0..<4 {
                            let y = h * CGFloat(i) / 3
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(DashboardTheme.border(dark).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    if samples.count >= 2 {
                        areaPath(samples.map(\.upload), maxY: maxY, size: geo.size, color: Color(hex: "3b82f6"))
                        areaPath(samples.map(\.download), maxY: maxY, size: geo.size, color: Color(hex: "22c55e"))
                    } else {
                        Text("等待流量数据…")
                            .font(.system(size: 12))
                            .foregroundColor(DashboardTheme.muted(dark))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(10)
        .background(DashboardTheme.bg(dark).opacity(0.35))
        .cornerRadius(10)
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(DashboardTheme.muted(dark))
        }
    }

    private func areaPath(_ values: [Double], maxY: Double, size: CGSize, color: Color) -> some View {
        let n = values.count
        guard n > 1 else { return AnyView(EmptyView()) }
        let w = size.width
        let h = size.height

        func pt(_ i: Int) -> CGPoint {
            let x = w * CGFloat(i) / CGFloat(n - 1)
            let y = h - h * CGFloat(values[i] / maxY)
            return CGPoint(x: x, y: y)
        }

        var line = Path()
        line.move(to: pt(0))
        for i in 1..<n { line.addLine(to: pt(i)) }

        var fill = Path()
        fill.move(to: CGPoint(x: pt(0).x, y: h))
        fill.addLine(to: pt(0))
        for i in 1..<n { fill.addLine(to: pt(i)) }
        fill.addLine(to: CGPoint(x: pt(n - 1).x, y: h))
        fill.closeSubpath()

        return AnyView(
            ZStack {
                fill.fill(color.opacity(0.08))
                line.stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        )
    }
}

// MARK: - Theme tokens from dashboard.css

enum DashboardTheme {
    static func bg(_ dark: Bool) -> Color { dark ? Color(hex: "1a1d21") : Color(hex: "f0f4f8") }
    static func surface(_ dark: Bool) -> Color { dark ? Color(hex: "22262b") : Color.white }
    static func border(_ dark: Bool) -> Color { dark ? Color(hex: "31363d") : Color(hex: "dde3ec") }
    static func text(_ dark: Bool) -> Color { dark ? Color(hex: "cdd9e5") : Color(hex: "1a202c") }
    static func muted(_ dark: Bool) -> Color { dark ? Color(hex: "768390") : Color(hex: "64748b") }
    static func blue(_ dark: Bool) -> Color { dark ? Color(hex: "4d9eff") : Color(hex: "2563eb") }
    static func green(_ dark: Bool) -> Color { dark ? Color(hex: "3fb950") : Color(hex: "16a34a") }
    static func orange(_ dark: Bool) -> Color { dark ? Color(hex: "f78166") : Color(hex: "ea580c") }
    static func red(_ dark: Bool) -> Color { dark ? Color(hex: "ff6b6b") : Color(hex: "dc2626") }
    static func purple(_ dark: Bool) -> Color { dark ? Color(hex: "bc8cff") : Color(hex: "7c3aed") }
    static func cyan(_ dark: Bool) -> Color { dark ? Color(hex: "39c5cf") : Color(hex: "0891b2") }
    static func gaugeTrack(_ dark: Bool) -> Color { dark ? Color(hex: "252a30") : Color(hex: "e8edf3") }
    static func gaugeCenter(_ dark: Bool) -> Color { dark ? Color(hex: "22262b") : Color.white }
}
