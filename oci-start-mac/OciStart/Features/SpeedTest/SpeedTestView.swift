import SwiftUI

/// 全球链路监控（对齐 Web `speed_test.ftl`，UI 对齐 `IpQualityView` 基准）。
struct SpeedTestView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = SpeedTestViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    private let regionColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 360), spacing: 14)
    ]

    var body: some View {
        PageScaffold(
            title: "全球链路监控",
            subtitle: "出口 IP · 区域延迟探测 · Top5 优选",
            systemImage: "globe",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let err = model.errorText, !err.isEmpty {
                            errorBanner(err)
                        }

                        statsRow

                        if !model.top5.isEmpty {
                            rankSection
                        }

                        regionSection
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.isLoadingRegions && model.regions.isEmpty)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.refresh() }
        }
        .environmentObject(appearance)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.isLoadingRegions && !model.isTesting
            ) {
                Task { await model.refresh() }
            }
            AppButton(
                title: model.isTesting ? "测速中…" : "开始测速",
                systemImage: "bolt.fill",
                kind: .primary,
                isLoading: model.isTesting,
                enabled: !model.regions.isEmpty
            ) {
                Task { await model.runTest() }
            }
        }
    }

    // MARK: - Error

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            AppButton(title: "重试", kind: .secondary) {
                Task { await model.refresh() }
            }
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "f85149").opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Stats（三等宽紧凑指标卡，避免 2fr 大空白）

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 14) {
            metricCard(
                label: "当前出口 IP",
                value: model.clientIPText,
                systemImage: "network",
                accent: Color(hex: "4a9eff")
            )
            metricCard(
                label: "最优区域",
                value: model.bestRegionText,
                systemImage: "trophy.fill",
                accent: Color(hex: "f0b429")
            )
            metricCard(
                label: "平均延迟",
                value: model.avgLatencyText,
                systemImage: "stopwatch",
                accent: AppTheme.sidebarActive
            )
        }
    }

    private func metricCard(label: String, value: String, systemImage: String, accent: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(AppTheme.sidebarBg(dark))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border(dark).opacity(0.7), lineWidth: 1)
        )
    }

    // MARK: - Top5

    private var rankSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SpeedTestTheme.success)
                Text("延迟 Top 5（< 150ms）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                Spacer(minLength: 0)
                Text("\(model.top5.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppTheme.sidebarHover(dark))
                    .cornerRadius(8)
            }

            // 用自适应流式布局，避免单行 Spacer 撑出空洞
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120, maximum: 220), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Array(model.top5.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 6) {
                        Text("#\(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(SpeedTestTheme.success.opacity(0.85))
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("\(item.ms)ms")
                            .font(Font.system(size: 12, weight: .bold).monospacedDigit())
                    }
                    .foregroundColor(SpeedTestTheme.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SpeedTestTheme.success.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(SpeedTestTheme.success.opacity(0.45), lineWidth: 1)
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.sidebarBg(dark))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border(dark).opacity(0.7), lineWidth: 1)
        )
    }

    // MARK: - Regions

    private var regionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("区域节点")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                Text("\(model.regions.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppTheme.sidebarHover(dark))
                    .cornerRadius(8)
                if model.isTesting {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.55)
                        Text("探测中")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    }
                }
                Spacer(minLength: 0)
            }

            if model.regions.isEmpty && !model.isLoadingRegions {
                EmptyStateView(
                    icon: "globe",
                    title: "暂无区域节点",
                    subtitle: "无法加载 Oracle 区域 endpoint，请检查后端连接",
                    actionTitle: "重新加载",
                    action: { Task { await model.refresh() } }
                )
                .frame(minHeight: 180)
                .background(AppTheme.sidebarBg(dark))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border(dark).opacity(0.7), lineWidth: 1)
                )
            } else {
                LazyVGrid(columns: regionColumns, spacing: 14) {
                    ForEach(model.regions) { region in
                        regionCard(region)
                    }
                }
            }
        }
    }

    private func regionCard(_ region: SpeedRegionEndpoint) -> some View {
        let state = model.latency[region.code] ?? .idle
        let tone: SpeedLatencyTone = {
            if case .ok(let ms) = state { return SpeedLatencyTone.from(ms: ms) }
            return .neutral
        }()
        let barFraction: CGFloat = {
            if case .ok(let ms) = state {
                if ms < 500 { return CGFloat(max(0.06, 1.0 - Double(ms) / 500.0)) }
                return 0.06
            }
            return 0
        }()
        let testing = state == .testing

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(region.simpleName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(region.code)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.sidebarHover(dark))
                    .cornerRadius(6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Group {
                    if testing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 22, height: 22)
                    } else {
                        Text(state.displayText)
                            .font(Font.system(size: state == .timeout ? 15 : 26, weight: .bold).monospacedDigit())
                            .foregroundColor(
                                state == .timeout
                                    ? AppTheme.sidebarText(dark)
                                    : SpeedTestTheme.toneColor(tone, dark: dark)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                if case .ok = state {
                    Text("ms")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.sidebarText(dark))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 32, alignment: .bottomLeading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SpeedTestTheme.progressTrack(dark))
                        .frame(height: 5)
                    Capsule()
                        .fill(barColor(tone: tone, testing: testing))
                        .frame(width: max(0, geo.size.width * barFraction), height: 5)
                        .animation(.easeOut(duration: 0.4), value: barFraction)
                }
            }
            .frame(height: 5)
        }
        .padding(14)
        .background(AppTheme.sidebarBg(dark))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    testing ? AppTheme.sidebarActive.opacity(0.85) : AppTheme.border(dark).opacity(0.7),
                    lineWidth: testing ? 1.5 : 1
                )
        )
        .shadow(color: Color.black.opacity(dark ? 0.18 : 0.04), radius: 3, y: 1)
        .animation(.easeInOut(duration: 0.18), value: testing)
    }

    private func barColor(tone: SpeedLatencyTone, testing: Bool) -> Color {
        if testing { return AppTheme.sidebarActive.opacity(0.35) }
        switch tone {
        case .fast: return SpeedTestTheme.success
        case .mid: return SpeedTestTheme.warning
        case .slow: return SpeedTestTheme.danger
        case .neutral: return AppTheme.sidebarActive.opacity(0.35)
        }
    }
}
