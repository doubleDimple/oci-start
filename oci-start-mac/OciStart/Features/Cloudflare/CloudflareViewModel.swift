import Foundation
import Combine

/// ViewModel for Web `/dns/cloudflare`.
@MainActor
final class CloudflareViewModel: ObservableObject {
    @Published private(set) var zones: [CfZone] = []
    @Published var selectedZoneId: String?
    @Published private(set) var records: [CfDnsRecord] = []
    @Published var pageState = PageState(page: 0, size: 20)
    @Published var searchName = ""
    @Published var searchContent = ""

    @Published var dnsForm: CfDnsForm?
    @Published var configForm: CfConfigForm?
    @Published private(set) var isLoading = false
    @Published private(set) var isZonesLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isConfigSaving = false
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: CloudflareService { CloudflareService(baseURL: session.serverURL) }

    var zoneOptions: [SelectOption] {
        zones.map { SelectOption(id: $0.id, title: $0.title) }
    }

    var selectedZoneName: String {
        zones.first(where: { $0.id == selectedZoneId })?.name ?? ""
    }

    var filteredRecords: [CfDnsRecord] {
        let n = searchName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = searchContent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n.isEmpty && c.isEmpty { return records }
        return records.filter { r in
            let nameOK = n.isEmpty || r.name.lowercased().contains(n)
            let contentOK = c.isEmpty || r.content.lowercased().contains(c)
            return nameOK && contentOK
        }
    }

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task { await loadZones(selectFirst: true) }
    }

    func loadZones(selectFirst: Bool) async {
        isZonesLoading = true
        errorText = nil
        defer { isZonesLoading = false }
        do {
            let list = try await service.fetchZones()
            zones = list
            if selectFirst {
                if selectedZoneId == nil || !list.contains(where: { $0.id == selectedZoneId }) {
                    selectedZoneId = list.first?.id
                    pageState.page = 0
                }
            }
            if let zid = selectedZoneId, !zid.isEmpty {
                await reloadRecords()
            } else {
                records = []
                pageState.apply(totalElements: 0, totalPages: 0)
            }
        } catch {
            zones = []
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func onZoneChange(_ zoneId: String?) {
        selectedZoneId = zoneId
        pageState.page = 0
        searchName = ""
        searchContent = ""
        Task { await reloadRecords() }
    }

    func reloadRecords() async {
        guard let zoneId = selectedZoneId, !zoneId.isEmpty else {
            records = []
            pageState.apply(totalElements: 0, totalPages: 0)
            return
        }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            // API page is 1-based
            let result = try await service.fetchRecords(
                zoneId: zoneId,
                page: pageState.page + 1,
                size: pageState.size
            )
            records = result.items
            pageState.apply(totalElements: result.total, totalPages: result.pages)
        } catch {
            records = []
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func onPageChange() {
        Task { await reloadRecords() }
    }

    func clearSearch() {
        searchName = ""
        searchContent = ""
    }

    // MARK: - DNS form

    func openAdd() {
        guard selectedZoneId != nil else {
            ToastCenter.shared.error("请先选择域名")
            return
        }
        dnsForm = .empty()
    }

    func openEdit(_ record: CfDnsRecord) {
        dnsForm = .edit(record)
    }

    func closeDnsForm() {
        dnsForm = nil
    }

    func saveDnsForm() {
        Task { await performSaveDns() }
    }

    private func performSaveDns() async {
        guard var form = dnsForm, let zoneId = selectedZoneId else { return }
        form.name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        form.content = form.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !form.name.isEmpty, !form.content.isEmpty else {
            ToastCenter.shared.error("请填写记录名与记录值")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await LoadingHUD.shared.during {
                if form.isEditing {
                    try await service.updateRecord(
                        recordId: form.recordId,
                        zoneId: zoneId,
                        type: form.type,
                        name: form.name,
                        content: form.content,
                        ttl: form.ttl,
                        proxied: form.proxied
                    )
                } else {
                    try await service.createRecord(
                        zoneId: zoneId,
                        type: form.type,
                        name: form.name,
                        content: form.content,
                        ttl: form.ttl,
                        proxied: form.proxied
                    )
                }
            }
            dnsForm = nil
            ToastCenter.shared.success(form.isEditing ? "记录已更新" : "记录已创建")
            await reloadRecords()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func delete(_ record: CfDnsRecord) {
        Task { await performDelete(record) }
    }

    private func performDelete(_ record: CfDnsRecord) async {
        guard let zoneId = selectedZoneId else { return }
        let ok = AppAlert.confirm(
            title: "删除 DNS 记录",
            message: "确认删除 \(record.name)？此操作不可撤销。",
            confirmTitle: "删除"
        )
        guard ok else { return }
        do {
            try await LoadingHUD.shared.during {
                try await service.deleteRecord(recordId: record.id, zoneId: zoneId)
            }
            ToastCenter.shared.success("已删除")
            await reloadRecords()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func syncRecords() {
        Task { await performSync() }
    }

    private func performSync() async {
        guard let zoneId = selectedZoneId else {
            ToastCenter.shared.error("请先选择域名")
            return
        }
        let name = selectedZoneName
        guard !name.isEmpty else {
            ToastCenter.shared.error("无法获取域名名称")
            return
        }
        let ok = AppAlert.confirm(
            title: "同步 DNS 记录",
            message: "将从 Cloudflare 拉取 \(name) 的解析记录到本地数据库。",
            confirmTitle: "同步"
        )
        guard ok else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let msg = try await LoadingHUD.shared.during {
                try await service.syncZone(zoneId: zoneId, domainName: name)
            }
            AppAlert.info(title: "同步完成", message: msg)
            await reloadRecords()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Config sheet

    func openConfig() {
        Task { await loadConfigForm() }
    }

    private func loadConfigForm() async {
        do {
            configForm = try await LoadingHUD.shared.during {
                try await service.fetchConfig()
            }
        } catch {
            // still open empty form so user can paste keys
            configForm = CfConfigForm()
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func closeConfig() {
        configForm = nil
    }

    func saveConfig() {
        Task { await performSaveConfig() }
    }

    private func performSaveConfig() async {
        guard var form = configForm else { return }
        form.apiToken = form.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        form.email = form.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if form.enabled, form.apiToken.isEmpty || form.email.isEmpty {
            ToastCenter.shared.error("启用时请填写 API Key 与邮箱")
            return
        }
        isConfigSaving = true
        defer { isConfigSaving = false }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateConfig(form)
            }
            configForm = nil
            ToastCenter.shared.success("密钥已保存")
            await loadZones(selectFirst: true)
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func testConfig() {
        Task { await performTestConfig() }
    }

    private func performTestConfig() async {
        guard var form = configForm else { return }
        form.apiToken = form.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        form.email = form.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if form.apiToken.isEmpty || form.email.isEmpty {
            ToastCenter.shared.error("请填写 API Key 与邮箱后再测试")
            return
        }
        isConfigSaving = true
        defer { isConfigSaving = false }
        do {
            let msg = try await LoadingHUD.shared.during {
                try await service.testConfig(form)
            }
            AppAlert.info(title: "连接测试", message: msg)
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
