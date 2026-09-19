import SwiftUI
import AppKit

/// Content-only top bar aligned with the Vue console.
/// Dropdown panels are rendered by `TopNavDropdownOverlay` (in-window), not system popover.
struct TopNavView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var navigation: NavigationState
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var header: HeaderViewModel
    @EnvironmentObject private var chrome: TopNavChromeState
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredTool: String?
    @State private var showThemePreferences = false
    @ObservedObject private var language = LanguageManager.shared

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                sidebarToggle
                SearchField(
                    text: $navigation.searchText,
                    placeholder: language.text("搜索并打开页面…", "Find and open a page…"),
                    onSubmit: openSelectedSearchResult,
                    maxWidth: 320,
                    onMoveSelection: { step in
                        guard !navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        chrome.moveSearchSelection(step, count: searchResults.count)
                    },
                    onCancel: { navigation.searchText = ""; chrome.close() },
                    onFocusChange: { focused in
                        if focused && !navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chrome.open = .search }
                        else if !focused && NSApp.currentEvent?.type == .keyDown { chrome.close() }
                    },
                    onClear: { chrome.focusSearch() },
                    focusRequest: chrome.searchFocusRequest,
                    blurRequest: chrome.searchBlurRequest,
                    shortcutHint: "⌘K"
                )
                .accessibilityLabel(language.text("搜索菜单", "Search menu"))
            }

            Spacer(minLength: 12)

            trailingActions
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: AppTheme.topBarHeight)
        .background(AppTheme.cardBg(dark))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.8)),
            alignment: .bottom
        )
        .onAppear { header.start() }
        .onDisappear { header.stop() }
        .onChange(of: navigation.searchText) { query in
            chrome.searchActiveIndex = 0
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                header.closeMessages()
                chrome.open = .search
            } else if chrome.open == .search { chrome.close() }
        }
        .onChange(of: language.locale) { _ in chrome.searchActiveIndex = 0 }
        // 消息中心改为右侧滑出抽屉（见 TopNavDropdownOverlay），不再用居中 sheet
        .sheet(isPresented: $showThemePreferences) {
            ThemePreferencesView(onClose: { showThemePreferences = false })
                .environmentObject(appearance)
        }
        .sheet(isPresented: $header.showAsset) {
            AssetAnalysisSheet(header: header, dark: dark)
                .environmentObject(appearance)
        }
        .sheet(isPresented: $header.showAbout) {
            AboutSheet(header: header, dark: dark)
                .environmentObject(appearance)
                .environmentObject(session)
        }
        .sheet(isPresented: $header.showUpdateProgress) {
            VersionUpdateProgressSheet(header: header, dark: dark)
                .environmentObject(appearance)
        }
    }

    // MARK: - Left

    private var sidebarToggle: some View {
        Button(action: {
            chrome.close()
            navigation.sidebarCollapsed.toggle()
        }) {
            Image(systemName: "sidebar.left")
                .font(.system(size: AppTheme.bodySize, weight: .semibold))
                .foregroundColor(AppTheme.navIcon(dark))
                .frame(width: 36, height: 36)
                .background(circleBg(highlight: navigation.sidebarCollapsed, tool: "sidebar"))
        }
        .buttonStyle(PlainButtonStyle())
        .help(navigation.sidebarCollapsed ? "展开侧栏（⌘⌥S）" : "收起侧栏（⌘⌥S）")
        .onHover { hoveredTool = $0 ? "sidebar" : nil }
    }

    // MARK: - Right

    private var trailingActions: some View {
        HStack(spacing: 8) {
            if header.version.needUpdate {
                updateButton
            }

            iconButton(
                systemName: themeIcon,
                help: language.text("外观模式", "Appearance mode") + " · \(appearance.mode.title)（⌘T）"
            ) {
                header.closeMessages()
                chrome.toggle(.appearance)
            }

            iconButton(systemName: "paintpalette", help: language.text("主题配色", "Theme colors")) {
                chrome.close()
                header.closeMessages()
                showThemePreferences = true
            }

            languageButton
            messageButton

            iconButton(systemName: "arrow.clockwise", help: language.text("刷新（⌘R）", "Refresh (⌘R)")) {
                chrome.close()
                NotificationCenter.default.post(name: .ociReloadCurrentPage, object: nil)
            }

            userButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var updateButton: some View {
        Button(action: {
            chrome.close()
            header.requestUpdate()
        }) {
            HStack(spacing: 5) {
                Image(systemName: header.updatePhase.isActive ? "arrow.triangle.2.circlepath" : "arrow.up.circle.fill")
                Text(header.updatePhase.isActive
                     ? "升级中…"
                     : "Mac 新版本")
                    .font(.system(size: AppTheme.secondarySize, weight: .semibold))
            }
            .foregroundColor(AppTheme.brand(dark))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppTheme.brand(dark).opacity(0.1))
            )
            .overlay(
                Capsule().stroke(AppTheme.brand(dark).opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(header.updatePhase.isActive)
        .help("下载 Mac \(header.version.latestDisplay) 安装包（DMG），替换应用程序后重启")
    }

    private var languageButton: some View {
        Button(action: {
            header.closeMessages()
            chrome.toggle(.language)
        }) {
            Image(systemName: "globe")
                .font(.system(size: AppTheme.bodySize, weight: .medium))
                .foregroundColor(AppTheme.navIcon(dark))
                .frame(width: 36, height: 36)
                .background(circleBg(highlight: chrome.open == .language, tool: "language"))
        }
        .buttonStyle(PlainButtonStyle())
        .help(language.text("语言", "Language"))
        .accessibilityLabel(language.text("语言", "Language"))
        .onHover { hoveredTool = $0 ? "language" : nil }
    }

    private var messageButton: some View {
        Button(action: {
            chrome.close()
            header.toggleMessages()
        }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: AppTheme.bodySize, weight: .medium))
                    .foregroundColor(AppTheme.navIcon(dark))
                    .frame(width: 36, height: 36)
                    .background(circleBg(highlight: header.showMessages, tool: "messages"))
                if header.unreadError != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12)).foregroundColor(AppTheme.warning(dark))
                } else if header.unreadCount > 0 {
                    Text(header.unreadCount > 99 ? "99+" : "\(header.unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(AppTheme.danger))
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .help(header.unreadError ?? language.text("消息中心", "Messages"))
        .accessibilityLabel(language.text("消息中心", "Messages"))
        .onHover { hoveredTool = $0 ? "messages" : nil }
    }

    private var userButton: some View {
        Button(action: {
            header.closeMessages()
            chrome.toggle(.user)
        }) {
            HStack(spacing: 6) {
                NativeUserAvatar(name: session.username, dark: dark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.username.isEmpty ? language.text("当前用户", "Current user") : session.username)
                        .font(.system(size: AppTheme.bodySize, weight: .semibold))
                        .lineLimit(1)
                    Text("Oracle Cloud")
                        .font(.system(size: AppTheme.secondarySize))
                }
                .foregroundColor(AppTheme.textPrimary(dark))
                .frame(maxWidth: 140, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary(dark))
                    .rotationEffect(.degrees(chrome.open == .user ? 180 : 0))
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(
                Capsule()
                    .fill(chrome.open == .user || hoveredTool == "user" ? AppTheme.hover(dark) : .clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("账户：\(session.username.isEmpty ? "Admin" : session.username)")
        .accessibilityLabel("账户菜单")
        .onHover { hoveredTool = $0 ? "user" : nil }
    }

    private var themeIcon: String {
        switch appearance.mode {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .system: return "desktopcomputer"
        }
    }

    private var searchResults: [NavigationItem] {
        guard !navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return NavigationCatalog.filtered(search: navigation.searchText, cloudType: 1).flatMap { $0.1 }
    }

    private func openSelectedSearchResult() {
        let results = searchResults
        guard !results.isEmpty else { return }
        let result = results[min(max(0, chrome.searchActiveIndex), results.count - 1)]
        navigation.select(result.nav)
        navigation.searchText = ""
        chrome.close()
        chrome.blurSearch()
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: AppTheme.bodySize, weight: .medium))
                .foregroundColor(AppTheme.navIcon(dark))
                .frame(width: 36, height: 36)
                .background(circleBg(highlight: false, tool: systemName))
        }
        .buttonStyle(PlainButtonStyle())
        .help(help)
        .accessibilityLabel(help)
        .onHover { hoveredTool = $0 ? systemName : nil }
    }

    private func circleBg(highlight: Bool, tool: String) -> some View {
        Circle()
            .fill(
                highlight
                    ? AppTheme.brand(dark).opacity(0.12)
                    : (hoveredTool == tool ? AppTheme.hover(dark) : Color.clear)
            )
    }
}

