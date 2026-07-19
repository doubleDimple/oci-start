import Foundation
import Combine

/// ViewModel for Web `/vpnProxy/page`.
@MainActor
final class ProxyConfigViewModel: ObservableObject {

    @Published private(set) var items: [VpnProxyItem] = []
    @Published var pageState = PageState(page: 0, size: 10)
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isTestingAll = false
    @Published private(set) var errorText: String?

    @Published var activeForm: ProxyFormState?
    @Published var parentTenants: [ProxyParentTenant] = []
    @Published var tenantSearch = ""
    @Published var tenantPageIndex = 0

    static let tenantPageSize = 7

    private let session: AppSession
    private var service: ProxyConfigService { ProxyConfigService(baseURL: session.serverURL) }
    private var testingIds = Set<Int64>()

    let typeOptions = [
        SelectOption(id: "HTTP", title: "HTTP"),
        SelectOption(id: "HTTPS", title: "HTTPS")
    ]

    let statusOptions = [
        SelectOption(id: "1", title: "启用"),
        SelectOption(id: "0", title: "停用")
    ]

    let forceOptions = [
        SelectOption(id: "0", title: "非强制"),
        SelectOption(id: "1", title: "强制")
    ]

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task {
            async let tenants: () = loadTenants()
            async let list: () = reload()
            _ = await (tenants, list)
        }
    }

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let pageNum = pageState.page + 1
            let result = try await service.pageList(pageNum: pageNum, pageSize: pageState.size)
            items = result.items
            pageState.apply(totalElements: result.total, totalPages: result.pages)
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadTenants() async {
        do {
            parentTenants = try await service.listParentTenants()
        } catch {
            parentTenants = []
        }
    }

    func onPageChange() {
        Task { await reload() }
    }

    func openAdd() {
        activeForm = .empty()
        tenantSearch = ""
        tenantPageIndex = 0
    }

    func openEdit(_ item: VpnProxyItem) {
        activeForm = .from(item)
        tenantSearch = ""
        jumpTenantPage(to: item.tenantId)
    }

    func closeForm() {
        activeForm = nil
    }

    func saveForm() {
        Task { await performSaveForm() }
    }

    private func performSaveForm() async {
        guard var form = activeForm else { return }
        form.proxyHost = form.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !form.proxyType.isEmpty, !form.proxyHost.isEmpty else {
            ToastCenter.shared.error("请填写代理类型与地址")
            return
        }
        guard let port = Int(form.proxyPort), (1...65535).contains(port) else {
            ToastCenter.shared.error("端口范围应为 1–65535")
            return
        }
        let payload = form
        isSaving = true
        defer { isSaving = false }
        do {
            try await LoadingHUD.shared.during {
                try await service.saveOrUpdate(payload)
            }
            activeForm = nil
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func delete(_ item: VpnProxyItem) {
        Task { await performDelete(item) }
    }

    private func performDelete(_ item: VpnProxyItem) async {
        guard AppAlert.confirm(
            title: "删除代理",
            message: "确定删除 \(item.proxyType) \(item.proxyHost):\(item.proxyPort)？",
            confirmTitle: "删除",
            style: .critical
        ) else { return }
        do {
            try await LoadingHUD.shared.during {
                try await service.delete(id: item.id)
            }
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Force proxy toggle（对齐 Web `toggleForceProxy`）

    func toggleForce(_ item: VpnProxyItem) {
        Task { await performToggleForce(item) }
    }

    private func performToggleForce(_ item: VpnProxyItem) async {
        let next = item.isForce ? 0 : 1
        if next == 1 {
            let ok = AppAlert.confirm(
                title: "开启强制代理",
                message: "开启后，该代理连通失败将拒绝向云厂商发起请求。确定开启？",
                confirmTitle: "开启"
            )
            guard ok else { return }
        }
        var form = ProxyFormState.from(item)
        form.forceProxy = next
        do {
            try await LoadingHUD.shared.during {
                try await service.saveOrUpdate(form)
            }
            // 本地立即刷新，再拉列表对齐服务端
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].forceProxy = next
            }
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Connectivity test

    func testConnection(_ item: VpnProxyItem) {
        Task { await performTestConnection(item.id) }
    }

    func testAll() {
        Task { await performTestAll() }
    }

    private func performTestConnection(_ id: Int64) async {
        guard id > 0, !testingIds.contains(id), !isTestingAll else { return }
        setTesting(id: id, testing: true)
        do {
            let result = try await service.testConnection(id: id)
            applyTestResult(result)
            ToastCenter.shared.success(result.connected ? "代理连通" : "代理不通")
        } catch {
            setTesting(id: id, testing: false)
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func performTestAll() async {
        guard !isTestingAll else { return }
        isTestingAll = true
        for item in items {
            setTesting(id: item.id, testing: true)
        }
        do {
            // 拉全量后逐条探测：实时刷新当前页，且避免单请求超时
            let all = try await service.pageList(pageNum: 1, pageSize: 1000)
            if all.items.isEmpty {
                testingIds.removeAll()
                for i in items.indices { items[i].isTesting = false }
                isTestingAll = false
                ToastCenter.shared.error("暂无代理可测试")
                return
            }
            var ok = 0
            var fail = 0
            for proxy in all.items {
                setTesting(id: proxy.id, testing: true)
                do {
                    let result = try await service.testConnection(id: proxy.id)
                    applyTestResult(result)
                    if result.connected { ok += 1 } else { fail += 1 }
                } catch {
                    setTesting(id: proxy.id, testing: false)
                    if let idx = items.firstIndex(where: { $0.id == proxy.id }) {
                        items[idx].availableStatus = 0
                    }
                    fail += 1
                }
            }
            testingIds.removeAll()
            await reload()
            ToastCenter.shared.success("全部测试完成：共 \(all.items.count) 条，通 \(ok)，不通 \(fail)")
        } catch {
            testingIds.removeAll()
            for i in items.indices {
                items[i].isTesting = false
            }
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
        isTestingAll = false
    }

    private func setTesting(id: Int64, testing: Bool) {
        if testing {
            testingIds.insert(id)
        } else {
            testingIds.remove(id)
        }
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isTesting = testing
        }
    }

    private func applyTestResult(_ result: ProxyTestResult) {
        testingIds.remove(result.id)
        if let idx = items.firstIndex(where: { $0.id == result.id }) {
            items[idx].isTesting = false
            items[idx].availableStatus = result.availableStatus
        }
    }

    // MARK: - Tenant picker

    var filteredTenants: [ProxyParentTenant] {
        let kw = tenantSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return parentTenants }
        return parentTenants.filter {
            ($0.name + " " + $0.region + " " + $0.id).lowercased().contains(kw)
        }
    }

    var tenantTotalPages: Int {
        max(1, Int(ceil(Double(filteredTenants.count) / Double(Self.tenantPageSize))))
    }

    var pagedTenants: [ProxyParentTenant] {
        let start = tenantPageIndex * Self.tenantPageSize
        guard start < filteredTenants.count else { return [] }
        let end = min(start + Self.tenantPageSize, filteredTenants.count)
        return Array(filteredTenants[start..<end])
    }

    func onTenantSearchChange() {
        tenantPageIndex = 0
    }

    func changeTenantPage(_ delta: Int) {
        let next = tenantPageIndex + delta
        guard next >= 0, next < tenantTotalPages else { return }
        tenantPageIndex = next
    }

    func selectTenant(_ id: Int64?) {
        guard var form = activeForm else { return }
        form.tenantId = id
        activeForm = form
    }

    func selectedTenantLabel() -> String {
        guard let form = activeForm, let tid = form.tenantId, tid > 0 else {
            return "全局共享"
        }
        if let t = parentTenants.first(where: { $0.id == "\(tid)" }) {
            return t.name
        }
        return "#\(tid)"
    }

    private func jumpTenantPage(to tenantId: Int64?) {
        tenantPageIndex = 0
        guard let tenantId = tenantId, tenantId > 0 else { return }
        let filtered = filteredTenants
        if let idx = filtered.firstIndex(where: { $0.id == "\(tenantId)" }) {
            tenantPageIndex = idx / Self.tenantPageSize
        }
    }
}
