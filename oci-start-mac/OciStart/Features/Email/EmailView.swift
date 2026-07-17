import SwiftUI

/// 原生邮件管理（对齐 Web `/email/management` · `email.ftl`）。
struct EmailView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = EmailViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(
            title: "邮件管理",
            subtitle: "OCI Email Delivery · 租户服务 / 收件人 / 发送记录",
            systemImage: "envelope",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let err = model.errorText, !err.isEmpty {
                            errorBanner(err)
                        }
                        HStack(alignment: .top, spacing: 14) {
                            tenantPanel
                                .frame(minWidth: 0, maxWidth: .infinity)
                            contactPanel
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                        .frame(minHeight: 320)
                        recordsPanel
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.isLoading)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reloadAll() }
        }
        .sheet(item: $model.activeSheet) { sheet in
            EmailSheetHost(sheet: sheet, model: model)
                .environmentObject(appearance)
        }
        .environmentObject(appearance)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "发送邮件", systemImage: "square.and.pencil", kind: .primary) {
                model.openCompose()
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                Task { await model.reloadAll() }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reloadAll() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Tenant panel

    private var tenantPanel: some View {
        panelCard {
            panelHeader(
                title: "可用租户邮件服务",
                systemImage: "server.rack",
                trailing: {
                    AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                        model.refreshTenants()
                    }
                }
            )

            // Tabs
            HStack(spacing: 4) {
                ForEach(EmailTenantTab.allCases) { tab in
                    tenantTabButton(tab)
                }
            }
            .padding(.bottom, 4)

            SearchField(
                text: Binding(
                    get: { model.tenantSearch },
                    set: { model.onTenantSearchChanged($0) }
                ),
                placeholder: "搜索租户…",
                fillsWidth: true
            )

            Group {
                if model.tenantsLoading && currentTenantEmpty {
                    loadingBox
                } else if currentTenantEmpty {
                    EmptyStateView(
                        icon: model.tenantTab == .enabled ? "server.rack" : "checkmark.circle",
                        title: model.tenantTab == .enabled ? "暂无已开启租户" : "全部租户均已开启",
                        subtitle: model.tenantTab == .enabled
                            ? "可在「未开启」中为租户启用邮件服务"
                            : nil
                    )
                    .frame(minHeight: 160)
                } else if model.tenantTab == .enabled {
                    enabledList
                } else {
                    disabledList
                }
            }
            .frame(minHeight: 180, maxHeight: .infinity)

            compactPager(
                state: model.tenantTab == .enabled ? model.enabledPage : model.disabledPage,
                onPrev: {
                    if model.tenantTab == .enabled {
                        model.enabledPage.goPrev()
                        model.onEnabledPageChange()
                    } else {
                        model.disabledPage.goPrev()
                        model.onDisabledPageChange()
                    }
                },
                onNext: {
                    if model.tenantTab == .enabled {
                        model.enabledPage.goNext()
                        model.onEnabledPageChange()
                    } else {
                        model.disabledPage.goNext()
                        model.onDisabledPageChange()
                    }
                }
            )
        }
    }

    private var currentTenantEmpty: Bool {
        model.tenantTab == .enabled ? model.enabledConfigs.isEmpty : model.disabledTenants.isEmpty
    }

    private func tenantTabButton(_ tab: EmailTenantTab) -> some View {
        let active = model.tenantTab == tab
        let count = tab == .enabled ? model.enabledTotal : model.disabledTotal
        return Button(action: { model.switchTenantTab(tab) }) {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(active ? AppTheme.sidebarActive : AppTheme.sidebarText(dark).opacity(0.45))
                    .cornerRadius(8)
            }
            .foregroundColor(active ? AppTheme.sidebarActive : AppTheme.sidebarText(dark))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(active ? AppTheme.sidebarActive : .clear),
                alignment: .bottom
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var enabledList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.enabledConfigs) { item in
                    enabledRow(item)
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func enabledRow(_ item: TenantEmailConfigItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if !item.tenantName.isEmpty {
                    Text(item.tenantName)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.sidebarText(dark))
                }
                Text(item.displaySender)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(item.todaySentCount)/\(item.dailyEmailLimit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.sidebarText(dark))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppTheme.border(dark).opacity(0.5))
                            Capsule()
                                .fill(item.usageTone.color(dark: dark))
                                .frame(width: max(4, geo.size.width * CGFloat(item.usagePercent)))
                        }
                    }
                    .frame(height: 4)
                }
            }
            Spacer(minLength: 4)
            Button(action: { model.disableConfig(item) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "f85149"))
                    .padding(6)
                    .background(Color(hex: "f85149").opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("禁用邮件服务")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var disabledList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.disabledTenants) { item in
                    disabledRow(item)
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func disabledRow(_ item: DisabledTenantItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                        .lineLimit(1)
                    if !item.region.isEmpty {
                        Text(item.region)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    }
                }
                Spacer()
                AppButton(
                    title: model.expandingEnableId == item.id ? "收起" : "开启",
                    systemImage: "plus",
                    kind: .primary
                ) {
                    model.toggleEnableForm(item.id)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            if model.expandingEnableId == item.id {
                HStack(spacing: 8) {
                    AppTextField(
                        text: Binding(
                            get: { model.enableDomainDraft[item.id] ?? "" },
                            set: { model.enableDomainDraft[item.id] = $0 }
                        ),
                        placeholder: "example.com"
                    )
                    AppButton(title: "确认", systemImage: "checkmark", kind: .primary) {
                        model.submitEnable(item.id)
                    }
                    AppButton(title: "取消", kind: .secondary) {
                        model.toggleEnableForm(item.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .padding(.top, 2)
                .background(AppTheme.pageBg(dark).opacity(0.55))
            }
        }
    }

    // MARK: - Contacts panel

    private var contactPanel: some View {
        panelCard {
            panelHeader(
                title: "收件人",
                systemImage: "person.crop.rectangle.stack",
                trailing: {
                    HStack(spacing: 6) {
                        AppButton(title: "添加", systemImage: "plus", kind: .primary) {
                            model.openAddContact()
                        }
                        AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                            Task { await model.loadContacts() }
                        }
                    }
                }
            )

            Group {
                if model.contactsLoading && model.contacts.isEmpty {
                    loadingBox
                } else if model.contacts.isEmpty {
                    EmptyStateView(
                        icon: "person.crop.circle.badge.plus",
                        title: "暂无收件人",
                        subtitle: "添加收件人后即可发送邮件",
                        actionTitle: "添加收件人",
                        action: { model.openAddContact() }
                    )
                    .frame(minHeight: 160)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.contacts) { c in
                                contactRow(c)
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: .infinity)

            compactPager(
                state: model.contactPage,
                onPrev: {
                    model.contactPage.goPrev()
                    model.onContactPageChange()
                },
                onNext: {
                    model.contactPage.goNext()
                    model.onContactPageChange()
                }
            )
        }
    }

    private func contactRow(_ c: EmailContactItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name.isEmpty ? "—" : c.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                Text(c.email)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
            Spacer()
            Button(action: { model.deleteContact(c) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "f85149"))
                    .padding(6)
                    .background(Color(hex: "f85149").opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    // MARK: - Records

    private var recordsPanel: some View {
        panelCard {
            panelHeader(
                title: "发送记录",
                systemImage: "clock.arrow.circlepath",
                trailing: {
                    HStack(spacing: 6) {
                        AppButton(title: "清空", systemImage: "trash", kind: .danger) {
                            model.batchDeleteRecords()
                        }
                        AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                            Task { await model.loadRecords() }
                        }
                    }
                }
            )

            Group {
                if model.recordsLoading && model.records.isEmpty {
                    loadingBox
                } else if model.records.isEmpty {
                    EmptyStateView(
                        icon: "envelope",
                        title: "暂无发送记录",
                        subtitle: "发送邮件后将在此显示"
                    )
                    .frame(minHeight: 140)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.records) { r in
                            recordRow(r)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }

            if model.recordPage.totalElements > 0 {
                PaginationBar(state: $model.recordPage) {
                    model.onRecordPageChange()
                }
            }
        }
    }

    private func recordRow(_ r: EmailBodyItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: { model.openRecordDetail(r) }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.subjectText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        metaChip(r.createTime.isEmpty ? "—" : r.createTime)
                        metaChip(r.tenantText)
                        metaChip("收件 \(r.receiveTotal)")
                        Text("成功 \(r.receiveSuccessTotal)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(StatusTone.success.color(dark: dark))
                        Text("失败 \(r.receiveFailTotal)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(StatusTone.danger.color(dark: dark))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { model.deleteRecord(r) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "f85149"))
                    .padding(6)
                    .background(Color(hex: "f85149").opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.sidebarText(dark).opacity(0.6))
                .onTapGesture { model.openRecordDetail(r) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(AppTheme.sidebarText(dark))
            .lineLimit(1)
    }

    // MARK: - Shared chrome

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.sidebarBg(dark))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border(dark).opacity(0.7), lineWidth: 1)
        )
    }

    private func panelHeader<Trailing: View>(
        title: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.sidebarActive)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
            Spacer()
            trailing()
        }
    }

    private var loadingBox: some View {
        HStack {
            Spacer()
            ProgressView().scaleEffect(0.8)
            Text("加载中…")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
            Spacer()
        }
        .padding(.vertical, 40)
    }

    /// Compact prev/next for side panels (fixed page size from Web).
    private func compactPager(state: PageState, onPrev: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(state.isFirst)
            .opacity(state.isFirst ? 0.35 : 1)

            Text("\(state.displayPage) / \(max(state.totalPages, 1))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(AppTheme.sidebarText(dark))

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(state.isLast)
            .opacity(state.isLast ? 0.35 : 1)

            Spacer()
            Text(state.rangeText)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark).opacity(0.85))
        }
        .padding(.top, 4)
    }
}