// MARK: - User dropdown panel (web structure)

struct UserDropdownPanel: View {
    var dark: Bool
    var username: String
    var levelTitle: String
    var level: Int
    var cloudProvider: Int
    var onAsset: () -> Void
    var onAuditLogs: () -> Void
    var onAbout: () -> Void
    var onLogout: () -> Void
    @State private var hoveredRow: String?
    @ObservedObject private var language = LanguageManager.shared

    private var welcome: String {
        username.isEmpty ? language.text("当前用户", "Current user") : username
    }

    private var levelName: String {
        levelTitle.isEmpty ? AssetAnalysis.levelConfig(level).name : levelTitle
    }

    private var textPrimary: Color {
        AppTheme.textPrimary(dark)
    }

    private var textMuted: Color {
        AppTheme.textMuted(dark)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topPart
            bottomPart
        }
        .padding(.bottom, 6)
        .frame(width: 240)
        .background(AppTheme.cardBg(dark))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border(dark), lineWidth: 1)
        )
    }

    private var topPart: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock
            thinLine
            menuRow(icon: "chart.pie.fill", color: AppTheme.brand(dark), title: language.text("OCI 资产报告", "OCI asset report"), action: onAsset)
            menuRow(icon: "checkmark.shield", color: textMuted, title: language.text("审计日志", "Audit logs"), action: onAuditLogs)
            thinLine
        }
    }

    private var bottomPart: some View {
        VStack(alignment: .leading, spacing: 0) {
            thinLine
            menuRow(icon: "info.circle", color: textMuted, title: language.text("关于 OCI Start", "About OCI Start"), action: onAbout)
            menuRow(icon: "arrow.right.square", color: AppTheme.danger, title: language.text("退出登录", "Sign out"), action: onLogout)
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(welcome)
                .font(.system(size: AppTheme.bodySize, weight: .semibold))
                .foregroundColor(textPrimary)
            Text("Oracle Cloud")
                .font(.system(size: AppTheme.secondarySize, weight: .medium))
                .foregroundColor(AppTheme.brand(dark))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(AppTheme.brand(dark).opacity(0.18)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var thinLine: some View {
        Rectangle()
            .fill(AppTheme.border(dark))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.secondarySize, weight: .semibold))
            .foregroundColor(textMuted)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func cloudLabel(_ type: Int, _ name: String) -> String {
        cloudProvider == type ? "✓  \(name)" : name
    }

    private func checkColor(_ type: Int) -> Color {
        cloudProvider == type ? AppTheme.sidebarActive : textMuted
    }

    private func menuRow(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundColor(color)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: AppTheme.bodySize))
                    .foregroundColor(textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(hoveredRow == title ? AppTheme.hover(dark) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hoveredRow = $0 ? title : nil }
    }
}

