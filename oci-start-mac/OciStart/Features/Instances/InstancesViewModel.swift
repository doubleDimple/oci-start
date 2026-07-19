import Foundation
import Combine
import AppKit

/// ViewModel for Web `/oci/list` — list + filter + row actions.
@MainActor
final class InstancesViewModel: ObservableObject {
    @Published private(set) var rows: [InstanceItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published var pageState = PageState(page: 0, size: 10)

    // Filters（租户 → 区域级联；查询参数 tenantId = 区域子租户 id）
    @Published var parentTenants: [TenantRegionOption] = []
    @Published var regions: [TenantRegionOption] = []
    @Published var selectedParentId: String = ""
    @Published var selectedRegionId: String = ""
    @Published var filterTenantId: String? = nil
    @Published var namesHidden = true

    @Published var activeSheet: InstanceSheet?
    /// SSH / 控制台 / 网络管理整页（非 sheet）
    @Published var sshItem: InstanceItem?
    @Published var consoleItem: InstanceItem?
    @Published var vnicItem: InstanceItem?

    // Form fields for sheets
    @Published var formText = ""
    @Published var formCpu = "1"
    @Published var formMemory = "6"
    @Published var formBootSize = "50"
    @Published var formVpu = "10"
    /// 多段 CIDR（对齐 Web 可动态增减输入行；留空则随机分配）
    @Published var formCidrLines: [String] = [""]
    @Published var formVerifyCode = ""
    @Published var formError: String?
    @Published var formBusy = false
    @Published var terminateCodeSent = false
    /// 更换 IP 成功后的 old → new 详情
    @Published var changeIpResult: (oldIp: String, newIp: String)?

    // 系统重装（Quick DD）
    @Published var ddOsId: String = "debian|12"
    @Published var ddPassword: String = ""
    @Published var ddLogLines: [String] = []
    @Published var ddRunning = false

    private let session: AppSession
    private var service: InstancesService { InstancesService(baseURL: session.serverURL) }

    var runningCount: Int { rows.filter(\.isRunning).count }
    var stoppedCount: Int { rows.filter(\.isStopped).count }
    var otherStateCount: Int { rows.count - runningCount - stoppedCount }

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task {
            await loadParentTenants()
            if let pending = NavigationState.shared.takePendingInstancesFilter() {
                await applyPendingFilter(pending)
            } else {
                await reload()
            }
        }
    }

