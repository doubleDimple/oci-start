import SwiftUI
import AppKit

/// 原生 AI 对话整页 — 内容区铺满 + 底栏通栏极简输入
struct AiChatView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var navigation: NavigationState
    @StateObject private var model = AiChatViewModel()
    @State private var scrollProxy: ScrollViewProxy?
    @State private var hoveredTenantId: Int64?
    @State private var inputFocused = false
    /// 租户列默认隐藏，给聊天区最大宽度；点顶栏按钮展开
    @State private var showTenantRail = false

    private var dark: Bool { appearance.isDarkEffective }

    /// 主色强调
    private var accent: Color { AppTheme.sidebarActive }
    private var indigo: Color { Color(hex: "6366f1") }
    private var surface: Color { AppTheme.sidebarBg(dark) }
    private var page: Color { AppTheme.pageBg(dark) }
    private var muted: Color { AppTheme.sidebarText(dark) }

    /// 内容区左右边距（消息流 / 输入框随内容区全宽伸缩）
    private var stageHPad: CGFloat { 20 }

    var body: some View {
        HStack(spacing: 0) {
            if showTenantRail {
                tenantRail
                    .frame(width: 280)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            chatStage
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(page)
        .animation(.easeInOut(duration: 0.22), value: showTenantRail)
        .onAppear {
            FloatingMenuDismiss.all()
            model.start()
            model.consumePendingTenant()
        }
        .onDisappear { model.teardown() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.loadTenants() }
        }
        .onReceive(navigation.$aiChatOpenToken) { _ in
            model.consumePendingTenant()
            // 从租户列表跳入时已预选，保持收起
            showTenantRail = false
        }
        .onChange(of: model.messages.count) { _ in scrollToBottom() }
        .onChange(of: model.messages.last?.text ?? "") { _ in scrollToBottom() }
        // 尚无租户时自动展开，方便首次选择
        .onChange(of: model.isLoadingTenants) { loading in
            if !loading, model.selectedTenantId == nil, !model.tenants.isEmpty {
                showTenantRail = true
            }
        }
    }

    // MARK: - Left rail

    private var tenantRail: some View {
        VStack(spacing: 0) {
            // Hero header
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        accent.opacity(0.95),
                                        indigo.opacity(0.85)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(color: accent.opacity(0.35), radius: 8, y: 3)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OCI AI")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(dark ? Color.white.opacity(0.95) : Color.primary)
                        Text("智能助手 · 按租户对话")
                            .font(.system(size: 11))
                            .foregroundColor(muted)
                    }
                    Spacer(minLength: 0)
                    // 收起租户列
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showTenantRail = false
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(muted)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("收起租户列表")
                }

                SearchField(text: $model.tenantSearch, placeholder: "搜索租户名称 / 区域…")
            }
            .padding(16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        surface,
                        surface.opacity(0.92)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Section label
            HStack {
                Text("租户会话")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(muted)
                    .textCase(.uppercase)
                Spacer()
                Text("\(model.filteredTenants.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.12)))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if model.isLoadingTenants && model.tenants.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("加载租户…")
                        .font(.system(size: 12))
                        .foregroundColor(muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredTenants.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(muted.opacity(0.5))
                    Text("暂无匹配租户")
                        .font(.system(size: 12))
                        .foregroundColor(muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.filteredTenants) { t in
                            tenantRow(t)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }

            // Footer tip
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("从租户列表点 AI 可直达本页")
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundColor(muted.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dark ? Color.black.opacity(0.15) : Color.black.opacity(0.03))
        }
        .background(surface)
        .overlay(
            Rectangle()
                .fill(AppTheme.border(dark).opacity(0.45))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private func tenantRow(_ t: AiChatTenantOption) -> some View {
        let selected = model.selectedTenantId == t.id
        let hovered = hoveredTenantId == t.id
        return Button {
            model.selectTenant(t.id, force: true)
            // 选完自动收起，把宽度还给聊天区
            withAnimation(.easeInOut(duration: 0.22)) {
                showTenantRail = false
            }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(
                            selected
                                ? LinearGradient(
                                    gradient: Gradient(colors: [accent, indigo.opacity(0.9)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    gradient: Gradient(colors: [
                                        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                        dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                        .frame(width: 36, height: 36)
                    Text(String(t.name.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(selected ? .white : muted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 9))
                        Text(t.region.isEmpty ? "未知区域" : t.region)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                    }
                    .foregroundColor(muted)
                }
                Spacer(minLength: 0)
                if t.supportAI {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selected ? accent : accent.opacity(0.55))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        selected
                            ? accent.opacity(dark ? 0.16 : 0.1)
                            : (hovered ? (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? accent.opacity(0.45) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { inside in
            hoveredTenantId = inside ? t.id : (hoveredTenantId == t.id ? nil : hoveredTenantId)
        }
        .animation(.easeOut(duration: 0.14), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    // MARK: - Chat stage

    private var chatStage: some View {
        ZStack(alignment: .bottom) {
            page.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                messageCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 底栏通栏极简输入（铺满内容区宽度）
            composer
                .padding(.horizontal, stageHPad)
                .padding(.bottom, 12)
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            // 展开/收起租户列
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showTenantRail.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                    if !showTenantRail {
                        Text("租户")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundColor(showTenantRail ? accent : muted)
                .padding(.horizontal, showTenantRail ? 8 : 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(showTenantRail
                              ? accent.opacity(0.14)
                              : (dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            showTenantRail ? accent.opacity(0.4) : AppTheme.border(dark).opacity(0.45),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help(showTenantRail ? "收起租户列表" : "展开租户列表")

            // Tenant + status（点击也可展开切换租户）
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showTenantRail = true
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.15))
                            .frame(width: 34, height: 34)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(model.selectedTenant?.name ?? "未选择租户")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(dark ? Color.white.opacity(0.94) : Color.primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(muted)
                        }
                        statusPill
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .help("切换租户")

            Spacer(minLength: 8)

            // Model picker
            if model.isLoadingModels {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65)
                    Text("加载模型…")
                        .font(.system(size: 11))
                        .foregroundColor(muted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(surface))
            } else if !model.models.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(indigo)
                    SelectMenu(
                        options: model.models.map {
                            SelectOption(id: $0.id, title: $0.title)
                        },
                        selection: Binding(
                            get: { model.selectedModelId.isEmpty ? nil : model.selectedModelId },
                            set: {
                                model.selectedModelId = $0 ?? ""
                                model.onModelChanged()
                            }
                        ),
                        placeholder: "选择模型",
                        width: 220,
                        allowClear: false
                    )
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppTheme.border(dark).opacity(0.5), lineWidth: 1)
                        )
                )
            } else if model.selectedTenantId != nil {
                Text("暂无可用模型")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "f59e0b"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: "f59e0b").opacity(0.12)))
            }

            // Context toggle chip
            contextChip

            iconToolButton(systemImage: "doc.on.doc", tip: "复制最后回复") {
                model.copyLastAssistant()
            }
            iconToolButton(systemImage: "trash", tip: "清空对话") {
                model.clearChat(keepWelcome: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            surface.opacity(0.92)
                .overlay(
                    Rectangle()
                        .fill(AppTheme.border(dark).opacity(0.4))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.6), radius: 3)
            Text(model.statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(muted)
                .lineLimit(1)
        }
    }

    private var statusColor: Color {
        if model.isConnected { return Color(hex: "10b981") }
        if model.isLoadingModels || model.statusText.contains("连接") || model.statusText.contains("加载") {
            return Color(hex: "f59e0b")
        }
        return Color(hex: "94a3b8")
    }

    private var contextChip: some View {
        Button(action: { model.useHistory.toggle() }) {
            HStack(spacing: 5) {
                Image(systemName: model.useHistory ? "bubble.left.and.bubble.right.fill" : "bubble.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("上下文")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(model.useHistory ? accent : muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(model.useHistory ? accent.opacity(0.14) : (dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
            )
            .overlay(
                Capsule()
                    .stroke(model.useHistory ? accent.opacity(0.35) : AppTheme.border(dark).opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("是否携带历史消息作为上下文")
    }

    private func iconToolButton(systemImage: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(muted)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(AppTheme.border(dark).opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(tip)
    }

    // MARK: - Messages

    private var messageCanvas: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if showHeroEmpty {
                        heroEmpty
                            .padding(.top, 48)
                            .padding(.bottom, 24)
                    }

                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(model.messages) { msg in
                            if !(showHeroEmpty && msg.role == .assistant && model.messages.count == 1) {
                                messageRow(msg)
                                    .id(msg.id)
                            }
                        }
                        if model.isSending {
                            typingDotsRow
                                .id("typing")
                        }
                        Color.clear.frame(height: 88).id("chat-bottom")
                    }
                    .padding(.horizontal, stageHPad)
                    .padding(.top, showHeroEmpty ? 0 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    /// 仅欢迎语时展示大空态
    private var showHeroEmpty: Bool {
        model.messages.count <= 1
            && !model.isSending
            && (model.messages.isEmpty || model.messages.first?.role == .assistant)
    }

    private var heroEmpty: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                accent.opacity(0.28),
                                accent.opacity(0.05),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 4,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [accent, indigo]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: accent.opacity(0.4), radius: 16, y: 6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            VStack(spacing: 8) {
                Text("有什么可以帮你的？")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(dark ? Color.white.opacity(0.94) : Color.primary)
                Text(model.selectedTenant.map { "正在与 \($0.name) 的 OCI AI 模型对话" }
                     ?? "从左侧选择一个租户，开始智能对话")
                    .font(.system(size: 13))
                    .foregroundColor(muted)
                    .multilineTextAlignment(.center)
            }

            // Suggestion chips
            HStack(spacing: 8) {
                suggestChip("解释当前区域配额")
                suggestChip("生成安全组建议")
                suggestChip("总结实例状态")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, stageHPad)
    }

    private func suggestChip(_ title: String) -> some View {
        Button {
            model.input = title
            model.send()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(dark ? Color.white.opacity(0.85) : Color.primary.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(surface)
                        .shadow(color: Color.black.opacity(dark ? 0.25 : 0.06), radius: 6, y: 2)
                )
                .overlay(
                    Capsule()
                        .stroke(AppTheme.border(dark).opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!model.isConnected || model.selectedModelId.isEmpty)
        .opacity(model.isConnected && !model.selectedModelId.isEmpty ? 1 : 0.45)
    }

    private func messageRow(_ msg: AiChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if msg.role == .user {
                Spacer(minLength: 80)
                userBubble(msg)
            } else {
                assistantBlock(msg)
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.16), value: msg.text)
    }

    /// 用户：右侧浅底气泡（短句像 pill，多行自动圆角矩形）
    private func userBubble(_ msg: AiChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(msg.text)
                .font(.system(size: 13.5))
                .foregroundColor(dark ? Color.white.opacity(0.95) : Color.primary)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(dark ? Color.white.opacity(0.12) : Color(hex: "f3f4f6"))
                )
            Text(timeString(msg.createdAt))
                .font(.system(size: 10))
                .foregroundColor(muted.opacity(0.75))
        }
        .frame(maxWidth: 480, alignment: .trailing)
    }

    /// 助手：接近全宽正文，弱化气泡
    private func assistantBlock(_ msg: AiChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if msg.role == .system {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "d97706"))
                    Text(msg.text)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "d97706"))
                        .lineSpacing(3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "f59e0b").opacity(0.12))
                )
            } else {
                Text(msg.text)
                    .font(.system(size: 14))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Text(timeString(msg.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(muted.opacity(0.75))
                if msg.isStreaming {
                    Text("生成中")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accent)
                }
                if msg.role == .assistant, !msg.isStreaming {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg.text, forType: .string)
                        ToastCenter.shared.success("已复制")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(muted.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("复制本条")
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typingDotsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("AI 正在思考…")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(muted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 6) {
            if let err = model.errorText, !err.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(Color(hex: "f85149"))
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "f85149"))
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            HStack(alignment: .center, spacing: 10) {
                ZStack(alignment: .leading) {
                    if model.input.isEmpty {
                        Text("畅所欲问…")
                            .font(.system(size: 14))
                            .foregroundColor(muted.opacity(0.55))
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    MacChatTextEditor(text: $model.input, onSubmit: { model.send() })
                        .frame(minHeight: 24, maxHeight: 88)
                }
                .frame(maxWidth: .infinity)

                Button(action: { model.send() }) {
                    ZStack {
                        Circle()
                            .fill(
                                canSend
                                    ? Color.primary.opacity(dark ? 0.92 : 0.88)
                                    : muted.opacity(0.22)
                            )
                            .frame(width: 30, height: 30)
                        if model.isSending {
                            ProgressView()
                                .scaleEffect(0.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: dark ? .black : .white))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(canSend ? (dark ? .black : .white) : muted.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSend)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(dark ? Color.white.opacity(0.08) : Color(hex: "f4f4f5"))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AppTheme.border(dark).opacity(0.35), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)

            Text(composerHint)
                .font(.system(size: 10))
                .foregroundColor(muted.opacity(0.55))
                .frame(maxWidth: .infinity)
        }
    }

    private var canSend: Bool {
        model.isConnected
            && !model.selectedModelId.isEmpty
            && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isSending
    }

    private var composerHint: String {
        if !model.isConnected {
            return model.statusText.isEmpty ? "等待连接…" : model.statusText
        }
        if model.selectedModelId.isEmpty {
            return "请选择可用模型后再发送"
        }
        return "内容由 OCI Generative AI 生成 · 请核对重要信息"
    }

    // MARK: - Helpers

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func scrollToBottom() {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                scrollProxy?.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - Text editor with Enter-to-send

private struct MacChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.string = text
        context.coordinator.textView = tv

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
        let dark = AppearanceController.shared.isDarkEffective
        tv.textColor = dark ? NSColor.white.withAlphaComponent(0.92) : NSColor.labelColor
        tv.insertionPointColor = dark ? .white : .labelColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacChatTextEditor
        weak var textView: NSTextView?

        init(_ parent: MacChatTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
