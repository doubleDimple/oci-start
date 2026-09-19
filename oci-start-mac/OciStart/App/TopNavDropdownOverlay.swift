import SwiftUI

/// Full-window overlay: 顶栏下拉（语言/用户）+ 右侧消息中心抽屉。
/// 保持在应用窗口内，不使用系统 popover / 居中 sheet。
struct TopNavDropdownOverlay: View {
    @ObservedObject var chrome: TopNavChromeState
    @ObservedObject var header: HeaderViewModel
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var navigation: NavigationState
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var appearance: AppearanceController

    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective }

    /// Match MainShell top bar height
    private let topBarHeight: CGFloat = AppTheme.topBarHeight
    private let trailingPad: CGFloat = AppTheme.pagePadding
    private let messagePanelWidth: CGFloat = 400

    private var anyOverlayOpen: Bool {
        chrome.open != .none || header.showMessages
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                // 语言 / 用户：点击空白关闭
                if chrome.open != .none && !header.showMessages {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width, height: geo.size.height)
                        .onTapGesture { chrome.close() }
                }

                if chrome.open == .search && !header.showMessages {
                    searchPanel
                        .padding(.top, topBarHeight + 4)
                        .padding(.leading, (navigation.sidebarCollapsed ? AppTheme.sidebarCollapsedWidth : AppTheme.sidebarWidth) + AppTheme.pagePadding + 48)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if chrome.open == .appearance && !header.showMessages {
                    appearancePanel
                        .padding(.top, topBarHeight + 4)
                        .padding(.trailing, trailingPad + 180)
                }

                if chrome.open == .language && !header.showMessages {
                    languagePanel
                        .padding(.top, topBarHeight + 4)
                        .padding(.trailing, trailingPad + 156)
                        .transition(.opacity)
                }

                if chrome.open == .user && !header.showMessages {
                    UserDropdownPanel(
                        dark: dark,
                        username: session.username,
                        levelTitle: header.levelBadgeTitle,
                        level: header.levelBadgeLevel,
                        cloudProvider: session.cloudProvider,
                        onAsset: {
                            chrome.close()
                            header.openAssetAnalysis()
                        },
                        onAuditLogs: {
                            chrome.close()
                            navigation.select(.auditLogs)
                        },
                        onAbout: {
                            chrome.close()
                            header.showAbout = true
                            Task { await header.checkVersion() }
                        },
                        onLogout: {
                            chrome.close()
                            Task { await session.logout() }
                        }
                    )
                    .padding(.top, topBarHeight + 4)
                    .padding(.trailing, trailingPad)
                    .shadow(color: Color.black.opacity(dark ? 0.45 : 0.18), radius: 16, y: 8)
                    .transition(.opacity)
                }

                // 消息中心：右侧滑出抽屉
                if header.showMessages {
                    messageDrawer(geo: geo)
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
            .animation(.easeInOut(duration: 0.22), value: header.showMessages)
            .animation(.easeInOut(duration: 0.15), value: chrome.open)
        }
        .allowsHitTesting(anyOverlayOpen)
    }

    private var searchPanel: some View {
        let results = NavigationCatalog.filtered(search: navigation.searchText, cloudType: 1).flatMap { $0.1 }
        return VStack(alignment: .leading, spacing: 0) {
            Text(language.text("找到 \(results.count) 个页面", "\(results.count) matching pages"))
                .font(.system(size: AppTheme.secondarySize))
                .padding(12)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        Button(action: {
                            navigation.select(item.nav)
                            navigation.searchText = ""
                            chrome.close()
                            chrome.blurSearch()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: item.systemImage).frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(size: AppTheme.bodySize))
                                    Text(NavigationCatalog.section(for: item.nav)?.title ?? "")
                                        .font(.system(size: AppTheme.secondarySize))
                                }
                                Spacer()
                                Image(systemName: "arrow.up.left").font(.system(size: AppTheme.captionSize))
                            }
                            .padding(12)
                            .background(index == chrome.searchActiveIndex ? AppTheme.hover(dark) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(item.id)
                        .onHover { inside in if inside { chrome.searchActiveIndex = index } }
                        .accessibilityValue(index == chrome.searchActiveIndex ? language.text("已选中", "Selected") : "")
                    }
                    }
                }
                .onChange(of: chrome.searchActiveIndex) { index in
                    if results.indices.contains(index) { scroll.scrollTo(results[index].id) }
                }
                .onChange(of: navigation.searchText) { _ in
                    if let first = results.first { scroll.scrollTo(first.id, anchor: .top) }
                }
            }
            .frame(maxHeight: 320)
            Text(language.text("↑↓ 选择 · Enter 打开 · Esc 清空", "↑↓ Select · Enter Open · Esc Clear"))
                .font(.system(size: AppTheme.secondarySize)).padding(12)
        }
        .foregroundColor(AppTheme.textPrimary(dark))
        .frame(width: 320)
        .background(AppTheme.cardBg(dark))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border(dark), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.15), radius: 16, y: 8)
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach([AppAppearanceMode.light, .dark, .system], id: \.rawValue) { mode in
                Button(action: {
                    appearance.mode = mode
                    chrome.close()
                }) {
                    HStack {
                        Text(mode.title)
                        Spacer()
                        if appearance.mode == mode { Image(systemName: "checkmark") }
                    }
                    .font(.system(size: AppTheme.bodySize))
                    .foregroundColor(AppTheme.textPrimary(dark))
                    .padding(12)
                    .contentShape(Rectangle())
                }.buttonStyle(PlainButtonStyle())
            }
        }
        .frame(width: 180)
        .padding(6)
        .background(AppTheme.cardBg(dark))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border(dark), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.15), radius: 16, y: 8)
    }

    // MARK: - Language

    private var languagePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("语言")
                .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                .foregroundColor(AppTheme.textMuted(dark))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach([AppLocale.zhCN, .enUS]) { loc in
                Button(action: {
                    Task {
                        if await header.setLocale(loc) { chrome.close() }
                    }
                }) {
                    HStack {
                        Text(loc.title)
                            .font(.system(size: AppTheme.bodySize))
                        Spacer()
                        if header.locale == loc {
                            Image(systemName: "checkmark")
                                .font(.system(size: AppTheme.secondarySize, weight: .bold))
                                .foregroundColor(AppTheme.sidebarActive)
                        }
                    }
                    .foregroundColor(AppTheme.textPrimary(dark))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(header.localeSyncing)
            }
        }
        .padding(.bottom, 8)
        .frame(width: 160, alignment: .leading)
        .background(AppTheme.cardBg(dark))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border(dark), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(dark ? 0.45 : 0.18), radius: 16, y: 8)
    }

    // MARK: - Message drawer (右侧滑出)

    private func messageDrawer(geo: GeometryProxy) -> some View {
        let panelW = min(messagePanelWidth, max(320, geo.size.width * 0.38))
        return ZStack(alignment: .trailing) {
            // 遮罩
            Color.black.opacity(dark ? 0.45 : 0.28)
                .contentShape(Rectangle())
                .onTapGesture { header.closeMessages() }

            // 右侧面板
            MessageCenterDrawerPanel(
                header: header,
                dark: dark,
                width: panelW
            )
            .frame(width: panelW, height: geo.size.height)
            .shadow(color: Color.black.opacity(dark ? 0.5 : 0.18), radius: 24, x: -6, y: 0)
            .offset(x: header.showMessages ? 0 : panelW)
            .animation(.easeOut(duration: 0.24), value: header.showMessages)
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }
}

