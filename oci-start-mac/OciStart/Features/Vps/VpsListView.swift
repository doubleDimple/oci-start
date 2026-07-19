import SwiftUI
import AppKit

/// VPS 监控看板（对齐 Web `/vps/instances/list` · `vps_list.ftl`）
struct VpsListView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = VpsViewModel()
    @State private var hoveredCardId: String?

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        Group {
            if let ssh = model.sshItem {
                InstanceSSHView(item: ssh, onBack: { model.closeSSH() })
            } else {
                mainBoard
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear {
            FloatingMenuDismiss.all()
            model.start()
        }
        .onDisappear { model.teardown() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reload() }
        }
    }

    private var mainBoard: some View {
        PageScaffold(
            title: "VPS 监控看板",
            subtitle: "共 \(model.totalCount) 台 · 在线 \(model.onlineCount) · 离线 \(model.offlineCount)",
            systemImage: "desktopcomputer",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "f85149"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            statsRow
                            controlBar
                            cardGrid
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
        .appLoading(model.isBusy || (model.isLoading && !model.cards.isEmpty))
        .background(
            Group {
                if model.moreMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.closeMoreMenu() }
                }
            }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(
                title: model.isLatencyTesting ? "测试中…" : "延迟测试",
                systemImage: "bolt.fill",
                kind: .secondary,
                isLoading: model.isLatencyTesting
            ) { model.runLatencyTest() }
            .disabled(model.isLatencyTesting)

            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.isLoading
            ) {
                Task { await model.reload() }
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 14) {
            statCard(
                title: "服务器总数",
                value: "\(model.totalCount)",
                icon: "server.rack",
                accent: AppTheme.sidebarActive,
                active: false,
                action: nil
            )
            statCard(
                title: "在线数量",
                value: "\(model.onlineCount)",
                icon: "wifi",
                accent: Color(hex: "10b981"),
                active: false,
                action: nil
            )
            statCard(
                title: "离线数量",
                value: "\(model.offlineCount)",
                icon: "heart.slash",
                accent: Color(hex: "ef4444"),
                active: model.offlineOnly,
                action: { model.toggleOfflineFilter() }
            )
        }
    }

    private func statCard(
        title: String,
        value: String,
        icon: String,
        accent: Color,
        active: Bool,
        action: (() -> Void)?
    ) -> some View {
        let content = HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.sidebarText(dark))
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
            }
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(accent.opacity(0.35))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.sidebarBg(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    active ? Color(hex: "ef4444") : AppTheme.border(dark).opacity(0.55),
                    lineWidth: active ? 1.5 : 1
                )
        )
        .background(
            active
                ? RoundedRectangle(cornerRadius: 12).fill(Color(hex: "ef4444").opacity(0.08))
                : nil
        )

        return Group {
            if let action = action {
                Button(action: action) { content }
                    .buttonStyle(PlainButtonStyle())
            } else {
                content
            }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(AppTheme.sidebarActive)
                Text("监控面板")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
            }
            Spacer(minLength: 8)
            SearchField(text: $model.searchText, placeholder: "搜索 IP、地区、租户…")
                .frame(width: 240)
            toolChip(
                title: model.showIP ? "隐藏 IP" : "显示 IP",
                systemImage: model.showIP ? "eye.slash" : "eye",
                active: model.showIP
            ) { model.toggleShowIP() }
            toolChip(
                title: model.showTenant ? "隐藏租户" : "显示租户",
                systemImage: model.showTenant ? "eye.slash" : "eye",
                active: model.showTenant
            ) { model.toggleShowTenant() }
            moreMenu
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.sidebarBg(dark).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border(dark).opacity(0.45), lineWidth: 1)
        )
        .zIndex(2)
    }

    private func toolChip(
        title: String,
        systemImage: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundColor(active ? AppTheme.sidebarActive : AppTheme.sidebarText(dark))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active
                          ? AppTheme.sidebarActive.opacity(0.14)
                          : (dark ? Color(hex: "2c3136") : Color(hex: "eef2f6")))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(active ? AppTheme.sidebarActive.opacity(0.4) : AppTheme.border(dark).opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var moreMenu: some View {
        ZStack(alignment: .topTrailing) {
            toolChip(title: "更多操作", systemImage: "gearshape", active: model.moreMenuOpen) {
                model.toggleMoreMenu()
            }
            if model.moreMenuOpen {
                VStack(alignment: .leading, spacing: 2) {
                    moreItem("开启自动 Ping", "play.fill", Color(hex: "10b981")) { model.enablePing() }
                    moreItem("停止自动 Ping", "stop.fill", Color(hex: "ef4444")) { model.disablePing() }
                    moreItem("手动 Ping 检测", "scope", AppTheme.sidebarActive) { model.manualPing() }
                    Divider().opacity(0.4)
                    moreItem("刷新列表", "arrow.clockwise", AppTheme.sidebarText(dark)) {
                        model.closeMoreMenu()
                        Task { await model.reload() }
                    }
                }
                .padding(8)
                .frame(width: 180, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.sidebarBg(dark))
                        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1)
                )
                .offset(y: 36)
            }
        }
    }

    private func moreItem(
        _ title: String,
        _ icon: String,
        _ color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Grid

    private var cardGrid: some View {
        Group {
            if model.isLoading && model.cards.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if model.filteredCards.isEmpty {
                EmptyStateView(
                    icon: "desktopcomputer",
                    title: "暂无实例",
                    subtitle: model.searchText.isEmpty && !model.offlineOnly
                        ? "没有 VPS 实例数据"
                        : "无匹配结果",
                    actionTitle: "刷新",
                    action: { Task { await model.reload() } }
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(model.filteredCards) { card in
                        VpsServerCard(
                            card: card,
                            showIP: model.showIP,
                            showTenant: model.showTenant,
                            dark: dark,
                            hovered: hoveredCardId == card.id,
                            onHover: { inside in
                                hoveredCardId = inside ? card.id : (hoveredCardId == card.id ? nil : hoveredCardId)
                            },
                            onCopyIP: { model.copyIP(card) },
                            onSSH: { model.openSSH(card) },
                            onInstall: { model.installMonitor(card) },
                            onUninstall: { model.uninstallMonitor(card) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Server card

private struct VpsServerCard: View {
    let card: VpsCardItem
    let showIP: Bool
    let showTenant: Bool
    let dark: Bool
    let hovered: Bool
    let onHover: (Bool) -> Void
    let onCopyIP: () -> Void
    let onSSH: () -> Void
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardBody
            Divider().opacity(0.4)
            cardActions
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.sidebarBg(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    card.monitorWarning
                        ? Color(hex: "f59e0b").opacity(0.75)
                        : (hovered ? AppTheme.sidebarActive.opacity(0.45) : AppTheme.border(dark).opacity(0.55)),
                    lineWidth: card.monitorWarning || hovered ? 1.5 : 1
                )
        )
        .shadow(color: Color.black.opacity(hovered ? (dark ? 0.28 : 0.08) : 0.04), radius: hovered ? 10 : 3, y: 2)
        .scaleEffect(hovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .onHover(perform: onHover)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                cloudIcon
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: onCopyIP) {
                        HStack(spacing: 6) {
                            Text(showIP ? card.displayIP : card.maskedIP)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                                .lineLimit(1)
                            Image(systemName: showIP ? "eye" : "eye.slash")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.sidebarText(dark))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("点击复制 IP")

                    tagsRow
                }
                Spacer(minLength: 4)
                StatusBadge(
                    text: card.isOnline ? "在线" : "离线",
                    tone: card.isOnline ? .success : .danger
                )
            }
            metricsBlock
        }
        .padding(14)
    }

    private var cloudIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.sidebarHover(dark).opacity(0.9))
                .frame(width: 40, height: 40)
            Image(systemName: cloudSF)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppTheme.sidebarActive)
        }
    }

    private var cloudSF: String {
        switch card.item.cloudType {
        case 2: return "g.circle.fill"
        case 4: return "cloud.fill"
        default: return "server.rack"
        }
    }

    private var tagsRow: some View {
        FlowWrap(spacing: 6) {
            tag(card.item.regionName.isEmpty ? "—" : card.item.regionName, icon: "mappin.and.ellipse")
            archTag
            tag(card.specText, icon: nil)
            tag(
                showTenant
                    ? (card.item.tenancyName.isEmpty ? "—" : card.item.tenancyName)
                    : card.item.maskedTenancyName,
                icon: "person"
            )
            if !card.metrics.uptime.isEmpty {
                tag(card.metrics.uptime, icon: "clock")
            }
            if !card.metrics.load.isEmpty {
                tag("负载 \(card.metrics.load)", icon: "gauge")
            }
            if card.isLatencyTesting {
                tag("延迟 …", icon: "bolt")
            } else if let ms = card.latencyMs {
                latencyTag(ms)
            }
        }
    }

    private var archTag: some View {
        let a = card.item.architecture.isEmpty ? "NONE" : card.item.architecture
        let color: Color = {
            switch card.archClass {
            case "arm": return Color(hex: "a78bfa")
            case "amd": return Color(hex: "60a5fa")
            default: return AppTheme.sidebarText(dark)
            }
        }()
        return Text(a)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
    }

    private func latencyTag(_ ms: Int) -> some View {
        let color: Color = {
            if ms < 0 { return Color(hex: "ef4444") }
            if ms < 150 { return Color(hex: "10b981") }
            if ms < 300 { return Color(hex: "f59e0b") }
            return Color(hex: "ef4444")
        }()
        return tag(VpsFormat.latencyLabel(ms), icon: "bolt.fill", color: color)
    }

    private func tag(_ text: String, icon: String?, color: Color? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(color ?? AppTheme.sidebarText(dark))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        )
    }

    private var metricsBlock: some View {
        VStack(spacing: 8) {
            metricRow("CPU", card.metrics.cpuPercent, Color(hex: "10b981"))
            metricRow("内存", card.metrics.memPercent, AppTheme.sidebarActive)
            metricRow(
                "硬盘\(card.metrics.diskTotalLabel.isEmpty ? "" : " (\(card.metrics.diskTotalLabel))")",
                card.metrics.diskPercent,
                Color(hex: "8b5cf6")
            )
            HStack(spacing: 14) {
                Label(card.metrics.netRx, systemImage: "arrow.down")
                    .foregroundColor(Color(hex: "10b981"))
                Label(card.metrics.netTx, systemImage: "arrow.up")
                    .foregroundColor(Color(hex: "f59e0b"))
                Spacer()
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(dark ? Color.black.opacity(0.22) : Color(hex: "f3f4f6").opacity(0.9))
        )
    }

    private func metricRow(_ title: String, _ percent: Double, _ color: Color) -> some View {
        let p = min(100, max(0, percent))
        let barColor: Color = {
            if p > 90 { return Color(hex: "ef4444") }
            if p > 70 { return Color(hex: "f59e0b") }
            return color
        }()
        return VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
                Spacer()
                Text(String(format: "%.0f%%", p))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(dark ? Color.white.opacity(0.85) : Color.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * CGFloat(p / 100)))
                        .animation(.easeInOut(duration: 0.25), value: p)
                }
            }
            .frame(height: 6)
        }
    }

    private var cardActions: some View {
        HStack(spacing: 8) {
            AppButton(title: "SSH", systemImage: "terminal", kind: .secondary) { onSSH() }
            if !card.item.monitorInstalled {
                AppButton(title: "安装", systemImage: "arrow.down.circle", kind: .primary) { onInstall() }
            }
            AppButton(title: "卸载", systemImage: "trash", kind: .danger) { onUninstall() }
            Spacer()
            if card.monitorWarning {
                Text("探针超时")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "f59e0b"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Simple flow layout for tags

private struct FlowWrap<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        // macOS 11+: use flexible wrapping via LazyVGrid single-line-ish
        // Prefer left-aligned chip wrap with PreferenceKey-free adaptive grid
        _FlowLayout(spacing: spacing, content: content)
    }
}

/// Lightweight wrap layout (macOS 12+ Layout protocol avoided for 11 compatibility)
private struct _FlowLayout<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Fallback: horizontal scroll if too many tags (smooth, no clip)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content()
            }
        }
    }
}
