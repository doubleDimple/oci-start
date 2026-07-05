import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader
                statsGrid
                instanceSection
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .background(dbBg.ignoresSafeArea())
        .navigationTitle("仪表板")
        .toolbar {
            ToolbarItem {
                Button(action: { Task {
                    await appState.loadDashboard()
                    await appState.loadInstances()
                }}) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            Task {
                if appState.dashboardStats == nil { await appState.loadDashboard() }
                if appState.instances.isEmpty    { await appState.loadInstances() }
            }
        }
    }

    // MARK: - Colors (mirrors dashboard.css)
    private var dbBg:      Color { scheme == .dark ? Color(hex: "1a1d21") : Color(hex: "f0f4f8") }
    private var surface:   Color { scheme == .dark ? Color(hex: "22262b") : Color.white }
    private var border:    Color { scheme == .dark ? Color(hex: "31363d") : Color(hex: "dde3ec") }
    private var textPrim:  Color { scheme == .dark ? Color(hex: "cdd9e5") : Color(hex: "1a202c") }
    private var textMuted: Color { scheme == .dark ? Color(hex: "768390") : Color(hex: "64748b") }
    private var dbBlue:    Color { scheme == .dark ? Color(hex: "4d9eff") : Color(hex: "2563eb") }
    private var dbGreen:   Color { scheme == .dark ? Color(hex: "3fb950") : Color(hex: "16a34a") }
    private var dbOrange:  Color { scheme == .dark ? Color(hex: "f78166") : Color(hex: "ea580c") }
    private var dbRed:     Color { scheme == .dark ? Color(hex: "ff6b6b") : Color(hex: "dc2626") }
    private var dbCyan:    Color { scheme == .dark ? Color(hex: "39c5cf") : Color(hex: "0891b2") }

    // MARK: - Page Header
    private var pageHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(dbBlue.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "chart.pie.fill")
                    .foregroundColor(dbBlue)
                    .font(.system(size: 17))
            }
            Text("仪表板")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(textPrim)
            Spacer()
            // Live dot + last update
            HStack(spacing: 6) {
                Circle()
                    .fill(dbGreen)
                    .frame(width: 7, height: 7)
                Text("实时数据")
                    .font(.system(size: 12))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(surface)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .padding(.bottom, 4)
    }

    // MARK: - Stats Grid (5 cards matching web)
    private var statsGrid: some View {
        let stats = appState.dashboardStats
        return HStack(spacing: 14) {
            WebStatCard(
                title: "总 API 调用",
                value: format(stats?.totalApiCalls),
                iconName: "slider.horizontal.3",
                iconBg: dbBlue.opacity(0.14),
                iconFg: dbBlue,
                textPrim: textPrim, textMuted: textMuted,
                surface: surface, border: border
            )
            WebStatCard(
                title: "开机实例",
                value: format(stats?.totalBootInstances),
                iconName: "cpu",
                iconBg: dbGreen.opacity(0.14),
                iconFg: dbGreen,
                textPrim: textPrim, textMuted: textMuted,
                surface: surface, border: border
            )
            WebStatCard(
                title: "总尝试次数",
                value: format(stats?.totalAttempts),
                iconName: "arrow.clockwise",
                iconBg: dbOrange.opacity(0.14),
                iconFg: dbOrange,
                textPrim: textPrim, textMuted: textMuted,
                surface: surface, border: border
            )
            WebStatCard(
                title: "成功次数",
                value: format(stats?.successfulAttempts),
                iconName: "checkmark.circle.fill",
                iconBg: dbCyan.opacity(0.14),
                iconFg: dbCyan,
                textPrim: textPrim, textMuted: textMuted,
                surface: surface, border: border
            )
            WebStatCard(
                title: "失败次数",
                value: format(stats?.failCounts),
                iconName: "xmark.circle.fill",
                iconBg: dbRed.opacity(0.14),
                iconFg: dbRed,
                textPrim: textPrim, textMuted: textMuted,
                surface: surface, border: border,
                valueColor: dbRed
            )
        }
    }

    // MARK: - Instance Section
    private var instanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("实例状态")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(textPrim)
                Spacer()
                Text("\(appState.instances.count) 台")
                    .font(.system(size: 12))
                    .foregroundColor(textMuted)
            }
            .padding(.bottom, 2)

            if appState.instancesLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .frame(height: 80)
            } else if appState.instances.isEmpty {
                HStack { Spacer(); Text("暂无实例数据").foregroundColor(textMuted); Spacer() }
                    .frame(height: 80)
            } else {
                HStack(spacing: 12) {
                    instanceBadge(
                        label: "全部",
                        value: appState.instances.count,
                        fg: textPrim,
                        bg: border.opacity(0.5)
                    )
                    instanceBadge(
                        label: "运行中",
                        value: appState.instances.filter(\.isRunning).count,
                        fg: dbGreen,
                        bg: dbGreen.opacity(0.12)
                    )
                    instanceBadge(
                        label: "已停止",
                        value: appState.instances.filter(\.isStopped).count,
                        fg: dbRed,
                        bg: dbRed.opacity(0.12)
                    )
                    instanceBadge(
                        label: "转换中",
                        value: appState.instances.filter(\.isTransitioning).count,
                        fg: dbOrange,
                        bg: dbOrange.opacity(0.12)
                    )
                    Spacer()
                }
            }
        }
        .padding(22)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func instanceBadge(label: String, value: Int, fg: Color, bg: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(fg)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(fg.opacity(0.75))
        }
        .frame(minWidth: 80)
        .padding(.vertical, 14)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func format(_ v: Int64?) -> String {
        guard let v = v else { return "—" }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000     { return String(format: "%.1fK", Double(v) / 1_000) }
        return "\(v)"
    }
}

// MARK: - WebStatCard (matches .stat-card in dashboard.css)

struct WebStatCard: View {
    let title: String
    let value: String
    let iconName: String
    let iconBg: Color
    let iconFg: Color
    let textPrim: Color
    let textMuted: Color
    let surface: Color
    let border: Color
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: iconName)
                        .foregroundColor(iconFg)
                        .font(.system(size: 16))
                }
                Spacer()
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(textMuted)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(valueColor ?? textPrim)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
