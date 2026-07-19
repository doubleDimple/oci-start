import Foundation
import Combine

/// ViewModel for Web `/dns/edgeone`.
@MainActor
final class EdgeOneViewModel: ObservableObject {
    @Published private(set) var zones: [EoZone] = []
    @Published var selectedZoneId: String?
    @Published var mode: EdgeOneMode = .dns

    @Published private(set) var dnsRecords: [EoDnsRecord] = []
    @Published private(set) var accelDomains: [EoAccelDomain] = []
    @Published var pageState = PageState(page: 0, size: 20)
    @Published var searchName = ""
    @Published var searchContent = ""

    @Published var dnsForm: EoDnsForm?
    @Published var configForm: EoConfigForm?
    @Published private(set) var isLoading = false
    @Published private(set) var isZonesLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isConfigSaving = false
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: EdgeOneService { EdgeOneService(baseURL: session.serverURL) }

    var zoneOptions: [SelectOption] {
        zones.map { SelectOption(id: $0.id, title: $0.title) }
    }

    var selectedZoneName: String {
        zones.first(where: { $0.id == selectedZoneId })?.name ?? ""
    }

    var filteredDns: [EoDnsRecord] {
        let n = searchName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = searchContent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = dnsRecords
        if !n.isEmpty {
            list = list.filter { $0.name.lowercased().contains(n) }
        }
        if !c.isEmpty {
            list = list.filter { $0.content.lowercased().contains(c) }
        }
        return list
    }

    var filteredDomains: [EoAccelDomain] {
        let n = searchName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = searchContent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = accelDomains
        if !n.isEmpty {
            list = list.filter {
                $0.domainName.lowercased().contains(n) || $0.status.lowercased().contains(n)
            }
        }
        if !c.isEmpty {
            list = list.filter { $0.cname.lowercased().contains(c) }
        }
        return list
    }

    var pagedDns: [EoDnsRecord] {
        pageSlice(filteredDns)
    }

    var pagedDomains: [EoAccelDomain] {
        pageSlice(filteredDomains)
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
            if selectedZoneId != nil {
                await reloadRecords()
            } else {
                clearLists()
            }
        } catch {
            zones = []
            clearLists()
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

    func switchMode(_ newMode: EdgeOneMode) {
        guard mode != newMode else { return }
        mode = newMode
        pageState.page = 0
        searchName = ""
        searchContent = ""
        Task { await reloadRecords() }
    }

    func reloadRecords() async {
        guard let zoneId = selectedZoneId, !zoneId.isEmpty else {
            clearLists()
            return
        }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            switch mode {
            case .dns:
                dnsRecords = try await service.fetchDnsRecords(zoneId: zoneId)
                applyPageTotal(filteredDns.count)
            case .domain:
                accelDomains = try await service.fetchAccelDomains(zoneId: zoneId)
                applyPageTotal(filteredDomains.count)
            }
        } catch {
            clearLists()
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func onPageChange() {
        // client-side paging only
    }

    func onSearchChanged() {
        pageState.page = 0
        switch mode {
        case .dns: applyPageTotal(filteredDns.count)
        case .domain: applyPageTotal(filteredDomains.count)
        }
    }

    func clearSearch() {
        searchName = ""
        searchContent = ""
        onSearchChanged()
    }

    // MARK: - DNS form

    func openAdd() {
        guard selectedZoneId != nil else {
            ToastCenter.shared.error("请先选择域名")
            return
        }
        guard mode == .dns else {
            ToastCenter.shared.error("加速域名请在腾讯云控制台添加")
            return
        }
        dnsForm = .empty()
    }

    func openEdit(_ record: EoDnsRecord) {
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
        let prio: Int? = {
            let s = form.priority.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            return Int(s)
        }()
        isSaving = true
        defer { isSaving = false }
        do {
            try await LoadingHUD.shared.during {
                if form.isEditing {
                    try await service.updateDnsRecord(
                        recordId: form.recordId,
                        zoneId: zoneId,
                        type: form.type,
                        name: form.name,
                        content: form.content,
                        ttl: form.ttl,
                        priority: prio
                    )
                } else {
                    try await service.createDnsRecord(
                        zoneId: zoneId,
                        type: form.type,
                        name: form.name,
                        content: form.content,
                        ttl: form.ttl,
                        priority: prio
                    )
                }
            }
            dnsForm = nil
            ToastCenter.shared.success(form.isEditing ? "记录已更新" : "记录已添加")
            await reloadRecords()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func deleteDns(_ record: EoDnsRecord) {
        Task { await performDeleteDns(record) }
    }

    private func performDeleteDns(_ record: EoDnsRecord) async {
        let ok = AppAlert.confirm(
            title: "删除 DNS 记录",
            message: "确认删除 \(record.name)？",
            confirmTitle: "删除"
        )
        guard ok else { return }
        do {
            try await LoadingHUD.shared.during {
                try await service.deleteDnsRecord(recordId: record.id)
            }
            ToastCenter.shared.success("已删除")
            await reloadRecords()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func deleteDomain(_ domain: EoAccelDomain) {
        Task { await performDeleteDomain(domain) }
    }

    private func performDeleteDomain(_ domain: EoAccelDomain) async {
        let ok = AppAlert.confirm(
            title: "删除加速域名",
            message: "确认删除 \(domain.domainName)？",
            confirmTitle: "删除"
        )
        guard ok else { return }
        do {
            try await LoadingHUD.shared.during {
                try await service.deleteAccelDomain(domainId: domain.id)
            }
            ToastCenter.shared.success("已删除")
            await reloadRecords()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func sync() {
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
        let title = mode == .dns ? "同步 DNS 记录" : "同步加速域名"
        let ok = AppAlert.confirm(
            title: title,
            message: "将从腾讯云拉取 \(name) 的数据到本地。",
            confirmTitle: "同步"
        )
        guard ok else { return }
        isSyncing = true
        defer { isSyncing = false }
        let syncMode = mode
        do {
            let msg: String = try await LoadingHUD.shared.during {
                switch syncMode {
                case .dns:
                    return try await service.syncDns(zoneId: zoneId, domainName: name)
                case .domain:
                    return try await service.syncDomains(zoneId: zoneId, domainName: name)
                }
            }
            AppAlert.info(title: "同步完成", message: msg)
            await reloadRecords()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Config

    func openConfig() {
        Task { await loadConfigForm() }
    }

    private func loadConfigForm() async {
        do {
            configForm = try await LoadingHUD.shared.during {
                try await service.fetchConfig()
            }
        } catch {
            configForm = EoConfigForm()
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
        form.secretId = form.secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        form.secretKey = form.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if form.enabled, form.secretId.isEmpty || form.secretKey.isEmpty {
            ToastCenter.shared.error("启用时请填写 SecretId 与 SecretKey")
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
        form.secretId = form.secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        form.secretKey = form.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if form.secretId.isEmpty || form.secretKey.isEmpty {
            ToastCenter.shared.error("请填写 SecretId 与 SecretKey 后再测试")
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

    // MARK: - helpers

    private func clearLists() {
        dnsRecords = []
        accelDomains = []
        pageState.apply(totalElements: 0, totalPages: 0)
    }

    private func applyPageTotal(_ count: Int) {
        pageState.apply(totalElements: Int64(count))
    }

    private func pageSlice<T>(_ list: [T]) -> [T] {
        guard !list.isEmpty else { return [] }
        let start = min(pageState.page * pageState.size, list.count)
        let end = min(start + pageState.size, list.count)
        if start >= end { return [] }
        return Array(list[start..<end])
    }
}
