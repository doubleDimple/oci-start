import SwiftUI

/// Web-parity 延迟测试 page (`speed_test.ftl` + `speed_test.css`).
struct SpeedTestView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = SpeedTestViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader

                if let err = model.errorText, !err.isEmpty {
                    errorBanner(err)
                }

                statsRow

                if !model.top5.isEmpty {
                    rankSection
                }

                controlBar

                if model.isLoadingRegions && model.regions.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("loading...")
                            .font(.system(size: 13))
                            .foregroundColor(SpeedTestTheme.muted(dark))
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.regions) { region in
                            regionCard(region)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SpeedTestTheme.bg(dark).ignoresSafeArea())
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.refresh() }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(SpeedTestTheme.primary(dark))
            Text("全球链路监控")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(SpeedTestTheme.text(dark))
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.refresh() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(SpeedTestTheme.danger)
        .padding(12)
        .background(SpeedTestTheme.danger.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Stats (web .dashboard-header)

    private var statsRow: some View {
        // web: grid 2fr 1fr 1fr
        HStack(alignment: .top, spacing: 16) {
            statusCard(label: "当前出口 IP", value: model.clientIPText, icon: "network")
                .frame(maxWidth: .infinity)
                .frame(minWidth: 0)
                .layoutPriority(2)
            statusCard(label: "最优区域", value: model.bestRegionText, icon: "trophy.fill")
                .frame(maxWidth: .infinity)
                .frame(minWidth: 0)
            statusCard(label: "平均延迟", value: model.avgLatencyText, icon: "stopwatch")
                .frame(maxWidth: .infinity)
                .frame(minWidth: 0)
        }
    }

    private func statusCard(label: String, value: String, icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SpeedTestTheme.muted(dark))
                    .tracking(0.5)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(SpeedTestTheme.text(dark))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(SpeedTestTheme.primary(dark).opacity(0.12))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SpeedTestTheme.surface2(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SpeedTestTheme.border(dark), lineWidth: 1)
        )
    }

    // MARK: - Top5 (web .rank-section)

    private var rankSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "medal.fill")
                    .foregroundColor(SpeedTestTheme.success)
                Text("延迟 Top 5（< 150ms）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SpeedTestTheme.muted(dark))
            }
            HStack(spacing: 10) {
                ForEach(model.top5) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text(item.name)
                        Text("\(item.ms)ms")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SpeedTestTheme.success)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(SpeedTestTheme.success.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(SpeedTestTheme.success, lineWidth: 1)
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SpeedTestTheme.surface2(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SpeedTestTheme.border(dark), lineWidth: 1)
        )
    }

    // MARK: - Control

    private var controlBar: some View {
        HStack {
            Spacer()
            Button(action: {
                Task { await model.runTest() }
            }) {
                HStack(spacing: 6) {
                    if model.isTesting {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(model.isTesting ? "测速中…" : "开始测速")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(SpeedTestTheme.primary(dark))
                .cornerRadius(6)
                .shadow(color: SpeedTestTheme.primary(dark).opacity(0.28), radius: 6, y: 3)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(model.isTesting || model.regions.isEmpty)
            .opacity(model.isTesting || model.regions.isEmpty ? 0.6 : 1)
        }
    }

    // MARK: - Region card (web .region-node)

    private func regionCard(_ region: SpeedRegionEndpoint) -> some View {
        let state = model.latency[region.code] ?? .idle
        let tone: SpeedLatencyTone = {
            if case .ok(let ms) = state { return SpeedLatencyTone.from(ms: ms) }
            return .neutral
        }()
        let barFraction: CGFloat = {
            if case .ok(let ms) = state {
                if ms < 500 { return CGFloat(max(0.05, 1.0 - Double(ms) / 500.0)) }
                return 0.05
            }
            return 0
        }()
        let testing = state == .testing

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(region.simpleName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SpeedTestTheme.text(dark))
                    .lineLimit(1)
                Spacer()
                Text(region.code)
                    .font(.system(size: 11))
                    .foregroundColor(SpeedTestTheme.muted(dark))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(SpeedTestTheme.nodeCodeBg(dark))
                    )
                    .overlay(
                        Capsule()
                            .stroke(SpeedTestTheme.border(dark), lineWidth: 1)
                    )
            }

            HStack(alignment: .bottom, spacing: 4) {
                Text(state.displayText)
                    .font(.system(size: state == .timeout ? 16 : 28, weight: .heavy))
                    .foregroundColor(
                        state == .timeout
                            ? SpeedTestTheme.muted(dark)
                            : SpeedTestTheme.toneColor(tone, dark: dark)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if case .ok = state {
                    Text("ms")
                        .font(.system(size: 12))
                        .foregroundColor(SpeedTestTheme.muted(dark))
                        .padding(.bottom, 4)
                }
                Spacer()
            }
            .frame(height: 36, alignment: .bottomLeading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SpeedTestTheme.progressTrack(dark))
                        .frame(height: 6)
                    Capsule()
                        .fill(barColor(tone: tone))
                        .frame(width: max(0, geo.size.width * barFraction), height: 6)
                        .animation(.easeOut(duration: 0.45), value: barFraction)
                }
            }
            .frame(height: 6)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(SpeedTestTheme.surface2(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    testing ? SpeedTestTheme.primary(dark) : SpeedTestTheme.border(dark),
                    lineWidth: testing ? 1.5 : 1
                )
        )
        .shadow(color: Color.black.opacity(dark ? 0.25 : 0.05), radius: 3, y: 1)
    }

    private func barColor(tone: SpeedLatencyTone) -> Color {
        switch tone {
        case .fast: return SpeedTestTheme.success
        case .mid: return SpeedTestTheme.warning
        case .slow: return SpeedTestTheme.danger
        case .neutral: return SpeedTestTheme.primary(dark)
        }
    }
}
