import Foundation
import Combine

/// ViewModel for Web `/email/management` — tenants / contacts / send / records.
@MainActor
final class EmailViewModel: ObservableObject {

    // MARK: - Lists

    @Published private(set) var enabledConfigs: [TenantEmailConfigItem] = []
    @Published private(set) var disabledTenants: [DisabledTenantItem] = []
    @Published private(set) var contacts: [EmailContactItem] = []
    @Published private(set) var records: [EmailBodyItem] = []
    @Published private(set) var detailRecipients: [EmailSendRecordItem] = []

    @Published var tenantTab: EmailTenantTab = .enabled
    @Published var tenantSearch = ""
    @Published var enableDomainDraft: [Int64: String] = [:]
    @Published var expandingEnableId: Int64?

    @Published var enabledPage = PageState(page: 0, size: 5)
    @Published var disabledPage = PageState(page: 0, size: 5)
    @Published var contactPage = PageState(page: 0, size: 10)
    @Published var recordPage = PageState(page: 0, size: 10)
    @Published var detailPage = PageState(page: 0, size: 10)

    @Published private(set) var enabledTotal: Int64 = 0
    @Published private(set) var disabledTotal: Int64 = 0

    // MARK: - Loading / errors

    @Published private(set) var isLoading = false
    @Published private(set) var tenantsLoading = false
    @Published private(set) var contactsLoading = false
    @Published private(set) var recordsLoading = false
    @Published private(set) var detailLoading = false
    @Published private(set) var errorText: String?

    // MARK: - Sheets / forms

    @Published var activeSheet: EmailSheet?
    @Published var formBusy = false
    @Published var formError: String?

    // Compose
    @Published var composeTitle = ""
    @Published var composeContent = ""
    @Published var composeConfigId: Int64 = 0
    @Published var composeSelectedIds: Set<Int64> = []
    @Published var composeContacts: [EmailContactItem] = []
    @Published var composeConfigs: [TenantEmailConfigItem] = []

    // Add contact
    @Published var newContactName = ""
    @Published var newContactEmail = ""

    // Detail
    @Published private(set) var detailRecord: EmailBodyItem?

    private let session: AppSession
    private var service: EmailService { EmailService(baseURL: session.serverURL) }
    private var searchTask: Task<Void, Never>?

    init(session: AppSession = .shared) {
        self.session = session
    }

    // MARK: - Lifecycle

    func start() {
        Task { await reloadAll() }
    }