// MARK: - Asset analysis

private struct AssetAnalysisSheet: View {
    @ObservedObject var header: HeaderViewModel
    var dark: Bool
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("云资产报告")
                    .font(.system(size: AppTheme.dialogTitleSize, weight: .semibold))
                Spacer()
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)

            if header.assetLoading {
                Spacer()
                HStack { Spacer(); ProgressView("加载中…"); Spacer() }
                Spacer()
            } else if let err = header.assetError {
                Spacer()
                Text(err).foregroundColor(.red).padding()
                Button("重试") { Task { await header.loadAsset() } }
                    .padding()
                Spacer()
            } else if let a = header.asset {
                let lvl = a.computedLevel
                let cfg = AssetAnalysis.levelConfig(lvl)
                HStack(alignment: .center, spacing: 0) {
                    VStack(spacing: 10) {
                        Text("ACCOUNT LEVEL")
                            .font(.system(size: AppTheme.captionSize, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary(dark))
                        HStack(spacing: 6) {
                            Image(systemName: cfg.icon)
                            Text(a.levelTitle.isEmpty ? cfg.name : a.levelTitle)
                                .font(.system(size: AppTheme.bodySize, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AppTheme.brand(dark).opacity(0.2)))
                        Text("Scale: Lvl.\(lvl)")
                            .font(.system(size: AppTheme.secondarySize))
                            .foregroundColor(AppTheme.textSecondary(dark))
                    }
                    .frame(width: 180)
                    .padding(16)
                    .background(AppTheme.inputBg(dark))

                    HStack(spacing: 0) {
                        metric("账号总数", "\(a.totalCount)", nil)
                        metric("升级账号", "\(a.upgradeCount)", AppTheme.info)
                        metric("免费额度", "\(a.freeCount)", nil)
                        metric("账户费用", a.totalCost, AppTheme.brand(dark))
                    }
                    .frame(maxWidth: .infinity)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border(dark), lineWidth: 1)
                )
                .cornerRadius(8)
                .padding(16)

                Spacer()
                HStack {
                    Spacer()
                    Button("关闭报告") { presentationMode.wrappedValue.dismiss() }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.sidebarActive))
                        .foregroundColor(.white)
                }
                .padding(16)
            } else {
                Spacer()
                Text("暂无数据").padding()
                Spacer()
            }
        }
        .frame(width: 720, height: 360)
        .background(AppTheme.cardBg(dark))
    }

    private func metric(_ title: String, _ value: String, _ color: Color?) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: AppTheme.captionSize))
                .foregroundColor(AppTheme.textSecondary(dark))
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(color ?? AppTheme.textPrimary(dark))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - About（Mac 客户端版本，不走 Web jar 更新）

