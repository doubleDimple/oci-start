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
            header.requestUpdate()
        }) {
            HStack(spacing: 5) {
                Image(systemName: header.updatePhase.isActive ? "arrow.triangle.2.circlepath" : "arrow.up.circle.fill")
                Text(header.updatePhase.isActive
                     ? "升级中…"
                     : "发现新版本 (\(header.version.latestVersion))")
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
        .disabled(header.updatePhase.isActive)
        .help("下载新版 macOS 安装包（DMG）")
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

// MARK: - About（对齐 Web `version_info.ftl`）

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
        header.version.currentVersion.isEmpty ? "v1.0.0" : header.version.currentVersion
    }

    private var latestVersion: String {
        let lat = header.version.latestVersion
        return lat.isEmpty ? currentVersion : lat
    }

    private var surface: Color { dark ? Color(hex: "1e2430") : Color.white }
    private var surface2: Color { dark ? Color(hex: "252d3d") : Color(hex: "f8fafc") }
    private var border: Color { dark ? Color(hex: "2e3a4e") : Color(hex: "edf2f7") }
    private var textPrimary: Color { dark ? Color(hex: "e2e8f0") : Color(hex: "0f172a") }
    private var textMuted: Color { dark ? Color(hex: "6b7fa3") : Color(hex: "94a3b8") }
    private var textSecondary: Color { dark ? Color(hex: "94a3b8") : Color(hex: "475569") }
    private var donateBg: Color { dark ? Color(hex: "161e2e") : Color(hex: "f1f5f9") }
    private var cardBg: Color { dark ? Color(hex: "252d3d") : Color.white }
    private var pillBg: Color { dark ? Color(hex: "2e3a4e") : Color(hex: "f1f5f9") }

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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(dark ? Color(hex: "2a3144") : Color(hex: "f1f5f9")))
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
        .frame(width: 720, height: 460)
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
                                    Color(hex: "e0f2fe"),
                                    Color(hex: "bae6fd")
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Color(hex: "0ea5e9"))
                }
                .frame(width: 64, height: 64)
                .shadow(color: Color(hex: "0ea5e9").opacity(0.25), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Oci-Start")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(textPrimary)
                    Text("Created by doubleDimple")
                        .font(.system(size: 12))
                        .foregroundColor(textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                versionItem(label: "Current", value: currentVersion, showTag: true)
                Rectangle()
                    .fill(dark ? Color(hex: "2e3a4e") : Color(hex: "e2e8f0"))
                    .frame(width: 1, height: 36)
                    .padding(.horizontal, 18)
                versionItem(label: "Latest", value: latestVersion, showTag: false)
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
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 22)
    }

    private func versionItem(label: String, value: String, showTag: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(textMuted)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundColor(textPrimary)
                if showTag {
                    Text(header.version.needUpdate ? "UPDATE" : "LATEST")
                        .font(.system(size: 9, weight: .bold))
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
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(dark ? surface2 : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(dark ? border : Color(hex: "e2e8f0"), lineWidth: 1)
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(dark ? Color(hex: "cbd5e1") : Color(hex: "334155"))
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "f43f5e"))
                }
                Spacer()
                Text("点击二维码可放大预览")
                    .font(.system(size: 11))
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
                    dark ? Color(hex: "1a2133") : Color(hex: "f8fafc"),
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(textPrimary)
                }
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(textMuted)
                }
                if showCopy {
                    Button(action: copyTRC20) {
                        HStack(spacing: 5) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                            Text(copied ? "已复制" : "TRC20 复制地址")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(copied ? Color(hex: "10b981") : textSecondary)
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
                .fill(dark ? Color(hex: "1e2430") : Color(hex: "f8fafc"))
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
        case .downloading: return "正在下载安装包"
        case .opening: return "正在打开 DMG"
        case .completed: return "下载完成"
        case .failed: return "升级失败"
        case .idle: return "升级"
        }
    }

    private var detail: String {
        switch header.updatePhase {
        case .downloading(let p):
            let pct = Int((p * 100).rounded())
            return "从 GitHub 下载 OciStart.dmg… \(pct)%"
        case .opening:
            return "即将在 Finder 中打开安装镜像…"
        case .completed(let path):
            return "已保存到：\n\(path)\n\n请将 OciStart 拖入「应用程序」，然后重新打开。"
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
                                 : (finished ? Color(hex: "10b981") : Color(hex: "1890ff")))

            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(dark ? Color.white.opacity(0.92) : Color(hex: "0f172a"))

            Text(detail)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundColor(dark ? Color.white.opacity(0.55) : Color(hex: "64748b"))
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
        .background(dark ? Color(hex: "1e2430") : Color.white)
    }
}
