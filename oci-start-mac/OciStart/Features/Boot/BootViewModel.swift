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

    // Create config form（对齐 Web add_boot）
    @Published var createArchitecture = "ARM"
    @Published var createOcpu = "1"
    @Published var createMemory = "6"
    @Published var createDisk = "50"
    @Published var createLoopTime = "60"
    @Published var createCount = "1"
    @Published var createDayGap = ""
    @Published var createPassword = ""
    @Published var createImages: [TenantImageInfo] = []
    @Published var createOSList: [String] = []
    @Published var createSelectedOS = ""
    @Published var createVersions: [TenantImageInfo] = []
    @Published var createSelectedVersion = ""
    @Published var createImageId = ""
    @Published var createLoadingImages = false
    private var createTenantId: Int64 = 0

    // Boot log（详情页下方内嵌，web full_machine_list.js openBootLogDrawer）
    @Published private(set) var bootLogLines: [BootLogLine] = []
    @Published private(set) var bootLogConnection: BootLogConnectionState = .disconnected
    @Published private(set) var bootLogLoadingHistory = false
    @Published var bootLogAutoScroll = true
    @Published private(set) var bootLogScrollToken = 0
    @Published private(set) var bootLogTaskId: Int64 = 0
    @Published private(set) var bootLogTitle = ""
    private var bootLogNextId = 1
    private var bootLogActive = false
    private var bootLogTaskRegex: NSRegularExpression?

    /// 当前日志面板是否正订阅该子任务
    func bootLogActiveIdMatches(_ id: Int64) -> Bool {
        bootLogActive && bootLogTaskId == id
    }

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
            if let pending = NavigationState.shared.takePendingBootFilter() {
                await applyPendingFilter(pending)
            } else {
                await reload()
            }
        }
    }

    /// 从租户详情跳入：预选租户/区域并过滤抢机任务
    func applyPendingFilter(_ filter: PendingTenantListFilter) async {
        selectedParentId = filter.parentTenantId
        selectedRegionId = filter.regionTenantId
        if !selectedRegionId.isEmpty {
            filterTenantId = selectedRegionId
        } else if !selectedParentId.isEmpty {
            filterTenantId = selectedParentId
        } else {
            filterTenantId = nil
        }
        pageState.page = 0
        if !selectedParentId.isEmpty {
            do {
                regions = try await service.listRegions(parentId: selectedParentId)
            } catch {
                regions = []
            }
        }
        await reload()
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

    /// 整页进入开机详情（非弹框）
    func openDetail(_ item: BootTaskItem) {
        stopBootLogStream(keepActive: false)
        detailParent = item
        detailItems = []
        Task { await loadDetail(item) }
    }

    func closeDetail() {
        stopBootLogStream(keepActive: false)
        detailParent = nil
        detailItems = []
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
        createTenantId = item.tenantId
        createArchitecture = item.architecture.isEmpty ? "ARM" : item.architecture.uppercased()
        if createArchitecture != "ARM" && createArchitecture != "AMD" && createArchitecture != "X86" {
            createArchitecture = "ARM"
        }
        createOcpu = item.ocpu > 0 ? "\(item.ocpu)" : "1"
        createMemory = item.memory > 0 ? "\(item.memory)" : "6"
        createDisk = item.disk > 0 ? "\(item.disk)" : "50"
        createLoopTime = item.loopTime > 0 ? "\(item.loopTime)" : "60"
        createCount = "1"
        createDayGap = item.dayGap
        createPassword = randomPassword()
        createImages = []
        createOSList = []
        createSelectedOS = ""
        createVersions = []
        createSelectedVersion = ""
        createImageId = ""
        formError = nil
        formBusy = false
        activeSheet = .createConfig(item)
        Task { await loadCreateImages() }
    }

    func onCreateArchitectureChanged(_ arch: String) {
        createArchitecture = arch
        Task { await loadCreateImages() }
    }

    func loadCreateImages() async {
        guard createTenantId > 0 else { return }
        createLoadingImages = true
        defer { createLoadingImages = false }
        do {
            let imgs = try await service.querySystemImages(
                tenantId: createTenantId,
                shapeType: createArchitecture
            )
            createImages = imgs
            let oss = Array(Set(imgs.map(\.operatingSystem))).sorted()
            createOSList = oss
            if let first = oss.first {
                applyCreateOS(first)
            } else {
                createSelectedOS = ""
                createVersions = []
                createSelectedVersion = ""
                createImageId = ""
            }
        } catch {
            createImages = []
            createOSList = []
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func applyCreateOS(_ os: String) {
        createSelectedOS = os
        createVersions = createImages.filter { $0.operatingSystem == os }
        if let v = createVersions.first {
            createSelectedVersion = v.operatingSystemVersion
            createImageId = v.imageId
        } else {
            createSelectedVersion = ""
            createImageId = ""
        }
    }

    func applyCreateVersion(_ ver: String) {
        createSelectedVersion = ver
        if let hit = createVersions.first(where: { $0.operatingSystemVersion == ver }) {
            createImageId = hit.imageId
        }
    }

    func submitCreateConfig() {
        guard createTenantId > 0 else {
            formError = "租户无效"
            return
        }
        guard !createImageId.isEmpty else {
            formError = "请选择系统镜像"
            return
        }
        let pwd = createPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pwd.isEmpty else {
            formError = "请填写 Root 密码"
            return
        }
        let fields: [String: String] = [
            "tenantId": "\(createTenantId)",
            "ocpu": createOcpu,
            "memory": createMemory,
            "disk": createDisk,
            "architecture": createArchitecture,
            "loopTime": createLoopTime,
            "instanceCount": createCount,
            "rootPassword": pwd,
            "imageId": createImageId,
            "operatingSystem": createSelectedOS,
            "operatingSystemVersion": createSelectedVersion,
            "dayGap": createDayGap,
            "notifyFlag": "NO",
            "cloudType": "1"
        ]
        Task {
            formBusy = true
            formError = nil
            do {
                try await service.saveBootInstance(fields: fields)
                activeSheet = nil
                ToastCenter.shared.success("抢机配置已创建")
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    private func randomPassword(length: Int = 12) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%")
        return String((0..<length).map { _ in chars.randomElement()! })
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
                activeSheet = nil
                if let parent = detailParent {
                    await loadDetail(parent)
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

    // MARK: - Boot log（详情页下方内嵌面板 + SSE，非弹框）

    /// 对齐 Web：按子任务 id 过滤 `TaskId=…` 日志流
    func openBootLog(for detail: BootDetailItem) {
        let title: String
        if let p = detailParent {
            title = "\(p.displayTenant) · \(detail.osText)"
        } else {
            title = detail.osText
        }
        openBootLog(taskId: detail.id, title: title)
    }

    /// 列表组入口：进详情整页，并用组 bootId 拉日志
    func openBootLog(for task: BootTaskItem) {
        if detailParent?.id != task.id {
            detailParent = task
            detailItems = []
            Task { await loadDetail(task) }
        }
        openBootLog(taskId: task.id, title: "\(task.displayTenant) · \(task.archText)")
    }

    func openBootLog(taskId: Int64, title: String) {
        stopBootLogStream(keepActive: true)
        bootLogTaskId = taskId
        bootLogTitle = title
        bootLogLines = []
        bootLogNextId = 1
        bootLogConnection = .disconnected
        bootLogActive = true
        let escaped = NSRegularExpression.escapedPattern(for: "\(taskId)")
        // web: /[Tt]ask[Ii]d\s*[=:：]\s*{id}(?![0-9])/
        bootLogTaskRegex = try? NSRegularExpression(
            pattern: "[Tt]ask[Ii]d\\s*[=:：]\\s*\(escaped)(?![0-9])",
            options: []
        )
        Task { await loadBootLogHistoryAndConnect() }
    }

    func closeBootLog() {
        stopBootLogStream(keepActive: false)
    }

    /// 离开详情页时停 SSE
    func stopBootLogIfLeaving() {
        guard bootLogActive || bootLogConnection != .disconnected else { return }
        stopBootLogStream(keepActive: false)
    }

    func clearBootLog() {
        bootLogLines = []
    }

    func reconnectBootLog() {
        guard bootLogActive, bootLogTaskId > 0 else { return }
        Task { await connectBootLogStream() }
    }

    private func stopBootLogStream(keepActive: Bool) {
        bootLogActive = keepActive
        OpenLogsSSEClient.shared.stop(notify: false)
        bootLogConnection = .disconnected
        if !keepActive {
            bootLogTaskId = 0
            bootLogTitle = ""
            bootLogTaskRegex = nil
            bootLogLines = []
        }
    }

    private func loadBootLogHistoryAndConnect() async {
        bootLogLoadingHistory = true
        defer { bootLogLoadingHistory = false }
        do {
            let lines = try await service.fetchBootLogHistory(lines: 400)
            var built: [BootLogLine] = []
            for line in lines {
                guard matchesBootLogTask(line) else { continue }
                let id = bootLogNextId
                bootLogNextId += 1
                built.append(BootLogLine.make(id: id, raw: line))
            }
            if built.count > 1000 {
                built = Array(built.suffix(1000))
            }
            bootLogLines = built
            if bootLogAutoScroll { bootLogScrollToken += 1 }
        } catch {
            // 历史失败不阻断 SSE
            ToastCenter.shared.error("加载历史日志失败：\(error.localizedDescription)")
        }
        guard bootLogActive else { return }
        await connectBootLogStream()
    }

    private func connectBootLogStream() async {
        guard bootLogActive else { return }
        bootLogConnection = .connecting
        let req: URLRequest
        do {
            req = try service.bootLogStreamRequest()
        } catch {
            bootLogConnection = .disconnected
            ToastCenter.shared.error(error.localizedDescription)
            return
        }
        // Strong capture：与 OpenLogsViewModel 一致，页面生命周期内由 ViewModel 持有
        OpenLogsSSEClient.shared.start(
            request: req,
            onOpen: {
                DispatchQueue.main.async {
                    self.bootLogConnection = .connected
                }
            },
            onLine: { line in
                DispatchQueue.main.async {
                    self.appendBootLogLine(line)
                }
            },
            onClose: { _ in
                DispatchQueue.main.async {
                    if self.bootLogActive {
                        self.bootLogConnection = .disconnected
                    }
                }
            }
        )
    }

    private func matchesBootLogTask(_ text: String) -> Bool {
        guard let re = bootLogTaskRegex else { return true }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.firstMatch(in: text, options: [], range: range) != nil
    }

    private func appendBootLogLine(_ raw: String) {
        guard bootLogActive else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard matchesBootLogTask(trimmed) else { return }
        let id = bootLogNextId
        bootLogNextId += 1
        var next = bootLogLines
        next.append(BootLogLine.make(id: id, raw: trimmed))
        if next.count > 1000 {
            next.removeFirst(next.count - 1000)
        }
        bootLogLines = next
        if bootLogAutoScroll {
            bootLogScrollToken += 1
        }
    }

    func copyBootLog() {
        let text = bootLogLines.map(\.text).joined(separator: "\n")
        guard !text.isEmpty else {
            ToastCenter.shared.error("暂无日志")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastCenter.shared.success("日志已复制")
    }

    func copyPassword(_ pwd: String) {
        let p = pwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else {
            ToastCenter.shared.error("无密码")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(p, forType: .string)
        ToastCenter.shared.success("密码已复制")
    }
}
