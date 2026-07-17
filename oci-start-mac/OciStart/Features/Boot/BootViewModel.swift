import Foundation
import Combine
import AppKit

/// ViewModel for Web `/boot/fullBootList` — boot task list + actions.
@MainActor
final class BootViewModel: ObservableObject {

    @Published private(set) var rows: [BootTaskItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published var pageState = PageState(page: 0, size: 20)

    // Cascade filter: parent → region (tenantId for list = region id)
    @Published var parentTenants: [TenantRegionOption] = []
    @Published var regions: [TenantRegionOption] = []
    @Published var selectedParentId: String = ""
    @Published var selectedRegionId: String = ""
    @Published var filterTenantId: String? = nil
    @Published var namesHidden = true

    @Published var activeSheet: BootSheet?

    // Detail
    @Published private(set) var detailItems: [BootDetailItem] = []
    @Published private(set) var detailLoading = false
    @Published private(set) var detailParent: BootTaskItem?

    // Edit form
    @Published var editOcpu = "1"
    @Published var editMemory = "6"
    @Published var editDisk = "50"
    @Published var editLoopTime = "60"
    @Published var editDayGap = ""
    @Published var editPassword = ""
    @Published var formBusy = false
    @Published var formError: String?
    private var editingDetailId: Int64 = 0

    private let session: AppSession
    private var service: BootService { BootService(baseURL: session.serverURL) }

    var hasActiveFilter: Bool {
        filterTenantId != nil && !(filterTenantId ?? "").isEmpty
    }

    var canQuery: Bool { !selectedRegionId.isEmpty || !selectedParentId.isEmpty }

    init(session: AppSession = .shared) {
        self.session = session
    }

    // MARK: - Lifecycle

    func start() {
        Task {
            await loadParentTenants()
            await reload()
        }
    }

    // MARK: - List

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let resp = try await service.list(
                page: pageState.page,
                size: pageState.size,
                tenantId: filterTenantId
            )
            rows = resp.content
            pageState.apply(totalElements: resp.totalElements, totalPages: resp.totalPages)
            if resp.currentPage != pageState.page {
                pageState.page = resp.currentPage
            }
        } catch {
            rows = []
            errorText = error.localizedDescription
            if case APIError.unauthorized = error { return }
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func onPageChange() {
        Task { await reload() }
    }

    // MARK: - Filter

    func loadParentTenants() async {
        do {
            parentTenants = try await service.listParentTenants()
        } catch {
            parentTenants = []
        }
    }

    func onParentChanged(_ parentId: String?) {
        selectedParentId = parentId ?? ""
        selectedRegionId = ""
        regions = []
        guard !selectedParentId.isEmpty else { return }
        Task {
            do {
                regions = try await service.listRegions(parentId: selectedParentId)
            } catch {
                regions = []
            }
        }
    }

    func onRegionChanged(_ regionId: String?) {
        selectedRegionId = regionId ?? ""
    }

    func applyFilter() {
        if !selectedRegionId.isEmpty {
            filterTenantId = selectedRegionId
        } else if !selectedParentId.isEmpty {
            filterTenantId = selectedParentId
        } else {
            filterTenantId = nil
        }
        pageState.page = 0
        Task { await reload() }
    }

    func resetFilter() {
        selectedParentId = ""
        selectedRegionId = ""
        regions = []
        filterTenantId = nil
        pageState.page = 0
        Task { await reload() }
    }

    // MARK: - Batch

    func batchStart() {
        Task {
            LoadingHUD.shared.begin()
            do {
                let n = try await service.offlineCount()
                guard AppAlert.confirm(
                    title: "批量启动",
                    message: "将启动全部未开机任务（当前约 \(n) 条），确定继续？"
                ) else {
                    LoadingHUD.shared.end()
                    return
                }
                try await service.batchStart()
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func batchStop() {
        Task {
            LoadingHUD.shared.begin()
            do {
                let n = try await service.startingCount()
                guard AppAlert.confirm(
                    title: "批量停止",
                    message: "将停止全部开机中任务（当前约 \(n) 条），确定继续？"
                ) else {
                    LoadingHUD.shared.end()
                    return
                }
                try await service.batchStop()
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func batchResetFail() {
        guard AppAlert.confirm(
            title: "重置失败次数",
            message: "将清空全部任务的失败计数，确定继续？"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.batchInitFailCount()
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    // MARK: - Row actions

    func confirmStart(_ item: BootTaskItem) {
        guard AppAlert.confirm(title: "启动任务", message: "启动 \(item.displayTenant) · \(item.archText) 下未开机任务？") else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.startBoot(bootId: item.id)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func confirmStop(_ item: BootTaskItem) {
        guard AppAlert.confirm(title: "停止任务", message: "停止 \(item.displayTenant) · \(item.archText) 下开机中任务？") else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.stopBoot(bootId: item.id)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func confirmClone(_ item: BootTaskItem) {
        guard AppAlert.confirm(title: "克隆开机", message: "克隆一条新的抢机配置？") else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.cloneBoot(bootId: item.id)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func confirmDelete(_ item: BootTaskItem) {
        guard AppAlert.confirm(
            title: "删除开机任务",
            message: "将删除该租户+架构下全部抢机配置，确定？"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.deleteBoot(bootId: item.id)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func confirmManual(_ item: BootTaskItem) {
        guard AppAlert.confirm(title: "手动抢机", message: "立即执行一次抢机尝试？") else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.manualBoot(bootId: item.id)
                AppAlert.info(title: "已提交", message: "手动抢机请求已提交")
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func openDetail(_ item: BootTaskItem) {
        detailParent = item
        detailItems = []
        activeSheet = .detail(item)
        Task { await loadDetail(item) }
    }

    func loadDetail(_ item: BootTaskItem) async {
        detailLoading = true
        defer { detailLoading = false }
        do {
            detailItems = try await service.bootDetail(bootId: item.id)
        } catch {
            detailItems = []
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func openAddConfig(_ item: BootTaskItem) {
        activeSheet = .embed(
            title: "添加抢机配置",
            path: "/tenants/bootPage",
            query: ["tenantId": "\(item.tenantId)"]
        )
    }

    // MARK: - Detail actions

    func toggleDetailStatus(_ d: BootDetailItem, start: Bool) {
        let status = start ? 1 : 0
        let title = start ? "启动" : "停止"
        guard AppAlert.confirm(title: title, message: "确定\(title)该子任务？") else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.toggleStatus(id: d.id, status: status)
                if let parent = detailParent {
                    await loadDetail(parent)
                    await reload()
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func deleteDetail(_ d: BootDetailItem) {
        guard AppAlert.confirm(title: "删除子任务", message: "确定删除该条抢机配置？") else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.deleteBootDetail(bootId: d.id)
                if let parent = detailParent {
                    await loadDetail(parent)
                    await reload()
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func openEditDetail(_ d: BootDetailItem) {
        editingDetailId = d.id
        editOcpu = "\(max(d.ocpu, 1))"
        editMemory = "\(max(d.memory, 1))"
        editDisk = "\(max(d.disk, 1))"
        editLoopTime = "\(max(d.loopTime, 1))"
        editDayGap = d.dayGap
        editPassword = d.rootPassword
        formError = nil
        formBusy = false
        activeSheet = .editDetail(d)
    }

    func submitEditDetail() {
        guard let ocpu = Int(editOcpu), ocpu > 0,
              let memory = Int(editMemory), memory > 0,
              let disk = Int(editDisk), disk > 0,
              let loop = Int(editLoopTime), loop > 0 else {
            formError = "请填写有效的数值配置"
            return
        }
        let pwd = editPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pwd.isEmpty else {
            formError = "Root 密码不能为空"
            return
        }
        formBusy = true
        formError = nil
        let id = editingDetailId
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.updateBoot(
                    id: id,
                    ocpu: ocpu,
                    memory: memory,
                    disk: disk,
                    loopTime: loop,
                    rootPassword: pwd,
                    dayGap: editDayGap.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if let parent = detailParent {
                    activeSheet = .detail(parent)
                    await loadDetail(parent)
                } else {
                    activeSheet = nil
                }
            } catch {
                formError = error.localizedDescription
                ToastCenter.shared.error(error.localizedDescription)
            }
            formBusy = false
            LoadingHUD.shared.end()
        }
    }

    func tenantLabel(_ t: TenantRegionOption) -> String {
        if !t.userName.isEmpty { return t.userName }
        if !t.tenancyName.isEmpty { return t.tenancyName }
        return t.id
    }

    func regionLabel(_ r: TenantRegionOption) -> String {
        var s = r.region.isEmpty ? (r.tenancyName.isEmpty ? r.id : r.tenancyName) : r.region
        if r.isHomeRegion { s += " · 主" }
        return s
    }
}