    /// 从租户详情跳入：预选父租户 + 区域并按区域租户 id 过滤
    func applyPendingFilter(_ filter: PendingTenantListFilter) async {
        selectedParentId = filter.parentTenantId
        selectedRegionId = filter.regionTenantId
        filterTenantId = filter.regionTenantId
        pageState.page = 0
        if !selectedParentId.isEmpty {
            do {
                regions = try await service.listRegions(parentId: selectedParentId).sorted {
                    $0.region.localizedCaseInsensitiveCompare($1.region) == .orderedAscending
                }
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
            errorText = error.localizedDescription
            rows = []
            if case APIError.unauthorized = error {
                // session expired — shell handles re-login
            } else {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    func onPageChange() {
        Task { await reload() }
    }

    // MARK: - Filter

    func loadParentTenants() async {
        do {
            // 对齐 Web：按 userName 排序
            parentTenants = try await service.listParentTenants().sorted {
                $0.userName.localizedCaseInsensitiveCompare($1.userName) == .orderedAscending
            }
        } catch {
            parentTenants = []
        }
    }

    func onParentChanged(_ parentId: String?) {
        selectedParentId = parentId ?? ""
        selectedRegionId = ""
        regions = []
        if selectedParentId.isEmpty {
            return
        }
        Task {
            do {
                let list = try await service.listRegions(parentId: selectedParentId)
                // 对齐 Web：按 region 排序；仅一个区域时自动选中
                regions = list.sorted {
                    $0.region.localizedCaseInsensitiveCompare($1.region) == .orderedAscending
                }
                if regions.count == 1 {
                    selectedRegionId = regions[0].id
                }
            } catch {
                regions = []
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    func onRegionChanged(_ regionId: String?) {
        selectedRegionId = regionId ?? ""
    }

    /// 对齐 Web `goToInstances`：用区域（子租户）id 过滤
    func applyFilter() {
        guard !selectedRegionId.isEmpty else {
            ToastCenter.shared.error("请选择区域后再查询")
            return
        }
        filterTenantId = selectedRegionId
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

    var canQuery: Bool {
        !selectedRegionId.isEmpty
    }

    var hasActiveFilter: Bool {
        filterTenantId != nil && !(filterTenantId?.isEmpty ?? true)
    }

    // MARK: - Export

    func exportInstances() {
        guard AppAlert.confirm(
            title: "导出实例",
            message: "将导出全部租户下所有实例（含明文 Root 密码），请妥善保管。是否继续？",
            confirmTitle: "导出",
            style: .critical
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                let (data, name) = try await service.exportAll()
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name ?? "oci-instances.txt"
                panel.allowedFileTypes = ["txt"]
                if panel.runModal() == .OK, let url = panel.url {
                    try data.write(to: url)
                    ToastCenter.shared.success("导出完成")
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    // MARK: - Clipboard

    func copyText(_ text: String, label: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "—", t != "-", t != "0.0.0.0" else {
            ToastCenter.shared.error("无可复制内容")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
        ToastCenter.shared.success("\(label) 已复制")
    }

    // MARK: - Start / Stop

    func confirmStart(_ item: InstanceItem) {
        guard AppAlert.confirm(
            title: "启动实例",
            message: "确定启动 \(item.displayName)？"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                let msg = try await service.startInstance(localId: item.id)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func confirmStop(_ item: InstanceItem) {
        guard AppAlert.confirm(
            title: "停止实例",
            message: "确定停止 \(item.displayName)？"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                let msg = try await service.stopInstance(localId: item.id)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    // MARK: - Sheets open

    func openUpdateName(_ item: InstanceItem) {
        formText = item.displayName
        formError = nil
        activeSheet = .updateName(item)
    }

    func openUpdateRemark(_ item: InstanceItem) {
        formText = item.remark == "未设置" ? "" : item.remark
        formError = nil
        activeSheet = .updateRemark(item)
    }

    func openUpdateConfig(_ item: InstanceItem) {
        formCpu = "\(max(item.ocpus, 1))"
        formMemory = "\(max(item.memoryInGBs, 1))"
        formError = nil
        activeSheet = .updateConfig(item)
    }

    func openUpdateBoot(_ item: InstanceItem) {
        formBootSize = "\(max(item.bootVolumeSizeInGBs, 50))"
        formError = nil
        activeSheet = .updateBoot(item)
    }

    func openUpdateVpu(_ item: InstanceItem) {
        let raw = Int(item.vpusPerGB) ?? 10
        let snapped = max(0, min(120, (raw / 10) * 10))
        formVpu = "\(snapped)"
        formError = nil
        activeSheet = .updateVpu(item)
    }

    func openChangeIp(_ item: InstanceItem) {
        formCidrLines = [""]
        changeIpResult = nil
        formError = nil
        formBusy = false
        activeSheet = .changeIp(item)
    }

    func addCidrLine() {
        formCidrLines.append("")
    }

    func removeCidrLine(at index: Int) {
        guard formCidrLines.count > 1, formCidrLines.indices.contains(index) else { return }
        formCidrLines.remove(at: index)
    }

    func openTerminate(_ item: InstanceItem) {
        formVerifyCode = ""
        formError = nil
        formBusy = false
        terminateCodeSent = false
        activeSheet = .terminate(item)
    }

    func openSSH(_ item: InstanceItem) {
        FloatingMenuDismiss.all()
        activeSheet = nil
        consoleItem = nil
        vnicItem = nil
        sshItem = item
    }

    func closeSSH() {
        FloatingMenuDismiss.all()
        sshItem = nil
    }

    func openConsole(_ item: InstanceItem) {
        // 必须先关掉所有窗内菜单，否则残留 catcher/panel 会挡住控制台所有按钮
        FloatingMenuDismiss.all()
        activeSheet = nil
        sshItem = nil
        vnicItem = nil
        consoleItem = item
    }

    func closeConsole() {
        FloatingMenuDismiss.all()
        consoleItem = nil
    }

    func openVnic(_ item: InstanceItem) {
        guard !item.instanceId.isEmpty else {
            ToastCenter.shared.error("缺少 OCI 实例 OCID")
            return
        }
        FloatingMenuDismiss.all()
        activeSheet = nil
        sshItem = nil
        consoleItem = nil
        vnicItem = item
    }

    func closeVnic() {
        FloatingMenuDismiss.all()
        vnicItem = nil
    }

    /// Web handleQuickDD：选系统 + 新密码 → SSE 日志
    func openOsReset(_ item: InstanceItem) {
        ddOsId = "debian|12"
        ddPassword = ""
        formError = nil
        formBusy = false
        activeSheet = .osReset(item)
    }

    // MARK: - Sheet submits

    func submitUpdateName(_ item: InstanceItem) {
        let name = formText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            formError = "名称不能为空"
            return
        }
        Task {
            formBusy = true
            formError = nil
            do {
                let msg = try await service.updateName(localId: item.id, newName: name)
                activeSheet = nil
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    func submitUpdateRemark(_ item: InstanceItem) {
        Task {
            formBusy = true
            formError = nil
            do {
                let msg = try await service.updateRemark(localId: item.id, remark: formText)
                activeSheet = nil
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    func submitUpdateConfig(_ item: InstanceItem) {
        guard let cpu = Int(formCpu), cpu >= 1, cpu <= 24 else {
            formError = "CPU 须为 1–24"
            return
        }
        guard let mem = Int(formMemory), mem >= 1, mem <= 256 else {
            formError = "内存须为 1–256 GB"
            return
        }
        Task {
            formBusy = true
            formError = nil
            do {
                let msg = try await service.updateConfig(localId: item.id, cpu: cpu, memory: mem)
                activeSheet = nil
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    func submitUpdateBoot(_ item: InstanceItem) {
        guard let size = Int64(formBootSize), size >= 47 else {
            formError = "引导卷不能小于 47GB"
            return
        }
        if size < item.bootVolumeSizeInGBs {
            formError = "暂不支持缩小引导卷"
            return
        }
        Task {
            formBusy = true
            formError = nil
            do {
                let msg = try await service.updateBootVolume(localId: item.id, sizeGB: size)
                activeSheet = nil
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    func submitUpdateVpu(_ item: InstanceItem) {
        guard let vpu = Int(formVpu), vpu >= 0, vpu <= 120, vpu % 10 == 0 else {
            formError = "VPU 须为 0–120 且为 10 的倍数"
            return
        }
        Task {
            formBusy = true
            formError = nil
            do {
                let msg = try await service.updateVpu(
                    bootVolumeId: item.bootVolumeId,
                    tenantId: item.tenantIdStr,
                    instanceDetailId: item.id,
                    vpus: vpu
                )
                activeSheet = nil
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    func submitChangeIp(_ item: InstanceItem) {
        let ranges = formCidrLines
            .flatMap { line in
                line.split(whereSeparator: { $0 == "," || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .filter { !$0.isEmpty }
        Task {
            formBusy = true
            formError = nil
            changeIpResult = nil
            do {
                let result = try await service.changeSpecIp(localId: item.id, cidrRanges: ranges)
                if let old = result.oldIp, let neu = result.newIp, !neu.isEmpty {
                    changeIpResult = (old, neu)
                    ToastCenter.shared.success("\(result.message)：\(old.isEmpty ? "—" : old) → \(neu)")
                } else {
                    ToastCenter.shared.success(result.message)
                }
                // 对齐 Web：展示详情后短暂停留再关闭
                try? await Task.sleep(nanoseconds: changeIpResult == nil ? 0 : 1_200_000_000)
                activeSheet = nil
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    func enableIpv6(_ item: InstanceItem) {
        let title = item.hasIpv6 ? "刷新 IPv6" : "开启 IPv6"
        guard AppAlert.confirm(title: title, message: "对 \(item.displayName) 执行 \(title)？") else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                let msg = try await service.enableIpv6(localId: item.id)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func sendTerminateCode(_ item: InstanceItem) {
        Task {
            formBusy = true
            formError = nil
            do {
                let msg = try await service.sendTerminateCode(localId: item.id)
                terminateCodeSent = true
                ToastCenter.shared.success(msg)
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    func submitTerminate(_ item: InstanceItem) {
        let code = formVerifyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            formError = "请输入验证码"
            return
        }
        Task {
            formBusy = true
            formError = nil
            do {
                let msg = try await service.terminateInstance(localId: item.id, code: code)
                activeSheet = nil
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            formBusy = false
        }
    }

    func confirmDeleteRecord(_ item: InstanceItem) {
        guard AppAlert.confirm(
            title: "删除本地记录",
            message: "仅删除本地数据库中的 \(item.displayName)，不会终止云端实例。是否继续？",
            confirmTitle: "删除",
            style: .critical
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                let msg = try await service.deleteLocalRecord(localId: item.id)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    // MARK: - OS Reset (Quick DD)

    func submitOsReset(_ item: InstanceItem) {
        guard !ddOsId.isEmpty else {
            formError = "请选择目标系统"
            return
        }
        let pwd = ddPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pwd.isEmpty else {
            formError = "请输入新 root 密码"
            return
        }
        let parts = ddOsId.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let osType = parts.first.map(String.init) ?? ""
        let osVersion = parts.count > 1 ? String(parts[1]) : ""
        guard !osType.isEmpty else {
            formError = "请选择目标系统"
            return
        }
        guard AppAlert.confirm(
            title: "确认系统重装",
            message: "将重装 \(item.displayName) 为 \(osType) \(osVersion)，磁盘数据会被覆盖，且不可恢复。是否继续？",
            confirmTitle: "开始重装",
            style: .critical
        ) else { return }

        ddLogLines = ["开始系统重装…", "实例：\(item.displayName)", "系统：\(osType) \(osVersion)"]
        ddRunning = true
        formBusy = true
        formError = nil
        activeSheet = .ddLog(item)

        let localId = item.id
        Task {
            do {
                try await self.service.streamQuickDD(
                    instanceId: localId,
                    osType: osType,
                    osVersion: osVersion,
                    password: pwd
                ) { event, data in
                    let line: String
                    switch event {
                    case "log", "message":
                        line = data
                    case "success":
                        line = "✅ \(data)"
                    case "complete":
                        line = "—— \(data) ——"
                    case "error":
                        line = "❌ \(data)"
                    default:
                        line = "[\(event)] \(data)"
                    }
                    guard !line.isEmpty else { return }
                    DispatchQueue.main.async {
                        self.ddLogLines.append(line)
                    }
                }
                await MainActor.run {
                    self.ddRunning = false
                    self.formBusy = false
                    self.ddLogLines.append("流已结束")
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    self.ddRunning = false
                    self.formBusy = false
                    self.ddLogLines.append("❌ \(msg)")
                    ToastCenter.shared.error(msg)
                }
            }
        }
    }
}