private struct AboutSheet: View {
    @ObservedObject var header: HeaderViewModel
    var dark: Bool
    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var copied = false
    @State private var zoomImage: NSImage?

    private let trc20 = "TMHTdWVm6ThvhihWqM1ViSDKMMsGcCBHtT"
    private let githubURL = "https://github.com/doubleDimple/oci-start"
    private let telegramURL = "https://t.me/+M7XhteVCMMU5ZDhh"
    private let releasesURL = "https://github.com/doubleDimple/oci-start/releases"

    private var currentVersion: String {
        header.version.currentDisplay
    }

    private var latestVersion: String {
        header.version.latestDisplay
    }

    private var surface: Color { AppTheme.cardBg(dark) }
    private var surface2: Color { AppTheme.inputBg(dark) }
    private var border: Color { AppTheme.border(dark) }
    private var textPrimary: Color { AppTheme.textPrimary(dark) }
    private var textMuted: Color { AppTheme.textMuted(dark) }
    private var textSecondary: Color { AppTheme.textSecondary(dark) }
    private var donateBg: Color { AppTheme.pageBg(dark) }
    private var cardBg: Color { AppTheme.cardBg(dark) }
    private var pillBg: Color { AppTheme.hover(dark) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topSection
                linksRow
                donateSection
            }
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(border.opacity(0.9), lineWidth: 1)
            )

            // close button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: AppTheme.bodySize, weight: .semibold))
                            .foregroundColor(textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(AppTheme.hover(dark)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("关闭")
                    .padding(16)
                }
                Spacer()
            }

            if let img = zoomImage {
                Color.black.opacity(0.88)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { zoomImage = nil }
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 420, maxHeight: 420)
                    .cornerRadius(12)
                    .onTapGesture { zoomImage = nil }
                    .help("点击关闭预览")
            }
        }
        .frame(width: 720, height: 510)
        .background(surface)
        .onAppear {
            Task { await header.checkVersion() }
        }
    }

    // MARK: Top — brand + version

    private var topSection: some View {
        HStack(alignment: .center, spacing: 28) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    AppTheme.brand(dark).opacity(0.16),
                                    AppTheme.brand(dark).opacity(0.08)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(AppTheme.brand(dark))
                }
                .frame(width: 64, height: 64)
                .shadow(color: AppTheme.brand(dark).opacity(0.25), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Oci-Start")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(textPrimary)
                    Text("Created by doubleDimple")
                        .font(.system(size: AppTheme.secondarySize))
                        .foregroundColor(textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 0) {
                    versionItem(label: "当前 Mac", value: currentVersion, showTag: true)
                    Rectangle()
                        .fill(AppTheme.border(dark))
                        .frame(width: 1, height: 36)
                        .padding(.horizontal, 18)
                    versionItem(label: "最新 Mac", value: latestVersion, showTag: false)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(surface2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(border, lineWidth: 1)
                        )
                )

                if header.version.needUpdate {
                    Button(action: { header.requestUpdate() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                            Text("下载 Mac 安装包")
                                .font(.system(size: AppTheme.bodySize, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.brand(dark)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(header.updatePhase.isActive)
                    .help("下载 macOS 安装包（DMG），替换应用程序后重启")
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 22)
    }

    private func versionItem(label: String, value: String, showTag: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: AppTheme.captionSize, weight: .bold))
                .foregroundColor(textMuted)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(textPrimary)
                if showTag {
                    Text(header.version.needUpdate ? "可更新" : "最新")
                        .font(.system(size: AppTheme.captionSize, weight: .bold))
                        .foregroundColor(header.version.needUpdate
                            ? (dark ? Color(hex: "fbbf24") : Color(hex: "854d0e"))
                            : (dark ? Color(hex: "4ade80") : Color(hex: "166534")))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(header.version.needUpdate
                                    ? (dark ? Color(hex: "eab308").opacity(0.15) : Color(hex: "fef9c3"))
                                    : (dark ? Color(hex: "22c55e").opacity(0.15) : Color(hex: "dcfce7")))
                        )
                }
            }
        }
    }

    // MARK: Links

    private var linksRow: some View {
        HStack(spacing: 12) {
            linkButton(icon: "chevron.left.slash.chevron.right", title: "开源仓库", url: githubURL)
            linkButton(icon: "paperplane", title: "Telegram", url: telegramURL)
            linkButton(icon: "doc.text", title: "更新日志", url: releasesURL)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 24)
    }

    private func linkButton(icon: String, title: String, url: String) -> some View {
        Button(action: {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                Text(title)
                    .font(.system(size: AppTheme.bodySize, weight: .medium))
            }
            .foregroundColor(textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(dark ? surface2 : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: Donate

    private var donateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Text("请作者喝杯咖啡")
                        .font(.system(size: AppTheme.sectionSize, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(dark))
                    Image(systemName: "heart.fill")
                        .font(.system(size: AppTheme.captionSize))
                        .foregroundColor(Color(hex: "f43f5e"))
                }
                Spacer()
                Text("点击二维码可放大预览")
                    .font(.system(size: AppTheme.secondarySize))
                    .foregroundColor(textMuted)
            }

            HStack(spacing: 16) {
                donateCard(
                    path: "/images/weixin.JPG",
                    title: "微信支付",
                    titleIcon: "message.fill",
                    titleColor: Color(hex: "07C160"),
                    subtitle: "扫码赞赏支持",
                    showCopy: false
                )
                donateCard(
                    path: "/images/binance_qr.jpg",
                    title: "币安/USDT",
                    titleIcon: "dollarsign.circle.fill",
                    titleColor: Color(hex: "F3BA2F"),
                    subtitle: nil,
                    showCopy: true
                )
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 22)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.inputBg(dark),
                    donateBg
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func donateCard(
        path: String,
        title: String,
        titleIcon: String,
        titleColor: Color,
        subtitle: String?,
        showCopy: Bool
    ) -> some View {
        HStack(spacing: 16) {
            AboutRemoteQR(url: imageURL(path), dark: dark) { img in
                zoomImage = img
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: titleIcon)
                        .foregroundColor(titleColor)
                    Text(title)
                        .font(.system(size: AppTheme.bodySize, weight: .semibold))
                        .foregroundColor(textPrimary)
                }
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: AppTheme.secondarySize))
                        .foregroundColor(textMuted)
                }
                if showCopy {
                    Button(action: copyTRC20) {
                        HStack(spacing: 5) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: AppTheme.captionSize, weight: .semibold))
                            Text(copied ? "已复制" : "TRC20 复制地址")
                                .font(.system(size: AppTheme.secondarySize, weight: .medium))
                        }
                        .foregroundColor(copied ? AppTheme.brand(dark) : textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(pillBg)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(trc20)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBg)
                .shadow(color: Color.black.opacity(dark ? 0.25 : 0.06), radius: 6, x: 0, y: 2)
        )
    }

    private func imageURL(_ path: String) -> URL? {
        try? APIClient.shared.makeURL(session.serverURL, path: path)
    }

    private func copyTRC20() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trc20, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Remote QR (macOS 11: no AsyncImage)

