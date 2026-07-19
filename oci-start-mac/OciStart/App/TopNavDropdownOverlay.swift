import SwiftUI

/// Full-window overlay: 顶栏下拉（语言/用户）+ 右侧消息中心抽屉。
/// 保持在应用窗口内，不使用系统 popover / 居中 sheet。
struct TopNavDropdownOverlay: View {
    @ObservedObject var chrome: TopNavChromeState
    @ObservedObject var header: HeaderViewModel
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }

    /// Match MainShell top bar height
    private let topBarHeight: CGFloat = 56
    private let trailingPad: CGFloat = 16
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

                if chrome.open == .language && !header.showMessages {
                    languagePanel
                        .padding(.top, topBarHeight + 4)
                        .padding(.trailing, trailingPad + 120)
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
                        onCloud: { type, _ in
                            chrome.close()
                            session.setCloudProvider(type)
                        },
                        onAbout: {
                            chrome.close()
                            header.showAbout = true
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

    // MARK: - Language

    private var languagePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("语言")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.45) : Color(hex: "6b7280"))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(AppLocale.allCases) { loc in
                Button(action: {
                    header.setLocale(loc)
                    chrome.close()
                }) {
                    HStack {
                        Text(loc.title)
                            .font(.system(size: 13))
                        Spacer()
                        if header.locale == loc {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.sidebarActive)
                        }
                    }
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color(hex: "111827"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.bottom, 8)
        .frame(width: 160, alignment: .leading)
        .background(dark ? Color(hex: "2a2f36") : Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
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

    private var surface: Color { dark ? Color(hex: "1e2228") : Color.white }
    private var surface2: Color { dark ? Color(hex: "262b32") : Color(hex: "f5f7fa") }
    private var border: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    private var textPrimary: Color { dark ? Color.white.opacity(0.92) : Color(hex: "111827") }
    private var textMuted: Color { dark ? Color.white.opacity(0.55) : Color(hex: "6b7280") }

    var body: some View {
        VStack(spacing: 0) {
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.sidebarActive)
            VStack(alignment: .leading, spacing: 2) {
                Text("消息中心")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(textPrimary)
                if header.unreadCount > 0 {
                    Text("\(header.unreadCount) 条未读")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "ff4d4f"))
                } else {
                    Text("全部已读")
                        .font(.system(size: 11))
                        .foregroundColor(textMuted)
                }
            }
            Spacer(minLength: 8)
            Button(action: {
                Task { await header.markAllRead() }
            }) {
                Text("全部已读")
                    .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 12))
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
                        .font(.system(size: 13, weight: .medium))
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
                    .fill(msg.isUnread ? Color(hex: "ff4d4f") : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 5) {
                    Text(msg.subject.isEmpty ? "(无标题)" : msg.subject)
                        .font(.system(size: 13, weight: msg.isUnread ? .semibold : .medium))
                        .foregroundColor(textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(msg.createTime)
                            .font(.system(size: 11))
                            .foregroundColor(textMuted)
                        if !msg.messageType.isEmpty {
                            Text(msg.messageType)
                                .font(.system(size: 10, weight: .medium))
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "f85149").opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "f85149").opacity(0.08))
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
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 32, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(surface2))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(header.messagePage.pageNum <= 1)
            .opacity(header.messagePage.pageNum <= 1 ? 0.4 : 1)

            Text("\(header.messagePage.pageNum) / \(max(header.messagePage.totalPages, 1))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(textMuted)
                .frame(minWidth: 56)

            Button(action: {
                let p = header.messagePage.pageNum + 1
                Task { await header.loadMessages(page: p) }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 32, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(surface2))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(header.messagePage.pageNum >= max(header.messagePage.totalPages, 1))
            .opacity(header.messagePage.pageNum >= max(header.messagePage.totalPages, 1) ? 0.4 : 1)

            Spacer()
            Text("共 \(header.messagePage.totalElements) 条")
                .font(.system(size: 11))
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
                        .font(.system(size: 12, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AppTheme.sidebarActive)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppTheme.sidebarActive.opacity(0.12)))
            }
            .buttonStyle(PlainButtonStyle())

            Text("消息详情")
                .font(.system(size: 15, weight: .semibold))
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
                    .font(.system(size: 16, weight: .semibold))
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
                .font(.system(size: 12))
                .foregroundColor(textMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface2.opacity(0.4))

            Rectangle().fill(border).frame(height: 1)

            ScrollView {
                Text(msg.content.isEmpty ? "（无内容）" : msg.content)
                    .font(.system(size: 13))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "f85149"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "f85149").opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: { header.backToMessageList() }) {
                    Text("返回列表")
                        .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textMuted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(surface2))
        }
        .buttonStyle(PlainButtonStyle())
        .help("关闭")
    }
}
