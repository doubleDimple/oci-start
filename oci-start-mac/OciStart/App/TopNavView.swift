import SwiftUI
import AppKit

/// Web-parity top bar (`header.ftl` + `header.js`).
/// Dropdown panels are rendered by `TopNavDropdownOverlay` (in-window), not system popover.
struct TopNavView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var navigation: NavigationState
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var header: HeaderViewModel
    @EnvironmentObject private var chrome: TopNavChromeState
    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                sidebarToggle
                brand
                pageTrail
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            trailingActions
        }
        .padding(.horizontal, 16)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: 56)
        .background(AppTheme.topNavBg(dark))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.8)),
            alignment: .bottom
        )
        .onAppear { header.start() }
        .onDisappear { header.stop() }
        // 消息中心改为右侧滑出抽屉（见 TopNavDropdownOverlay），不再用居中 sheet
        .sheet(isPresented: $header.showAsset) {
            AssetAnalysisSheet(header: header, dark: dark)
                .environmentObject(appearance)
        }
        .sheet(isPresented: $header.showAbout) {
            AboutSheet(
                version: header.version.currentVersion.isEmpty ? "1.0.0" : header.version.currentVersion,
                dark: dark
            )
            .environmentObject(appearance)
        }
    }

    // MARK: - Left

    private var sidebarToggle: some View {
        Button(action: {
            chrome.close()
            navigation.sidebarCollapsed.toggle()
        }) {
            Image(systemName: navigation.sidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.navIcon(dark))
                .frame(width: 36, height: 36)
                .background(circleBg(highlight: navigation.sidebarCollapsed))
        }
        .buttonStyle(PlainButtonStyle())
        .help(navigation.sidebarCollapsed ? "展开侧栏（⌘⌥S）" : "收起侧栏（⌘⌥S）")
    }

    private var brand: some View {
        Button(action: {
            chrome.close()
            navigation.select(.dashboard)
        }) {
            Text(session.siteName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AppTheme.brand(dark))
                .tracking(0.8)
        }
        .buttonStyle(PlainButtonStyle())
        .help("回到系统监控")
    }

    private var pageTrail: some View {
        HStack(spacing: 6) {
            if let item = NavigationCatalog.item(for: navigation.selected) {
                Text("·")
                    .foregroundColor(AppTheme.navIcon(dark).opacity(0.35))
                Image(systemName: item.systemImage)
                    .font(.system(size: 11))
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .foregroundColor(AppTheme.navIcon(dark).opacity(0.85))
        .lineLimit(1)
    }

    // MARK: - Right

    private var trailingActions: some View {
        HStack(spacing: 10) {
            if header.version.needUpdate {
                updateButton
            }

            iconButton(
                systemName: themeIcon,
                help: "主题：\(appearance.mode.title)（⌘T）"
            ) {
                chrome.close()
                appearance.cycle()
            }

            languageButton
            messageButton

            iconButton(systemName: "arrow.clockwise", help: "刷新（⌘R）") {
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
            Task { await header.executeUpdate() }
        }) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.circle.fill")
                Text("发现新版本 (\(header.version.latestVersion))")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(dark ? Color.white : Color(hex: "dc2626"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.red.opacity(dark ? 0.15 : 0.08))
            )
            .overlay(
                Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("执行系统更新")
    }

    private var languageButton: some View {
        Button(action: {
            header.closeMessages()
            chrome.toggle(.language)
        }) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.navIcon(dark))
                .frame(width: 36, height: 36)
                .background(circleBg(highlight: chrome.open == .language))
        }
        .buttonStyle(PlainButtonStyle())
        .help("语言")
    }

    private var messageButton: some View {
        Button(action: {
            chrome.close()
            header.toggleMessages()
        }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.navIcon(dark))
                    .frame(width: 36, height: 36)
                    .background(circleBg(highlight: header.showMessages))
                if header.unreadCount > 0 {
                    Text(header.unreadCount > 99 ? "99+" : "\(header.unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Color(hex: "ff4d4f")))
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .help("消息中心")
    }

    private var userButton: some View {
        Button(action: {
            header.closeMessages()
            chrome.toggle(.user)
        }) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.brand(dark).opacity(0.25))
                        .frame(width: 30, height: 30)
                    Text(avatarLetter)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.brand(dark))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.username.isEmpty ? "Admin" : session.username)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.navIcon(dark))
                    Text(session.cloudProviderName)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.navIcon(dark).opacity(0.7))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppTheme.navIcon(dark).opacity(0.7))
                    .rotationEffect(.degrees(chrome.open == .user ? 180 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(dark ? 0.06 : 0.35))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var themeIcon: String {
        switch appearance.mode {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .system: return "desktopcomputer"
        }
    }

    private var avatarLetter: String {
        let name = session.username
        if let c = name.first { return String(c).uppercased() }
        return "A"
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.navIcon(dark))
                .frame(width: 36, height: 36)
                .background(circleBg(highlight: false))
        }
        .buttonStyle(PlainButtonStyle())
        .help(help)
    }

    private func circleBg(highlight: Bool) -> some View {
        Circle()
            .fill(
                highlight
                    ? AppTheme.sidebarActive.opacity(0.22)
                    : Color.white.opacity(dark ? 0.06 : 0.22)
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
    var onCloud: (Int, String) -> Void
    var onAbout: () -> Void
    var onLogout: () -> Void

    private var welcome: String {
        username.isEmpty ? "欢迎" : "欢迎，\(username)"
    }

    private var levelName: String {
        levelTitle.isEmpty ? AssetAnalysis.levelConfig(level).name : levelTitle
    }

    private var textPrimary: Color {
        dark ? Color.white.opacity(0.92) : Color(hex: "111827")
    }

    private var textMuted: Color {
        dark ? Color.white.opacity(0.5) : Color(hex: "6b7280")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topPart
            cloudPart
            bottomPart
        }
        .padding(.bottom, 6)
        .frame(width: 240)
        .background(dark ? Color(hex: "2a2f36") : Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var topPart: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock
            thinLine
            menuRow(icon: "chart.pie.fill", color: Color(hex: "FFD700"), title: "云资产报告", action: onAsset)
            thinLine
        }
    }

    private var cloudPart: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("切换云厂商")
            menuRow(icon: "cloud", color: checkColor(1), title: cloudLabel(1, "Oracle Cloud"), action: { onCloud(1, "Oracle Cloud") })
            menuRow(icon: "g.circle", color: checkColor(2), title: cloudLabel(2, "Google Cloud"), action: { onCloud(2, "Google Cloud") })
            menuRow(icon: "square.stack.3d.up", color: checkColor(3), title: cloudLabel(3, "Azure Cloud"), action: { onCloud(3, "Azure Cloud") })
            menuRow(icon: "server.rack", color: checkColor(4), title: cloudLabel(4, "Amazon Cloud"), action: { onCloud(4, "Amazon Cloud") })
        }
    }

    private var bottomPart: some View {
        VStack(alignment: .leading, spacing: 0) {
            thinLine
            menuRow(icon: "info.circle", color: textMuted, title: "关于 OCI Start", action: onAbout)
            menuRow(icon: "arrow.right.square", color: Color(hex: "f85149"), title: "退出登录", action: onLogout)
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(welcome)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textPrimary)
            Text(levelName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "b45309"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: "FFD700").opacity(0.18)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var thinLine: some View {
        Rectangle()
            .fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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
                    .font(.system(size: 16, weight: .bold))
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
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.sidebarText(dark))
                        HStack(spacing: 6) {
                            Image(systemName: cfg.icon)
                            Text(a.levelTitle.isEmpty ? cfg.name : a.levelTitle)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(hex: "FFD700").opacity(0.2)))
                        Text("Scale: Lvl.\(lvl)")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    }
                    .frame(width: 180)
                    .padding(16)
                    .background(dark ? Color(hex: "1e2124") : Color(hex: "f8f9fa"))

                    HStack(spacing: 0) {
                        metric("账号总数", "\(a.totalCount)", nil)
                        metric("升级账号", "\(a.upgradeCount)", Color(hex: "2196f3"))
                        metric("免费额度", "\(a.freeCount)", nil)
                        metric("账户费用", a.totalCost, Color(hex: "1abc9c"))
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
        .background(dark ? Color(hex: "22262b") : Color.white)
    }

    private func metric(_ title: String, _ value: String, _ color: Color?) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(color ?? (dark ? Color.white.opacity(0.9) : Color.primary))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - About

private struct AboutSheet: View {
    let version: String
    var dark: Bool
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.brand(dark))
            Text("OCI Start")
                .font(.system(size: 20, weight: .bold))
            Text("版本 \(version)")
                .foregroundColor(AppTheme.sidebarText(dark))
            Text("桌面端 Hybrid AppKit + SwiftUI")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
            Button("关闭") { presentationMode.wrappedValue.dismiss() }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 320, height: 260)
        .background(dark ? Color(hex: "22262b") : Color.white)
    }
}