private struct AboutRemoteQR: View {
    let url: URL?
    var dark: Bool
    var onZoom: (NSImage) -> Void

    @State private var image: NSImage?
    @State private var loading = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.inputBg(dark))
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(5)
                    .cornerRadius(10)
            } else if loading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 28))
                    .foregroundColor(dark ? Color.white.opacity(0.25) : Color.black.opacity(0.2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            if let image = image { onZoom(image) }
        }
        .onAppear { load() }
        .onChange(of: url?.absoluteString) { _ in load() }
    }

    private func load() {
        guard let url = url else {
            loading = false
            image = nil
            return
        }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSImage(contentsOf: url)
            DispatchQueue.main.async {
                self.image = img
                self.loading = false
            }
        }
    }
}

// MARK: - Version update progress（下载 DMG）

private struct VersionUpdateProgressSheet: View {
    @ObservedObject var header: HeaderViewModel
    var dark: Bool

    private var title: String {
        switch header.updatePhase {
        case .downloading: return "正在下载 Mac 安装包"
        case .opening: return "正在打开 DMG"
        case .completed: return "安装包已就绪"
        case .failed: return "下载失败"
        case .idle: return "Mac 升级"
        }
    }

    private var detail: String {
        switch header.updatePhase {
        case .downloading(let p):
            let pct = Int((p * 100).rounded())
            return "正在从 GitHub 下载 Mac 安装包（DMG）… \(pct)%"
        case .opening:
            return "即将在 Finder 中打开安装镜像…"
        case .completed(let path):
            return "已保存到：\n\(path)\n\n请将 OciStart 拖入「应用程序」，然后重新打开。这不会改动 Web / 远程服务端。"
        case .failed(let msg):
            return msg
        case .idle:
            return ""
        }
    }

    private var finished: Bool {
        switch header.updatePhase {
        case .failed, .completed: return true
        default: return false
        }
    }

    private var failed: Bool {
        if case .failed = header.updatePhase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: failed
                  ? "exclamationmark.triangle.fill"
                  : (finished ? "checkmark.circle.fill" : "arrow.down.circle.fill"))
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(failed
                                 ? Color(hex: "f59e0b")
                                 : AppTheme.brand(dark))

            Text(title)
                .font(.system(size: AppTheme.dialogTitleSize, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(dark))

            Text(detail)
                .font(.system(size: AppTheme.secondarySize))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary(dark))
                .fixedSize(horizontal: false, vertical: true)

            if case .downloading(let p) = header.updatePhase {
                ProgressView(value: min(max(p, 0), 1))
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 260)
            } else if !finished {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.0)
            }

            if finished {
                Button("完成") {
                    header.dismissUpdateProgress()
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.sidebarActive))
                .foregroundColor(.white)
            }
        }
        .padding(28)
        .frame(width: 400, height: 300)
        .background(AppTheme.cardBg(dark))
    }
}
