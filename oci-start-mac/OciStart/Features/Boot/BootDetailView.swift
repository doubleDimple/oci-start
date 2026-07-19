import SwiftUI
import AppKit

/// 开机详情整页：上半子任务卡片，下半开机日志（非弹框，对齐实例 SSH/控制台整页模式）。
struct BootDetailView: View {
    @ObservedObject var model: BootViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession

    private var dark: Bool { appearance.isDarkEffective }
    private var primaryText: Color { AppSheetSurface.primaryText(dark) }
    private var mutedText: Color { AppSheetSurface.mutedText(dark) }
    private var parent: BootTaskItem? { model.detailParent }

    var body: some View {
        PageScaffold(
            title: "开机详情",
            subtitle: detailSubtitle,
            systemImage: "list.bullet.rectangle",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                    }
                    GeometryReader { geo in
                        let logMin: CGFloat = 220
                        let detailCap = max(160, min(geo.size.height * 0.42, geo.size.height - logMin - 24))
                        VStack(spacing: 12) {
                            detailSection
                                .frame(maxWidth: .infinity, maxHeight: detailCap, alignment: .top)
                            bootLogSection
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .appLoading(model.detailLoading && model.detailItems.isEmpty)
    }

    private var detailSubtitle: String {
        guard let p = parent else { return "子任务与实时日志" }
        var parts: [String] = [p.displayTenant]
        if !p.archText.isEmpty && p.archText != "—" { parts.append(p.archText) }
        if !p.regionName.isEmpty { parts.append(p.regionName) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "返回列表", systemImage: "chevron.left", kind: .secondary) {
                model.closeDetail()
            }
            if let p = parent {
                AppButton(title: "添加配置", systemImage: "plus.circle", kind: .primary) {
                    model.openAddConfig(p)
                }
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.detailLoading
            ) {
                if let p = parent {
                    Task { await model.loadDetail(p) }
                }
            }
        }
    }

    // MARK: - Detail cards

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("子任务")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(primaryText)
                Text("\(model.detailItems.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.sidebarHover(dark).opacity(0.65))
                    .cornerRadius(6)
                Spacer(minLength: 0)
                Text("启动 · 日志 · 修改 · 删除")
                    .font(.system(size: 11))
                    .foregroundColor(mutedText)
            }

            if model.detailLoading && model.detailItems.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().scaleEffect(0.8)
                    Text("加载中…")
                        .font(.system(size: 12))
                        .foregroundColor(mutedText)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else if model.detailItems.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "暂无子任务",
                    subtitle: "该组下没有开机配置"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.detailItems) { d in
                            BootDetailCardView(
                                detail: d,
                                model: model,
                                logActive: model.bootLogActiveIdMatches(d.id)
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(dark ? 0.22 : 0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Boot log panel

    private var bootLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarActive)
                Text(bootLogHeaderTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(primaryText)
                    .lineLimit(1)

                if model.bootLogTaskId > 0 {
                    StatusBadge(
                        text: model.bootLogConnection.title,
                        tone: model.bootLogConnection == .connected ? .success
                            : (model.bootLogConnection == .connecting ? .warning : .neutral)
                    )
                    Text("TaskId = \(model.bootLogTaskId)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(mutedText)
                    if model.bootLogLoadingHistory {
                        ProgressView().scaleEffect(0.55)
                        Text("加载历史…")
                            .font(.system(size: 11))
                            .foregroundColor(mutedText)
                    }
                }

                Spacer(minLength: 0)

                if model.bootLogTaskId > 0 {
                    Toggle(isOn: $model.bootLogAutoScroll) {
                        Text("自动滚动")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(SwitchToggleStyle())
                    AppButton(title: "清空", systemImage: "trash", kind: .secondary) {
                        model.clearBootLog()
                    }
                    AppButton(title: "复制", systemImage: "doc.on.doc", kind: .secondary) {
                        model.copyBootLog()
                    }
                    AppButton(
                        title: "重连",
                        systemImage: "arrow.clockwise",
                        kind: .secondary,
                        isLoading: model.bootLogConnection == .connecting
                    ) {
                        model.reconnectBootLog()
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if model.bootLogTaskId == 0 {
                            VStack(spacing: 8) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundColor(mutedText.opacity(0.7))
                                Text("点击子任务的「开机日志」在此查看实时日志")
                                    .font(.system(size: 12))
                                    .foregroundColor(mutedText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        } else if model.bootLogLines.isEmpty && !model.bootLogLoadingHistory {
                            VStack(spacing: 8) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundColor(mutedText.opacity(0.7))
                                Text("暂无日志，等待 TaskId=\(model.bootLogTaskId) 的推送…")
                                    .font(.system(size: 12))
                                    .foregroundColor(mutedText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        } else {
                            ForEach(model.bootLogLines) { line in
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(bootLogColor(line.tone))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        Color.clear.frame(height: 1).id("boot-log-bottom")
                    }
                    .padding(10)
                }
                .background(Color.black.opacity(dark ? 0.35 : 0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.border(dark).opacity(0.45), lineWidth: 1)
                )
                .onChange(of: model.bootLogScrollToken) { _ in
                    guard model.bootLogAutoScroll else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("boot-log-bottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(dark ? 0.22 : 0.06), radius: 8, x: 0, y: 2)
    }

    private var bootLogHeaderTitle: String {
        if model.bootLogTitle.isEmpty {
            return model.bootLogTaskId > 0 ? "开机日志 · #\(model.bootLogTaskId)" : "开机日志"
        }
        return "开机日志 · \(model.bootLogTitle)"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(AppTheme.sidebarBg(dark))
    }

    private func bootLogColor(_ tone: BootLogLine.BootLogTone) -> Color {
        switch tone {
        case .success: return Color(hex: "3fb950")
        case .warn: return Color(hex: "d29922")
        case .error: return Color(hex: "f85149")
        case .normal: return primaryText
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f0881a"))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(primaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "f0881a").opacity(dark ? 0.14 : 0.1))
    }
}

// MARK: - Detail card

struct BootDetailCardView: View {
    let detail: BootDetailItem
    @ObservedObject var model: BootViewModel
    var logActive: Bool = false
    @EnvironmentObject private var appearance: AppearanceController
    @State private var showPassword = false

    private var dark: Bool { appearance.isDarkEffective }
    private var primaryText: Color { AppSheetSurface.primaryText(dark) }
    private var mutedText: Color { AppSheetSurface.mutedText(dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.osText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(primaryText)
                        .lineLimit(1)
                    Text(detail.configText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(mutedText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if logActive {
                    StatusBadge(text: "日志中", tone: .info)
                }
                StatusBadge(text: detail.statusText, tone: detail.statusTone)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                metricChip("昨日", "\(detail.yesterdayAttemptCount)")
                metricChip("今日", "\(detail.currentAttemptCount)")
                metricChip("失败", "\(detail.failCount)", accent: detail.failCount > 0 ? AppSheetSurface.accentOrange(dark) : nil)
                metricChip("间隔", "\(detail.loopTime)s")
                metricChip("时段", detail.dayGap.isEmpty ? "—" : detail.dayGap)
                passwordChip
                metricChip("创建", detail.createdAt.isEmpty ? "—" : String(detail.createdAt.prefix(16)))
                metricChip("成功", "\(detail.successCount)", accent: detail.successCount > 0 ? AppSheetSurface.accentGreen(dark) : nil)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                AppButton(
                    title: detail.status == 1 ? "停止" : "启动",
                    systemImage: detail.status == 1 ? "stop.fill" : "play.fill",
                    kind: detail.status == 1 ? .secondary : .primary
                ) {
                    model.toggleDetailStatus(detail, start: detail.status != 1)
                }
                AppButton(
                    title: logActive ? "日志中" : "开机日志",
                    systemImage: "text.alignleft",
                    kind: .secondary
                ) {
                    model.openBootLog(for: detail)
                }
                AppButton(title: "修改", systemImage: "slider.horizontal.3", kind: .secondary) {
                    model.openEditDetail(detail)
                }
                AppButton(title: "删除", systemImage: "trash", kind: .danger) {
                    model.deleteDetail(detail)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSheetSurface.surface2(dark))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    logActive ? AppTheme.sidebarActive.opacity(0.55) : AppSheetSurface.border(dark),
                    lineWidth: logActive ? 1.5 : 1
                )
        )
    }

    private var passwordChip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("密码")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(mutedText)
            HStack(spacing: 4) {
                Text(passwordDisplay)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if !detail.rootPassword.isEmpty {
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.sidebarActive)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(showPassword ? "隐藏密码" : "显示密码")
                    Button(action: { model.copyPassword(detail.rootPassword) }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.sidebarActive)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("复制密码")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppSheetSurface.panelBg(dark).opacity(0.65))
        .cornerRadius(8)
    }

    private var passwordDisplay: String {
        if detail.rootPassword.isEmpty { return "—" }
        return showPassword ? detail.rootPassword : "••••••••"
    }

    private func metricChip(_ label: String, _ value: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(mutedText)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accent ?? primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppSheetSurface.panelBg(dark).opacity(0.65))
        .cornerRadius(8)
    }
}
