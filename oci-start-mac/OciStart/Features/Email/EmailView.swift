import SwiftUI

/// 原生邮件管理（对齐 Web `/email/management` · `email.ftl`）。
/// 列表类页面：主分区 Tab + FilterBar + 卡片/DataList + PaginationBar（对齐质量管理视觉体系）。
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
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    mainSectionBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    filterBar
                    sectionBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .appLoading(pageLoading)
            },
            footer: { paginationFooter }
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

    private var pageLoading: Bool {
        switch model.mainSection {
        case .tenants: return model.tenantsLoading && currentTenantEmpty
        case .contacts: return model.contactsLoading && model.contacts.isEmpty
        case .records: return model.recordsLoading && model.records.isEmpty
        }
    }

    private var currentTenantEmpty: Bool {
        model.tenantTab == .enabled ? model.enabledConfigs.isEmpty : model.disabledTenants.isEmpty
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "发送邮件", systemImage: "square.and.pencil", kind: .primary) {
                model.openCompose()
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.isLoading || sectionBusy
            ) {
                Task { await model.reloadAll() }
            }
        }
    }

    private var sectionBusy: Bool {
        switch model.mainSection {
        case .tenants: return model.tenantsLoading
        case .contacts: return model.contactsLoading
        case .records: return model.recordsLoading
        }
    }

    // MARK: - Main section tabs

    private var mainSectionBar: some View {
        HStack(spacing: 8) {
            ForEach(EmailMainSection.allCases) { section in
                sectionTab(section)
            }
        }
    }

    private func sectionTab(_ section: EmailMainSection) -> some View {
        let active = model.mainSection == section
        let count = sectionBadge(section)
        return Button(action: { model.switchMainSection(section) }) {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(section.title)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(active ? .white : AppTheme.sidebarText(dark))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(active ? AppTheme.sidebarActive : AppTheme.border(dark).opacity(0.55))
                        )
                }
            }
            .foregroundColor(active ? AppTheme.sidebarActive : AppTheme.sidebarText(dark))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? AppTheme.sidebarActive.opacity(0.12) : AppTheme.sidebarBg(dark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        active ? AppTheme.sidebarActive.opacity(0.45) : AppTheme.border(dark).opacity(0.7),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    private func sectionBadge(_ section: EmailMainSection) -> Int64? {
        switch section {
        case .tenants:
            return model.tenantTab == .enabled ? model.enabledTotal : model.disabledTotal
        case .contacts:
            return model.contactPage.totalElements
        case .records:
            return model.recordPage.totalElements
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        FilterBar(
            leading: {
                Group {
                    switch model.mainSection {
                    case .tenants:
                        HStack(spacing: 10) {
                            tenantSubTabs
                            SearchField(
                                text: Binding(
                                    get: { model.tenantSearch },
                                    set: { model.onTenantSearchChanged($0) }
                                ),
                                placeholder: "搜索租户 / 发件地址…",
                                fillsWidth: true
                            )
                            .frame(maxWidth: 280)
                        }
                    case .contacts:
                        Text("管理常用收件人，发送邮件时可多选")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    case .records:
                        Text("查看历史发送结果与收件明细")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    }
                }
            },
            trailing: {
                Group {
                    switch model.mainSection {
                    case .tenants:
                        AppButton(
                            title: "刷新",
                            systemImage: "arrow.clockwise",
                            kind: .secondary,
                            isLoading: model.tenantsLoading
                        ) {
                            model.refreshTenants()
                        }
                    case .contacts:
                        HStack(spacing: 8) {
                            AppButton(title: "添加", systemImage: "plus", kind: .primary) {
                                model.openAddContact()
                            }
                            AppButton(
                                title: "刷新",
                                systemImage: "arrow.clockwise",
                                kind: .secondary,
                                isLoading: model.contactsLoading
                            ) {
                                Task { await model.loadContacts() }
                            }
                        }
                    case .records:
                        HStack(spacing: 8) {
                            AppButton(title: "清空", systemImage: "trash", kind: .danger) {
                                model.batchDeleteRecords()
                            }
                            AppButton(
                                title: "刷新",
                                systemImage: "arrow.clockwise",
                                kind: .secondary,
                                isLoading: model.recordsLoading
                            ) {
                                Task { await model.loadRecords() }
                            }
                        }
                    }
                }
            }
        )
    }

    private var tenantSubTabs: some View {
        HStack(spacing: 0) {
            ForEach(EmailTenantTab.allCases) { tab in
                let active = model.tenantTab == tab
                let count = tab == .enabled ? model.enabledTotal : model.disabledTotal
                Button(action: { model.switchTenantTab(tab) }) {
                    HStack(spacing: 5) {
                        Text(tab.title)
                            .font(.system(size: 12, weight: active ? .semibold : .regular))
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(active ? .white : AppTheme.sidebarText(dark).opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(active ? AppTheme.sidebarActive : AppTheme.border(dark).opacity(0.5))
                            )
                    }
                    .foregroundColor(active ? AppTheme.sidebarActive : AppTheme.sidebarText(dark))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(active ? AppTheme.sidebarActive.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.pageBg(dark).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - Section body

    @ViewBuilder
    private var sectionBody: some View {
        switch model.mainSection {
        case .tenants:
            tenantsBody
        case .contacts:
            contactsBody
        case .records:
            recordsBody
        }
    }

    // MARK: Tenants

    private var tenantsBody: some View {
        Group {
            if model.tenantsLoading && currentTenantEmpty {
                loadingBox
            } else if currentTenantEmpty {
                EmptyStateView(
                    icon: model.tenantTab == .enabled ? "server.rack" : "checkmark.circle",
                    title: model.tenantTab == .enabled ? "暂无已开启租户" : "全部租户均已开启",
                    subtitle: model.tenantTab == .enabled
                        ? "可在「未开启」中为租户启用邮件服务"
                        : "没有待开启的租户",
                    actionTitle: model.tenantTab == .enabled ? "查看未开启" : nil,
                    action: model.tenantTab == .enabled
                        ? { model.switchTenantTab(.disabled) }
                        : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.tenantTab == .enabled {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.enabledConfigs) { item in
                            enabledCard(item)
                        }
                    }
                    .padding(16)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.disabledTenants) { item in
                            disabledCard(item)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func enabledCard(_ item: TenantEmailConfigItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "4a9eff").opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "4a9eff"))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.displaySender)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                        .lineLimit(1)
                    StatusBadge(text: "运行中", tone: .success)
                }
                if !item.tenantName.isEmpty {
                    Text(item.tenantName)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.sidebarText(dark))
                        .lineLimit(1)
                }
                usageBar(item)
            }

            Spacer(minLength: 8)

            AppButton(title: "禁用", systemImage: "trash", kind: .danger) {
                model.disableConfig(item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardStroke(accent: Color(hex: "4a9eff"), active: true))
        .shadow(color: Color.black.opacity(dark ? 0.18 : 0.05), radius: 8, y: 2)
    }

    private func usageBar(_ item: TenantEmailConfigItem) -> some View {
        HStack(spacing: 10) {
            Text("今日 \(item.todaySentCount)/\(item.dailyEmailLimit)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.sidebarText(dark))
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.border(dark).opacity(0.45))
                    Capsule()
                        .fill(item.usageTone.color(dark: dark))
                        .frame(width: max(6, geo.size.width * CGFloat(item.usagePercent)))
                }
            }
            .frame(height: 6)
            .frame(maxWidth: 220)
            Text("\(Int(item.usagePercent * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(item.usageTone.color(dark: dark))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func disabledCard(_ item: DisabledTenantItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "9b59b6").opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "plus.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "9b59b6"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                    .lineLimit(1)
                Text(item.region.isEmpty ? "未开启邮件服务" : item.region)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            AppButton(title: "开启服务", systemImage: "plus", kind: .primary) {
                model.openEnableTenant(item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardStroke(accent: Color(hex: "9b59b6"), active: false))
        .shadow(color: Color.black.opacity(dark ? 0.18 : 0.05), radius: 8, y: 2)
    }

    // MARK: Contacts

    private var contactsBody: some View {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.contacts) { c in
                            contactCard(c)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func contactCard(_ c: EmailContactItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "3fb950").opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(avatarLetter(c))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "3fb950"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(c.name.isEmpty ? "—" : c.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                    .lineLimit(1)
                Text(c.email)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !c.createTime.isEmpty {
                Text(c.createTime)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark).opacity(0.85))
            }

            AppButton(title: "删除", systemImage: "trash", kind: .danger) {
                model.deleteContact(c)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardStroke(accent: Color(hex: "3fb950"), active: false))
        .shadow(color: Color.black.opacity(dark ? 0.18 : 0.05), radius: 8, y: 2)
    }

    private func avatarLetter(_ c: EmailContactItem) -> String {
        let base = c.name.isEmpty ? c.email : c.name
        return String(base.prefix(1)).uppercased()
    }

    // MARK: Records

    private var recordsBody: some View {
        Group {
            if model.recordsLoading && model.records.isEmpty {
                loadingBox
            } else if model.records.isEmpty {
                EmptyStateView(
                    icon: "envelope",
                    title: "暂无发送记录",
                    subtitle: "发送邮件后将在此显示",
                    actionTitle: "发送邮件",
                    action: { model.openCompose() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataList {
                    DataListColumnHeader(title: "主题", width: nil)
                    DataListColumnHeader(title: "时间", width: 150)
                    DataListColumnHeader(title: "租户", width: 120)
                    DataListColumnHeader(title: "收件", width: 56)
                    DataListColumnHeader(title: "成功", width: 56)
                    DataListColumnHeader(title: "失败", width: 56)
                    DataListColumnHeader(title: "操作", width: 120, alignment: .trailing)
                } content: {
                    ForEach(model.records) { r in
                        DataListRow(action: { model.openRecordDetail(r) }) {
                            recordRow(r)
                        }
                    }
                }
            }
        }
    }

    private func recordRow(_ r: EmailBodyItem) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(r.subjectText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                    .lineLimit(1)
                if !r.senderEmail.isEmpty {
                    Text(r.senderEmail)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.sidebarText(dark))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(r.createTime.isEmpty ? "—" : r.createTime)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)

            Text(r.tenantText)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)

            Text("\(r.receiveTotal)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 56, alignment: .leading)

            Text("\(r.receiveSuccessTotal)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(StatusTone.success.color(dark: dark))
                .frame(width: 56, alignment: .leading)

            Text("\(r.receiveFailTotal)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(
                    r.receiveFailTotal > 0
                        ? StatusTone.danger.color(dark: dark)
                        : AppTheme.sidebarText(dark)
                )
                .frame(width: 56, alignment: .leading)

            HStack(spacing: 6) {
                AppButton(title: "详情", kind: .secondary) {
                    model.openRecordDetail(r)
                }
                AppButton(title: "删除", systemImage: "trash", kind: .danger) {
                    model.deleteRecord(r)
                }
            }
            .frame(width: 120, alignment: .trailing)
        }
    }

    // MARK: - Pagination

    @ViewBuilder
    private var paginationFooter: some View {
        switch model.mainSection {
        case .tenants:
            if model.tenantTab == .enabled {
                PaginationBar(state: $model.enabledPage) {
                    model.onEnabledPageChange()
                }
            } else {
                PaginationBar(state: $model.disabledPage) {
                    model.onDisabledPageChange()
                }
            }
        case .contacts:
            PaginationBar(state: $model.contactPage) {
                model.onContactPageChange()
            }
        case .records:
            PaginationBar(state: $model.recordPage) {
                model.onRecordPageChange()
            }
        }
    }

    // MARK: - Shared chrome

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(AppTheme.sidebarBg(dark))
    }

    private func cardStroke(accent: Color, active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(
                active
                    ? accent.opacity(dark ? 0.35 : 0.28)
                    : AppTheme.border(dark).opacity(0.7),
                lineWidth: 1
            )
    }

    private var loadingBox: some View {
        HStack {
            Spacer()
            ProgressView().scaleEffect(0.85)
            Text("加载中…")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f85149"))
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
}