// MARK: - Message center drawer content

/// 列表 / 详情双态；详情在同一抽屉内切换（非第二层 sheet）。
struct MessageCenterDrawerPanel: View {
    @ObservedObject var header: HeaderViewModel
    var dark: Bool
    var width: CGFloat

    private var surface: Color { AppTheme.cardBg(dark) }
    private var surface2: Color { AppTheme.inputBg(dark) }
    private var border: Color { AppTheme.border(dark) }
    private var textPrimary: Color { AppTheme.textPrimary(dark) }
    private var textMuted: Color { AppTheme.textMuted(dark) }

    var body: some View {
        VStack(spacing: 0) {
            if let error = header.messagesError ?? header.unreadError {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: AppTheme.secondarySize))
                    Button("重试") { Task { await header.loadMessages(page: header.messagePage.pageNum); await header.refreshUnread() } }
                }
                .foregroundColor(AppTheme.danger)
                .padding(12)
            }
            if let detail = header.messageDetail {
                detailHeader(detail)
                detailBody(detail)
            } else {
                listHeader
                listBody
                listFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(surface)
        .disabled(header.messageMutationBusy)
        .overlay(
            Rectangle()
                .fill(border)
                .frame(width: 1),
            alignment: .leading
        )
    }

    // MARK: List

    private var listHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.system(size: AppTheme.bodySize, weight: .semibold))
                .foregroundColor(AppTheme.sidebarActive)
            VStack(alignment: .leading, spacing: 2) {
                Text("消息中心")
                    .font(.system(size: AppTheme.sectionSize, weight: .semibold))
                    .foregroundColor(textPrimary)
                if header.unreadCount > 0 {
                    Text("\(header.unreadCount) 条未读")
                        .font(.system(size: AppTheme.secondarySize))
                        .foregroundColor(AppTheme.danger)
                } else {
                    Text("全部已读")
                        .font(.system(size: AppTheme.secondarySize))
                        .foregroundColor(textMuted)
                }
            }
            Spacer(minLength: 8)
            Button(action: {
                Task { await header.markAllRead() }
            }) {
                Text("全部已读")
                    .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarActive)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AppTheme.sidebarActive.opacity(0.12))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(header.unreadCount == 0)

            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(surface2.opacity(0.65))
        .overlay(
            Rectangle().fill(border).frame(height: 1),
            alignment: .bottom
        )
    }

    private var listBody: some View {
        Group {
            if header.messagesLoading && header.messagePage.content.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text("加载消息…")
                        .font(.system(size: AppTheme.captionSize))
                        .foregroundColor(textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if header.messagePage.content.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(textMuted.opacity(0.7))
                    Text("暂无消息")
                        .font(.system(size: AppTheme.bodySize, weight: .medium))
                        .foregroundColor(textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(header.messagePage.content) { msg in
                            messageRow(msg)
                            Rectangle()
                                .fill(border)
                                .frame(height: 1)
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }

    private func messageRow(_ msg: SysMessageItem) -> some View {
        Button(action: {
            Task { await header.openMessageDetail(msg) }
        }) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(msg.isUnread ? AppTheme.danger : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 5) {
                    Text(msg.subject.isEmpty ? "(无标题)" : msg.subject)
                        .font(.system(size: AppTheme.bodySize, weight: msg.isUnread ? .semibold : .medium))
                        .foregroundColor(textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(msg.createTime)
                            .font(.system(size: AppTheme.secondarySize))
                            .foregroundColor(textMuted)
                        if !msg.messageType.isEmpty {
                            Text(msg.messageType)
                                .font(.system(size: AppTheme.captionSize, weight: .medium))
                                .foregroundColor(AppTheme.sidebarActive)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AppTheme.sidebarActive.opacity(0.12)))
                        }
                    }
                }
                Spacer(minLength: 4)
                Button(action: {
                    Task { await header.deleteMessage(msg.businessId) }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: AppTheme.secondarySize, weight: .medium))
                        .foregroundColor(AppTheme.danger.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.danger.opacity(0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("删除")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(
                msg.isUnread
                    ? AppTheme.sidebarActive.opacity(dark ? 0.08 : 0.05)
                    : Color.clear
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var listFooter: some View {
        HStack(spacing: 10) {
            Button(action: {
                let p = max(1, header.messagePage.pageNum - 1)
                Task { await header.loadMessages(page: p) }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                    .frame(width: 32, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(surface2))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(header.messagePage.pageNum <= 1)
            .opacity(header.messagePage.pageNum <= 1 ? 0.4 : 1)

            Text("\(header.messagePage.pageNum) / \(max(header.messagePage.totalPages, 1))")
                .font(.system(size: AppTheme.captionSize, weight: .medium))
                .foregroundColor(textMuted)
                .frame(minWidth: 56)

            Button(action: {
                let p = header.messagePage.pageNum + 1
                Task { await header.loadMessages(page: p) }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                    .frame(width: 32, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(surface2))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(header.messagePage.pageNum >= max(header.messagePage.totalPages, 1))
            .opacity(header.messagePage.pageNum >= max(header.messagePage.totalPages, 1) ? 0.4 : 1)

            Spacer()
            Text("共 \(header.messagePage.totalElements) 条")
                .font(.system(size: AppTheme.secondarySize))
                .foregroundColor(textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(surface2.opacity(0.65))
        .overlay(
            Rectangle().fill(border).frame(height: 1),
            alignment: .top
        )
    }

    // MARK: Detail

    private func detailHeader(_ msg: SysMessageItem) -> some View {
        HStack(spacing: 10) {
            Button(action: { header.backToMessageList() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: AppTheme.captionSize, weight: .semibold))
                    Text("返回")
                        .font(.system(size: AppTheme.captionSize, weight: .semibold))
                }
                .foregroundColor(AppTheme.sidebarActive)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppTheme.sidebarActive.opacity(0.12)))
            }
            .buttonStyle(PlainButtonStyle())

            Text("消息详情")
                .font(.system(size: AppTheme.sectionSize, weight: .semibold))
                .foregroundColor(textPrimary)
            Spacer()
            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(surface2.opacity(0.65))
        .overlay(
            Rectangle().fill(border).frame(height: 1),
            alignment: .bottom
        )
    }

    private func detailBody(_ msg: SysMessageItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(msg.subject.isEmpty ? "(无标题)" : msg.subject)
                    .font(.system(size: AppTheme.sectionSize, weight: .semibold))
                    .foregroundColor(textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Label(msg.createTime.isEmpty ? "—" : msg.createTime, systemImage: "clock")
                    if !msg.messageType.isEmpty {
                        Text(msg.messageType)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.sidebarActive.opacity(0.15)))
                            .foregroundColor(AppTheme.sidebarActive)
                    }
                }
                .font(.system(size: AppTheme.captionSize))
                .foregroundColor(textMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface2.opacity(0.4))

            Rectangle().fill(border).frame(height: 1)

            ScrollView {
                Text(msg.content.isEmpty ? "（无内容）" : msg.content)
                    .font(.system(size: AppTheme.bodySize))
                    .foregroundColor(textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            Spacer(minLength: 0)

            HStack {
                Button(action: {
                    Task {
                        await header.deleteMessage(msg.businessId)
                        header.backToMessageList()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("删除")
                    }
                    .font(.system(size: AppTheme.captionSize, weight: .semibold))
                    .foregroundColor(AppTheme.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.danger.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: { header.backToMessageList() }) {
                    Text("返回列表")
                        .font(.system(size: AppTheme.captionSize, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.sidebarActive))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(14)
            .overlay(
                Rectangle().fill(border).frame(height: 1),
                alignment: .top
            )
        }
    }

    private var closeButton: some View {
        Button(action: { header.closeMessages() }) {
            Image(systemName: "xmark")
                .font(.system(size: AppTheme.secondarySize, weight: .bold))
                .foregroundColor(textMuted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(surface2))
        }
        .buttonStyle(PlainButtonStyle())
        .help("关闭")
    }
}