    func reloadAll() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        async let t: Void = loadCurrentTenantTab()
        async let badge: Void = refreshOtherTenantBadge()
        async let c: Void = loadContacts()
        async let r: Void = loadRecords()
        _ = await (t, badge, c, r)
    }

    /// Keep both tab badges roughly accurate without switching tabs.
    private func refreshOtherTenantBadge() async {
        do {
            if tenantTab == .enabled {
                let resp = try await service.listDisabledTenants(page: 0, size: 1, keyword: nil)
                disabledTotal = resp.totalElements
            } else {
                let resp = try await service.listEnabledConfigs(pageNum: 1, pageSize: 1)
                enabledTotal = resp.totalElements
            }
        } catch {
            // badge is best-effort
        }
    }

    // MARK: - Tenants

    func switchTenantTab(_ tab: EmailTenantTab) {
        guard tenantTab != tab else { return }
        tenantTab = tab
        tenantSearch = ""
        expandingEnableId = nil
        if tab == .enabled {
            enabledPage.page = 0
        } else {
            disabledPage.page = 0
        }
        Task { await loadCurrentTenantTab() }
    }

    func onTenantSearchChanged(_ text: String) {
        tenantSearch = text
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            if tenantTab == .enabled {
                enabledPage.page = 0
            } else {
                disabledPage.page = 0
            }
            await loadCurrentTenantTab()
        }
    }

    func refreshTenants() {
        tenantSearch = ""
        expandingEnableId = nil
        if tenantTab == .enabled {
            enabledPage.page = 0
        } else {
            disabledPage.page = 0
        }
        Task { await loadCurrentTenantTab() }
    }

    func onEnabledPageChange() {
        Task { await loadEnabledConfigs() }
    }

    func onDisabledPageChange() {
        Task { await loadDisabledTenants() }
    }

    func loadCurrentTenantTab() async {
        if tenantTab == .enabled {
            await loadEnabledConfigs()
        } else {
            await loadDisabledTenants()
        }
    }

    func loadEnabledConfigs() async {
        tenantsLoading = true
        defer { tenantsLoading = false }
        do {
            let resp = try await service.listEnabledConfigs(
                pageNum: enabledPage.page + 1,
                pageSize: enabledPage.size
            )
            // Client-side keyword filter (API has no search on enabled list)
            let kw = tenantSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if kw.isEmpty {
                enabledConfigs = resp.content
            } else {
                enabledConfigs = resp.content.filter {
                    $0.displaySender.lowercased().contains(kw)
                        || $0.tenantName.lowercased().contains(kw)
                        || $0.domainName.lowercased().contains(kw)
                }
            }
            enabledPage.apply(totalElements: resp.totalElements, totalPages: resp.totalPages)
            enabledTotal = resp.totalElements
        } catch {
            enabledConfigs = []
            handleError(error)
        }
    }

    func loadDisabledTenants() async {
        tenantsLoading = true
        defer { tenantsLoading = false }
        do {
            let kw = tenantSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            let resp = try await service.listDisabledTenants(
                page: disabledPage.page,
                size: disabledPage.size,
                keyword: kw.isEmpty ? nil : kw
            )
            disabledTenants = resp.content
            disabledPage.apply(totalElements: resp.totalElements, totalPages: resp.totalPages)
            disabledTotal = resp.totalElements
        } catch {
            disabledTenants = []
            handleError(error)
        }
    }

    func toggleEnableForm(_ tenantId: Int64) {
        if expandingEnableId == tenantId {
            expandingEnableId = nil
        } else {
            expandingEnableId = tenantId
            if enableDomainDraft[tenantId] == nil {
                enableDomainDraft[tenantId] = ""
            }
        }
    }

    func submitEnable(_ tenantId: Int64) {
        let domain = (enableDomainDraft[tenantId] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else {
            ToastCenter.shared.error("请输入邮箱域名")
            return
        }
        let pattern = #"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(\.[a-zA-Z]{2,})$"#
        guard domain.range(of: pattern, options: .regularExpression) != nil else {
            ToastCenter.shared.error("域名格式错误，如 example.com")
            return
        }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.enableEmail(tenantId: tenantId, domain: domain)
                expandingEnableId = nil
                enableDomainDraft[tenantId] = nil
                disabledPage.page = 0
                await loadDisabledTenants()
                await loadEnabledConfigs()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func disableConfig(_ item: TenantEmailConfigItem) {
        guard AppAlert.confirm(
            title: "禁用邮件服务",
            message: "确定禁用 \(item.displaySender) 的邮件服务？相关配置将被清理。"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.disableEmail(configId: item.id)
                await loadEnabledConfigs()
                if tenantTab == .disabled {
                    await loadDisabledTenants()
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    // MARK: - Contacts

    func onContactPageChange() {
        Task { await loadContacts() }
    }

    func loadContacts() async {
        contactsLoading = true
        defer { contactsLoading = false }
        do {
            let resp = try await service.listContacts(
                pageNum: contactPage.page + 1,
                pageSize: contactPage.size
            )
            contacts = resp.content
            contactPage.apply(totalElements: resp.totalElements, totalPages: resp.totalPages)
        } catch {
            contacts = []
            handleError(error)
        }
    }

    func openAddContact() {
        newContactName = ""
        newContactEmail = ""
        formError = nil
        formBusy = false
        activeSheet = .addContact
    }

    func submitAddContact() {
        let name = newContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = newContactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !email.isEmpty else {
            formError = "请填写姓名与邮箱"
            return
        }
        guard email.contains("@"), email.contains(".") else {
            formError = "邮箱格式不正确"
            return
        }
        formBusy = true
        formError = nil
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.addContact(name: name, email: email)
                activeSheet = nil
                await loadContacts()
            } catch {
                formError = error.localizedDescription
                ToastCenter.shared.error(error.localizedDescription)
            }
            formBusy = false
            LoadingHUD.shared.end()
        }
    }

    func deleteContact(_ item: EmailContactItem) {
        guard AppAlert.confirm(
            title: "删除收件人",
            message: "确定删除 \(item.name)（\(item.email)）？"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.deleteContact(id: item.id)
                await loadContacts()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    // MARK: - Compose / send

    func openCompose() {
        composeTitle = ""
        composeContent = ""
        composeConfigId = 0
        composeSelectedIds = []
        composeContacts = []
        composeConfigs = enabledConfigs
        formError = nil
        formBusy = false
        activeSheet = .compose
        Task {
            do {
                let configs = try await service.listEnabledConfigs(pageNum: 1, pageSize: 100)
                composeConfigs = configs.content
                if composeConfigId == 0, let first = configs.content.first {
                    composeConfigId = first.id
                }
            } catch {
                if composeConfigId == 0, let first = composeConfigs.first {
                    composeConfigId = first.id
                }
            }
            do {
                let list = try await service.listContacts(pageNum: 1, pageSize: 100)
                composeContacts = list.content
            } catch {
                composeContacts = contacts
            }
        }
    }

    func toggleComposeRecipient(_ id: Int64) {
        if composeSelectedIds.contains(id) {
            composeSelectedIds.remove(id)
        } else {
            composeSelectedIds.insert(id)
        }
    }

    func selectAllComposeRecipients() {
        composeSelectedIds = Set(composeContacts.map(\.id))
    }

    func clearComposeRecipients() {
        composeSelectedIds = []
    }

    func submitSend() {
        let title = composeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = composeContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !content.isEmpty else {
            formError = "请填写主题与内容"
            return
        }
        guard composeConfigId > 0 else {
            formError = "请选择发件租户"
            return
        }
        guard !composeSelectedIds.isEmpty else {
            formError = "请至少选择一位收件人"
            return
        }
        formBusy = true
        formError = nil
        let ids = Array(composeSelectedIds)
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.sendEmail(
                    title: title,
                    content: content,
                    tenantEmailConfigId: composeConfigId,
                    receiveIds: ids
                )
                activeSheet = nil
                await loadRecords()
                await loadEnabledConfigs()
            } catch {
                formError = error.localizedDescription
                ToastCenter.shared.error(error.localizedDescription)
            }
            formBusy = false
            LoadingHUD.shared.end()
        }
    }

    // MARK: - Records

    func onRecordPageChange() {
        Task { await loadRecords() }
    }

    func loadRecords() async {
        recordsLoading = true
        defer { recordsLoading = false }
        do {
            let resp = try await service.listBodies(
                pageNum: recordPage.page + 1,
                pageSize: recordPage.size
            )
            records = resp.content
            recordPage.apply(totalElements: resp.totalElements, totalPages: resp.totalPages)
        } catch {
            records = []
            handleError(error)
        }
    }

    func openRecordDetail(_ item: EmailBodyItem) {
        detailRecord = item
        detailRecipients = []
        detailPage = PageState(page: 0, size: 10)
        formError = nil
        activeSheet = .recordDetail(item)
        Task { await loadDetailRecipients() }
    }

    func onDetailPageChange() {
        Task { await loadDetailRecipients() }
    }

    func loadDetailRecipients() async {
        guard let bodyId = detailRecord?.emailBodyId, !bodyId.isEmpty else {
            detailRecipients = []
            return
        }
        detailLoading = true
        defer { detailLoading = false }
        do {
            let resp = try await service.listSendRecords(
                emailBodyId: bodyId,
                pageNum: detailPage.page + 1,
                pageSize: detailPage.size
            )
            detailRecipients = resp.content
            detailPage.apply(totalElements: resp.totalElements, totalPages: resp.totalPages)
        } catch {
            detailRecipients = []
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func deleteRecord(_ item: EmailBodyItem) {
        guard AppAlert.confirm(
            title: "删除发送记录",
            message: "确定删除「\(item.subjectText)」及其收件明细？"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.deleteBody(id: item.id)
                if case .recordDetail(let cur) = activeSheet, cur.id == item.id {
                    activeSheet = nil
                }
                await loadRecords()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func batchDeleteRecords() {
        guard AppAlert.confirm(
            title: "清空全部记录",
            message: "确定删除全部邮件发送记录？此操作不可恢复。"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.batchDeleteBodies()
                recordPage.page = 0
                await loadRecords()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    // MARK: - Helpers

    private func handleError(_ error: Error) {
        errorText = error.localizedDescription
        if case APIError.unauthorized = error { return }
        ToastCenter.shared.error(error.localizedDescription)
    }

    var composeConfigOptions: [SelectOption] {
        var seen = Set<Int64>()
        var opts: [SelectOption] = []
        for c in composeConfigs {
            guard c.id > 0, !seen.contains(c.id) else { continue }
            seen.insert(c.id)
            let title = c.senderEmail.isEmpty ? c.displaySender : c.senderEmail
            let suffix = c.tenantName.isEmpty ? "" : " · \(c.tenantName)"
            opts.append(SelectOption(id: "\(c.id)", title: title + suffix))
        }
        return opts
    }
}
