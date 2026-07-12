import SwiftUI

/// Native email management: tenant email on/off + contacts + send history (Web: /email/management)
struct EmailManageView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    /// 0 发信租户 · 1 收件人 · 2 发送记录
    @State private var tab = 0
    /// 0 已开启 · 1 未开启
    @State private var tenantSub = 0
    @State private var contacts: [EmailContact] = []
    @State private var bodies: [EmailBodyItem] = []
    @State private var senders: [EmailSenderConfig] = []
    @State private var notEnabledTenants: [Tenant] = []
    @State private var loading = false
    @State private var search = ""
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newEmail = ""
    @State private var deleteContact: EmailContact?
    @State private var showDeleteContact = false
    @State private var deleteBody: EmailBodyItem?
    @State private var showDeleteBody = false
    @State private var disableSender: EmailSenderConfig?
    @State private var showDisableSender = false
    @State private var showCompose = false
    @State private var detailBody: EmailBodyItem?
    @State private var enableTenant: Tenant?
    @State private var enableDomain = ""
    @State private var enabling = false

    var filteredContacts: [EmailContact] {
        guard !search.isEmpty else { return contacts }
        let q = search.lowercased()
        return contacts.filter {
            $0.name.lowercased().contains(q) || $0.email.lowercased().contains(q)
        }
    }

    var filteredBodies: [EmailBodyItem] {
        guard !search.isEmpty else { return bodies }
        let q = search.lowercased()
        return bodies.filter {
            $0.title.lowercased().contains(q)
                || $0.tenantName.lowercased().contains(q)
                || $0.senderEmail.lowercased().contains(q)
        }
    }

    var filteredSenders: [EmailSenderConfig] {
        guard !search.isEmpty else { return senders }
        let q = search.lowercased()
        return senders.filter {
            $0.label.lowercased().contains(q)
                || $0.domainName.lowercased().contains(q)
                || $0.tenantName.lowercased().contains(q)
        }
    }

    var filteredNotEnabled: [Tenant] {
        guard !search.isEmpty else { return notEnabledTenants }
        let q = search.lowercased()
        return notEnabledTenants.filter {
            $0.displayName.lowercased().contains(q)
                || ($0.region ?? "").lowercased().contains(q)
        }
    }

    private var searchPlaceholder: String {
        switch tab {
        case 0: return tenantSub == 0 ? "搜索发信邮箱 / 域名…" : "搜索租户名称…"
        case 1: return "搜索姓名 / 邮箱…"
        default: return "搜索主题 / 租户…"
        }
    }

    private var isEmptyLoading: Bool {
        if !loading { return false }
        switch tab {
        case 0: return tenantSub == 0 ? senders.isEmpty : notEnabledTenants.isEmpty
        case 1: return contacts.isEmpty
        default: return bodies.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("发信租户").tag(0)
                Text("收件人").tag(1)
                Text("发送记录").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, tab == 0 ? 6 : 10)

            if tab == 0 {
                Picker("", selection: $tenantSub) {
                    Text("已开启 (\(senders.count))").tag(0)
                    Text("未开启 (\(notEnabledTenants.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .onChange(of: tenantSub) { _ in
                    if tenantSub == 1 && notEnabledTenants.isEmpty {
                        Task { await loadNotEnabled() }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(AppTheme.muted(scheme))
                TextField(searchPlaceholder, text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(AppTheme.elevated(scheme))

            Divider()

            if isEmptyLoading {
                PageLoadingView()
            } else if tab == 0 {
                if tenantSub == 0 { enabledTenantsList } else { notEnabledTenantsList }
            } else if tab == 1 {
                contactsList
            } else {
                bodiesList
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("邮件管理")
        .toolbar {
            ToolbarItem {
                if loading || enabling { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: { showCompose = true }) {
                    Label("发信", systemImage: "paperplane")
                }
            }
            ToolbarItem {
                if tab == 1 {
                    Button(action: { showAdd = true }) {
                        Label("添加收件人", systemImage: "plus")
                    }
                }
            }
            ToolbarItem {
                Button(action: { Task { await loadAll() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { Task { await loadAll() } }
        .sheet(isPresented: $showAdd) { addContactSheet }
        .sheet(isPresented: $showCompose) {
            EmailComposeSheet(contacts: contacts, senders: senders) {
                Task { await loadBodies() }
            }
            .environmentObject(appState)
        }
        .sheet(item: $detailBody) { item in
            EmailBodyDetailSheet(item: item)
                .environmentObject(appState)
        }
        .sheet(item: $enableTenant) { t in
            enableEmailSheet(tenant: t)
        }
        .alert(isPresented: $showDeleteContact) {
            Alert(
                title: Text("删除收件人"),
                message: Text(deleteContact?.email ?? ""),
                primaryButton: .destructive(Text("删除")) {
                    guard let item = deleteContact else { return }
                    Task { await removeContact(item) }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showDeleteBody) {
            Alert(
                title: Text("删除发送记录"),
                message: Text(deleteBody?.title ?? ""),
                primaryButton: .destructive(Text("删除")) {
                    guard let item = deleteBody else { return }
                    Task { await removeBody(item) }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showDisableSender) {
            Alert(
                title: Text("关闭邮件服务"),
                message: Text(disableSender.map { "确定关闭 \($0.label)？" } ?? ""),
                primaryButton: .destructive(Text("关闭")) {
                    guard let item = disableSender else { return }
                    Task { await disableSenderConfig(item) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Enabled / not-enabled tenants

    private var enabledTenantsList: some View {
        Group {
            if filteredSenders.isEmpty {
                EmptyStateView(icon: "server.rack", title: "暂无已开启发信租户",
                               subtitle: "切换到「未开启」为 OCI 租户开通邮件域名")
            } else {
                List(filteredSenders) { item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .font(.callout.weight(.semibold))
                                .foregroundColor(AppTheme.text(scheme))
                                .lineLimit(1)
                            if !item.tenantName.isEmpty {
                                Text(item.tenantName)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.muted(scheme))
                            }
                            HStack(spacing: 8) {
                                if !item.domainName.isEmpty {
                                    Text(item.domainName)
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.muted(scheme))
                                }
                                Text("今日 \(item.todaySentCount)/\(item.dailyEmailLimit)")
                                    .font(.caption2)
                                    .foregroundColor(item.quotaColor)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(action: {
                            disableSender = item
                            showDisableSender = true
                        }) {
                            Text("关闭")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(AppTheme.pageBg(scheme))
                }
                .listStyle(.plain)
            }
        }
    }

    private var notEnabledTenantsList: some View {
        Group {
            if filteredNotEnabled.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "全部租户均已开启",
                               subtitle: "或当前没有 OCI 租户")
            } else {
                List(filteredNotEnabled) { t in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.displayName)
                                .foregroundColor(AppTheme.text(scheme))
                            Text(t.displayRegion)
                                .font(.caption)
                                .foregroundColor(AppTheme.muted(scheme))
                        }
                        Spacer()
                        Button("开启") {
                            enableDomain = ""
                            enableTenant = t
                        }
                        .buttonStyle(ProminentButton())
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(AppTheme.pageBg(scheme))
                }
                .listStyle(.plain)
            }
        }
    }

    private func enableEmailSheet(tenant: Tenant) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开启邮件服务").font(.headline)
            Text(tenant.displayName)
                .font(.callout)
                .foregroundColor(.secondary)
            Text("邮件域名（如 example.com）")
                .font(.caption)
                .foregroundColor(AppTheme.muted(scheme))
            TextField("example.com", text: $enableDomain)
                .textFieldStyle(.roundedBorder)
            Text("将通过 OCI Email Delivery 为该租户创建发信域名与发件人配置。")
                .font(.caption2)
                .foregroundColor(AppTheme.muted(scheme))
            HStack {
                Spacer()
                Button("取消") { enableTenant = nil }
                Button(enabling ? "开启中…" : "确认开启") {
                    Task { await enableEmail(for: tenant) }
                }
                .buttonStyle(ProminentButton())
                .disabled(enabling || enableDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 400)
    }

    // MARK: - Contacts

    private var contactsList: some View {
        Group {
            if filteredContacts.isEmpty {
                EmptyStateView(icon: "envelope", title: "暂无收件人",
                               subtitle: "点击右上角添加，或先配置发信租户")
            } else {
                List(filteredContacts) { item in
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundColor(AppTheme.text(scheme))
                            Text(item.email)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(AppTheme.muted(scheme))
                        }
                        Spacer()
                        Button(action: { deleteContact = item; showDeleteContact = true }) {
                            Image(systemName: "trash").foregroundColor(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(AppTheme.pageBg(scheme))
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Body records

    private var bodiesList: some View {
        Group {
            if filteredBodies.isEmpty {
                EmptyStateView(icon: "tray", title: "暂无发送记录",
                               subtitle: "点击右上角发信后将出现在此")
            } else {
                List(filteredBodies) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.callout.weight(.semibold))
                                .foregroundColor(AppTheme.text(scheme))
                                .lineLimit(1)
                            Text("\(item.timeText) · \(item.senderLabel)")
                                .font(.caption)
                                .foregroundColor(AppTheme.muted(scheme))
                            HStack(spacing: 10) {
                                Text("收件 \(item.receiveTotal)")
                                Text("成功 \(item.receiveSuccessTotal)").foregroundColor(AppTheme.success)
                                Text("失败 \(item.receiveFailTotal)").foregroundColor(AppTheme.danger)
                            }
                            .font(.caption2)
                            .foregroundColor(AppTheme.muted(scheme))
                        }
                        Spacer(minLength: 0)
                        Button(action: {
                            deleteBody = item
                            showDeleteBody = true
                        }) {
                            Image(systemName: "trash").foregroundColor(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { detailBody = item }
                    .listRowBackground(AppTheme.pageBg(scheme))
                }
                .listStyle(.plain)
            }
        }
    }

    private var addContactSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加收件人").font(.headline)
            TextField("姓名", text: $newName).textFieldStyle(.roundedBorder)
            TextField("邮箱", text: $newEmail).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { showAdd = false }
                Button("保存") { Task { await addContact() } }
                    .buttonStyle(ProminentButton())
                    .disabled(newName.isEmpty || newEmail.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    // MARK: - Data

    private func loadAll() async {
        loading = true
        defer { loading = false }
        async let c: () = loadContacts()
        async let b: () = loadBodies()
        async let s: () = loadSenders()
        async let n: () = loadNotEnabled()
        _ = await (c, b, s, n)
    }

    private func loadContacts() async {
        do {
            let arr = try await appState.network.emailReceiveList(baseURL: appState.serverURL)
            contacts = arr.compactMap { EmailContact(dict: $0) }
        } catch {
            appState.errorMessage = error.localizedDescription
            contacts = []
        }
    }

    private func loadBodies() async {
        do {
            let arr = try await appState.network.emailBodyList(baseURL: appState.serverURL)
            bodies = arr.compactMap { EmailBodyItem(dict: $0) }
        } catch {
            if tab == 2 { appState.errorMessage = error.localizedDescription }
            bodies = []
        }
    }

    private func loadSenders() async {
        do {
            let arr = try await appState.network.emailTenantConfigs(baseURL: appState.serverURL)
            senders = arr.compactMap { EmailSenderConfig(dict: $0) }
        } catch {
            if tab == 0 { appState.errorMessage = error.localizedDescription }
            senders = []
        }
    }

    private func loadNotEnabled() async {
        do {
            let resp = try await appState.network.getTenants(
                baseURL: appState.serverURL, page: 0, size: 100,
                keyword: nil, cloudType: 1, emailEnable: 0)
            notEnabledTenants = resp.content ?? []
        } catch {
            if tab == 0 && tenantSub == 1 {
                appState.errorMessage = error.localizedDescription
            }
            notEnabledTenants = []
        }
    }

    private func disableSenderConfig(_ item: EmailSenderConfig) async {
        do {
            let r = try await appState.network.emailConfigDisable(
                baseURL: appState.serverURL, configId: item.id)
            if r.success == false {
                appState.errorMessage = r.message ?? "关闭失败"
                return
            }
            appState.showToast(r.message ?? "已关闭邮件服务")
            await loadSenders()
            await loadNotEnabled()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func enableEmail(for tenant: Tenant) async {
        let domain = enableDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDomain(domain) else {
            appState.errorMessage = "域名格式不正确，请输入如 example.com"
            return
        }
        enabling = true
        defer { enabling = false }
        do {
            let r = try await appState.network.enableTenantEmail(
                baseURL: appState.serverURL, tenantId: tenant.id, emailDomain: domain)
            if r.success == false {
                appState.errorMessage = r.message ?? "开启失败"
                return
            }
            appState.showToast(r.message ?? "邮件服务已开启")
            enableTenant = nil
            enableDomain = ""
            tenantSub = 0
            await loadSenders()
            await loadNotEnabled()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func isValidDomain(_ domain: String) -> Bool {
        // simple host-like check aligned with web
        let pattern = #"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(\.[a-zA-Z]{2,})$"#
        return domain.range(of: pattern, options: .regularExpression) != nil
    }

    private func addContact() async {
        do {
            let r = try await appState.network.emailReceiveAdd(
                baseURL: appState.serverURL, name: newName, email: newEmail)
            if r.success == false {
                appState.errorMessage = r.message ?? "添加失败"
                return
            }
            appState.showToast(r.message ?? "已添加")
            newName = ""; newEmail = ""
            showAdd = false
            await loadContacts()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func removeContact(_ item: EmailContact) async {
        do {
            let r = try await appState.network.emailReceiveDelete(
                baseURL: appState.serverURL, id: item.id)
            appState.showToast(r.message ?? "已删除")
            await loadContacts()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func removeBody(_ item: EmailBodyItem) async {
        do {
            let r = try await appState.network.emailBodyDelete(
                baseURL: appState.serverURL, id: item.id)
            if r.success == false {
                appState.errorMessage = r.message ?? "删除失败"
                return
            }
            appState.showToast(r.message ?? "已删除")
            await loadBodies()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

}

// MARK: - Compose

struct EmailComposeSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var presentationMode

    let contacts: [EmailContact]
    let senders: [EmailSenderConfig]
    var onSent: () -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var senderId: Int64 = 0
    @State private var selected: Set<Int64> = []
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("发送邮件").font(.headline)

            if senders.isEmpty {
                Text("暂无可用发信租户，请先在「发信租户 → 未开启」中开通邮件域名")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Picker("发信账号", selection: $senderId) {
                    ForEach(senders) { s in
                        Text(s.label).tag(s.id)
                    }
                }
            }

            TextField("主题", text: $title).textFieldStyle(.roundedBorder)

            Text("正文").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $content)
                .frame(minHeight: 120, maxHeight: 180)
                .border(Color.secondary.opacity(0.3))

            Text("收件人").font(.caption).foregroundColor(.secondary)
            if contacts.isEmpty {
                Text("暂无收件人，请先添加").font(.caption).foregroundColor(.secondary)
            } else {
                List {
                    ForEach(contacts) { c in
                        Toggle(isOn: Binding(
                            get: { selected.contains(c.id) },
                            set: { on in
                                if on { selected.insert(c.id) } else { selected.remove(c.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name)
                                Text(c.email).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 200)
            }

            HStack {
                Spacer()
                Button("取消") { presentationMode.wrappedValue.dismiss() }
                Button(sending ? "发送中…" : "发送") { Task { await send() } }
                    .buttonStyle(ProminentButton())
                    .disabled(sending || title.isEmpty || content.isEmpty
                              || senderId == 0 || selected.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480, height: 560)
        .onAppear {
            if senderId == 0, let first = senders.first { senderId = first.id }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let r = try await appState.network.emailSend(
                baseURL: appState.serverURL,
                title: title,
                content: content,
                tenantEmailConfigId: senderId,
                emailReceiveIds: Array(selected))
            if r.success == false {
                appState.errorMessage = r.message ?? "发送失败"
                return
            }
            appState.showToast(r.message ?? "发送成功")
            onSent()
            presentationMode.wrappedValue.dismiss()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Detail

struct EmailBodyDetailSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.colorScheme) private var scheme
    let item: EmailBodyItem
    @State private var sends: [EmailSendItem] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.title).font(.headline)
                Spacer()
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
            }
            Text(item.senderLabel)
                .font(.caption)
                .foregroundColor(AppTheme.muted(scheme))
            Text(item.content.isEmpty ? "（无正文）" : item.content)
                .font(.callout)
                .foregroundColor(AppTheme.text(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppTheme.elevated(scheme))
                .cornerRadius(8)

            Text("收件明细").font(.subheadline.weight(.semibold))
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if sends.isEmpty {
                Text("暂无明细").font(.caption).foregroundColor(.secondary)
            } else {
                List(sends) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.receiveEmailAddress)
                                .font(.system(.callout, design: .monospaced))
                            Text(s.timeText).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(s.success ? "成功" : "失败")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(s.success ? AppTheme.success : AppTheme.danger)
                    }
                }
                .frame(minHeight: 160)
            }
        }
        .padding(22)
        .frame(width: 480, height: 420)
        .onAppear { Task { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let arr = try await appState.network.emailSendRecords(
                baseURL: appState.serverURL, emailBodyId: item.emailBodyId)
            sends = arr.compactMap { EmailSendItem(dict: $0) }
        } catch {
            appState.errorMessage = error.localizedDescription
            sends = []
        }
    }
}

// MARK: - Models (dict)

struct EmailContact: Identifiable {
    let id: Int64
    let name: String
    let email: String

    init?(dict: [String: Any]) {
        guard let id = DictID.int64(dict["id"]) else { return nil }
        self.id = id
        self.name = (dict["name"] as? String) ?? "—"
        self.email = (dict["email"] as? String) ?? "—"
    }
}

struct EmailSenderConfig: Identifiable {
    let id: Int64
    let senderEmail: String
    let tenantName: String
    let domainName: String
    let dailyEmailLimit: Int
    let todaySentCount: Int

    var label: String {
        if !senderEmail.isEmpty { return senderEmail }
        if !tenantName.isEmpty { return tenantName }
        if !domainName.isEmpty { return domainName }
        return "配置 #\(id)"
    }

    var quotaColor: Color {
        guard dailyEmailLimit > 0 else { return .secondary }
        let ratio = Double(todaySentCount) / Double(dailyEmailLimit)
        if ratio >= 0.9 { return AppTheme.danger }
        if ratio >= 0.7 { return AppTheme.warning }
        return .secondary
    }

    init?(dict: [String: Any]) {
        guard let id = DictID.int64(dict["id"]) else { return nil }
        self.id = id
        self.senderEmail = (dict["senderEmail"] as? String) ?? ""
        self.tenantName = (dict["tenantName"] as? String) ?? ""
        self.domainName = (dict["domainName"] as? String) ?? ""
        self.dailyEmailLimit = DictID.int(dict["dailyEmailLimit"]) ?? 200
        self.todaySentCount = DictID.int(dict["todaySentCount"]) ?? 0
    }
}

struct EmailBodyItem: Identifiable {
    let id: Int64
    let emailBodyId: String
    let title: String
    let content: String
    let tenantName: String
    let senderEmail: String
    let receiveTotal: Int
    let receiveSuccessTotal: Int
    let receiveFailTotal: Int
    let createTimeRaw: String

    var senderLabel: String {
        if !senderEmail.isEmpty { return senderEmail }
        if !tenantName.isEmpty { return tenantName }
        return "—"
    }

    var timeText: String {
        if createTimeRaw.count >= 16 { return String(createTimeRaw.prefix(16)).replacingOccurrences(of: "T", with: " ") }
        return createTimeRaw.isEmpty ? "—" : createTimeRaw
    }

    init?(dict: [String: Any]) {
        guard let id = DictID.int64(dict["id"]) else { return nil }
        self.id = id
        self.emailBodyId = (dict["emailBodyId"] as? String) ?? "\(id)"
        self.title = (dict["title"] as? String) ?? "（无主题）"
        self.content = (dict["content"] as? String) ?? ""
        self.tenantName = (dict["tenantName"] as? String) ?? ""
        self.senderEmail = (dict["senderEmail"] as? String) ?? ""
        self.receiveTotal = DictID.int(dict["receiveTotal"]) ?? 0
        self.receiveSuccessTotal = DictID.int(dict["receiveSuccessTotal"]) ?? 0
        self.receiveFailTotal = DictID.int(dict["receiveFailTotal"]) ?? 0
        self.createTimeRaw = DictID.timeString(dict["createTime"])
    }
}

struct EmailSendItem: Identifiable {
    let id: Int64
    let receiveEmailAddress: String
    let success: Bool
    let createTimeRaw: String

    var timeText: String {
        if createTimeRaw.count >= 16 { return String(createTimeRaw.prefix(16)).replacingOccurrences(of: "T", with: " ") }
        return createTimeRaw.isEmpty ? "—" : createTimeRaw
    }

    init?(dict: [String: Any]) {
        guard let id = DictID.int64(dict["id"]) else { return nil }
        self.id = id
        self.receiveEmailAddress = (dict["receiveEmailAddress"] as? String) ?? "—"
        if let s = dict["sendState"] as? Int { self.success = s == 1 }
        else if let s = dict["sendState"] as? Bool { self.success = s }
        else { self.success = false }
        self.createTimeRaw = DictID.timeString(dict["createTime"])
    }
}

enum DictID {
    static func int64(_ v: Any?) -> Int64? {
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let i = v as? String { return Int64(i) }
        if let i = v as? Double { return Int64(i) }
        return nil
    }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let i = v as? Int64 { return Int(i) }
        if let i = v as? String { return Int(i) }
        if let i = v as? Double { return Int(i) }
        return nil
    }

    static func timeString(_ v: Any?) -> String {
        if let s = v as? String { return s }
        // Jackson LocalDateTime array: [y,m,d,h,m,s]
        if let arr = v as? [Any], arr.count >= 3 {
            let nums = arr.compactMap { int($0) }
            if nums.count >= 3 {
                let y = nums[0], m = nums[1], d = nums[2]
                let hh = nums.count > 3 ? nums[3] : 0
                let mm = nums.count > 4 ? nums[4] : 0
                return String(format: "%04d-%02d-%02d %02d:%02d", y, m, d, hh, mm)
            }
        }
        return ""
    }
}
