import Foundation
import Combine
import AppKit

/// ViewModel for Web `/tenants/list` — same role as RegionsViewModel / DashboardViewModel.
@MainActor
final class TenantsViewModel: ObservableObject {
    @Published private(set) var rows: [TenantItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published var pageState = PageState(page: 0, size: 10)
    @Published var searchText = ""
    @Published var namesHidden = true
    @Published var activeSheet: TenantSheet?

    // Add form
    @Published var addConfigText = ""
    @Published var addUserName = ""
    @Published var addTenantId = ""
    @Published var addFingerprint = ""
    @Published var addTenancy = ""
    @Published var addRegion = "ap-singapore-1"
    @Published var addKeyFileURL: URL?
    @Published var formError: String?

    // Generic edit
    @Published var editText = ""

    // Users (full page)
    @Published var userManageParent: TenantItem?
    @Published var userManageLoading = false
    @Published var userTab: TenantUserTab = .users
    @Published var users: [TenantOracleUser] = []
    @Published var groups: [TenantOciGroup] = []
    @Published var newUsername = ""
    @Published var newEmail = ""
    @Published var newGroupId = ""
    @Published var showAddUser = false
    @Published var useEmailAsUsername = false
    // Password policy
    @Published var showPasswordPolicy = false
    @Published var policyEnableExpiry = false
    @Published var policyExpiryDays = "120"
    @Published var policyInfoLines: [String] = []
    // Notifications
    @Published var notifyEmails: [String] = []
    @Published var notifyEmailsLoading = false
    @Published var showAddNotify = false
    @Published var newNotifyEmail = ""
    // MFA
    @Published var mfaLoading = false
    @Published var mfaStatusText = "加载中…"
    @Published var mfaEmailEnabled = false
    @Published var mfaDetailLines: [String] = []

    // Traffic
    @Published var trafficThreshold = ""
    @Published var trafficAutoShutdown = false
    @Published var trafficStats = true

    // Audit (full page, not sheet)
    @Published var auditParent: TenantItem?
    @Published var auditLogs: [TenantAuditLogEntry] = []
    @Published var auditStart = ""
    @Published var auditEnd = ""
    @Published var auditLoading = false
    @Published var auditLoadingMore = false
    @Published var auditNextPageToken: String?
    @Published var auditError: String?

    // Email
    @Published var emailDomain = ""
    @Published var emailInfo: String = ""
    @Published var emailEnabled = false
    @Published var emailTestAddress = ""
    @Published var emailViewOnly = false

    // Social
    @Published var socialItems: [TenantSocialItem] = []
    @Published var socialTypes: [String] = []
    @Published var socialDraft = TenantSocialItem()

    // Quota page（从弹框改为整页）
    @Published var quotaParent: TenantItem?
    @Published var quotaRegions: [TenantRegionOption] = []
    @Published var quotaTenantId = ""
    @Published var quotaService = "compute"
    @Published var quotaPage = 0
    @Published var quotaPageSize = 20
    @Published var quotaItems: [TenantQuotaItem] = []
    @Published var quotaHasNext = false
    @Published var quotaRegionLabel = ""
    @Published var quotaError = ""
    @Published var quotaLoading = false

    // Boot volumes
    @Published var volumes: [TenantBootVolume] = []
    @Published var volumesLoading = false
    @Published var volumesBusy = false
    @Published var editingVolumeId: String?
    @Published var editVolumeName = ""
    @Published var editVolumeVpus: Double = 10

    // Account check
    @Published var checkLines: [String] = []
    @Published var checkResult: TenantAccountCheckResult?
    @Published var checkPercent: Int = 0

    // Export（Web `handleSecureExport`：发码 → 输入 6 位 → 下载 JSON）
    @Published var exportCode = ""
    @Published var exportSent = false
    @Published var exportSending = false

    // Update SSE
    @Published var updateLines: [String] = []

    // OCI 同步进度（Web syncModal）
    @Published var syncPercent: Double = 0
    @Published var syncStatusText: String = ""
    @Published var syncPhase: TenantSyncPhase = .running
    @Published var syncTenantName: String = ""
    private var syncTickerTask: Task<Void, Never>?

    // Region sub (full page)
    @Published var regionSubParent: TenantItem?
    @Published var regionChildren: [TenantRegionOption] = []
    @Published var regionSummaryText = ""
    @Published var regionSubTab = 0       // 0=已订阅, 1=未订阅
    @Published var regionSubLoading = false
    @Published var subscribedRegions: [TenantSubscribedRegion] = []
    @Published var unsubscribedRegions: [TenantUnsubscribedRegion] = []
    @Published var selectedUnsubKeys: Set<String> = []
    @Published var regionTotalCount = 0
    @Published var regionSubscribedCount = 0
    @Published var regionUnsubscribedCount = 0

    // 租户详情整页（Web `/tenants/regionList` → tenant_region_list.ftl）
    @Published var detailParent: TenantItem?
    @Published var detailRows: [TenantItem] = []
    @Published var detailLoading = false
    @Published var detailError: String?
    @Published var detailNamesHidden = true

    // Security rules sheet
    @Published var rulesTab = "ingress"
    @Published var securityRules: [TenantSecurityRule] = []
    @Published var rulesLoading = false
    @Published var rulesBusy = false
    @Published var ruleProtocol = "tcp"
    @Published var ruleSource = "0.0.0.0/0"
    @Published var rulePorts = ""
    @Published var showAddRule = false

    // MySQL sheet
    @Published var mysqlRows: [TenantMysqlInstance] = []
    @Published var mysqlLoading = false
    @Published var mysqlBusy = false
    @Published var mysqlRevealedPasswordIds: Set<String> = []

    // Boot create (full page)
    @Published var bootPageParent: TenantItem?
    @Published var bootArchitecture = "ARM"
    @Published var bootOcpu = "1"
    @Published var bootMemory = "6"
    @Published var bootDisk = "50"
    @Published var bootLoopTime = "60"
    @Published var bootCount = "1"
    @Published var bootDayGap = ""
    @Published var bootImages: [TenantImageInfo] = []
    @Published var bootOSList: [String] = []
    @Published var bootSelectedOS = ""
    @Published var bootVersions: [TenantImageInfo] = []
    @Published var bootSelectedVersion = ""
    @Published var bootImageId = ""
    @Published var bootRootPassword = ""
    @Published var bootRegionOptions: [TenantRegionOption] = []
    @Published var bootSelectedRegionTenantId = ""

    // Cost page (Web `/cost/costPage` → oci_cost.ftl)
    @Published var costParent: TenantItem?
    @Published var costStart = ""
    @Published var costEnd = ""
    @Published var costTimePreset = "month" // today | month | custom
    @Published var costItems: [TenantCostItem] = []
    @Published var costLoading = false
    @Published var costError: String?
    @Published var costFilterPositiveOnly = false
    @Published var costChartType = "all" // all | compute | storage | network | other
    /// 费用明细客户端分页（与租户列表共用 `PaginationBar` / `PageState`）
    @Published var costPageState = PageState(page: 0, size: 20)

    // Traffic query page (Web `/monitor/homePage` → oci_monitor.ftl)
    @Published var trafficParent: TenantItem?
    @Published var tqStart = ""
    @Published var tqEnd = ""
    @Published var tqPeriod = "1d"
    @Published var tqRows: [TenantTrafficRow] = []
    /// Child region tenants for multi-select (Web region dropdown).
    @Published var tqRegions: [TenantRegionOption] = []
    @Published var tqSelectedRegionIds: Set<String> = []
    /// `today` | `month` | `custom` — matches Web time presets.
    @Published var tqTimePreset = "month"
    /// Alert threshold in GB (Web default 10240 = 10 TB).
    @Published var tqThresholdGB: Double = 10240

    // AI chat
    @Published var aiModels: [TenantAiModel] = []
    @Published var aiSelectedModelId = ""
    @Published var aiConnected = false
    @Published var aiLines: [TenantChatLine] = []
    @Published var aiInput = ""
    @Published var aiUseHistory = true
    @Published var aiStatus = "未连接"
    private var aiWS: URLSessionWebSocketTask?
    private var aiSession: URLSession?
    private var aiTenantId: Int64 = 0

    private let session: AppSession
    private var searchTask: Task<Void, Never>?
    private var service: TenantsService { TenantsService(baseURL: session.serverURL) }

    init(session: AppSession = .shared) {
        self.session = session
    }

    // MARK: - Lifecycle

    func start() { Task { await reload() } }

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let cloud = max(1, session.cloudProvider)
            let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let resp = try await service.list(
                page: pageState.page,
                size: pageState.size,
                keyword: kw.isEmpty ? nil : kw,
                cloudType: cloud,
                emailEnable: nil
            )
            rows = resp.content
            pageState.page = resp.currentPage
            if resp.size > 0 { pageState.size = resp.size }
            pageState.apply(totalElements: resp.totalElements, totalPages: resp.totalPages)
        } catch {
            errorText = error.localizedDescription
            rows = []
        }
    }

    func onSearchSubmit() {
        pageState.page = 0
        Task { await reload() }
    }

    func onSearchChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            pageState.page = 0
            await reload()
        }
    }

    // MARK: - Row actions

    func confirmDelete(_ item: TenantItem) {
        guard AppAlert.confirm(
            title: "删除租户",
            message: "确定删除「\(item.displayName)」及其关联数据？此操作不可恢复。",
            confirmTitle: "删除",
            cancelTitle: "取消"
        ) else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.delete(tenantId: item.id)
                    await reload()
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func sync(_ item: TenantItem) {
        startOciSync(item, afterSuccess: { [weak self] in
            await self?.reload()
        })
    }

    func updateTenantSSE(_ item: TenantItem) {
        updateLines = ["开始更新…"]
        activeSheet = .updateProgress(tenantId: item.id, lines: updateLines)
        let tenantId = item.id
        Task {
            do {
                try await service.streamSSE(path: "/tenants/updateTenant", query: ["tenantId": "\(tenantId)"]) { event, data in
                    DispatchQueue.main.async {
                        self.updateLines.append("[\(event)] \(data)")
                        self.activeSheet = .updateProgress(tenantId: tenantId, lines: self.updateLines)
                        if event == "error" {
                            ToastCenter.shared.error(data)
                        }
                    }
                    if event == "success" {
                        Task { @MainActor in
                            await self.reload()
                        }
                    }
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    // MARK: - Edit name / cost

    func openEditName(_ item: TenantItem) {
        editText = item.defName
        activeSheet = .editName(item)
    }

    func saveEditName(_ item: TenantItem) {
        let name = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.updateCustomName(tenantId: item.id, defName: name)
                    activeSheet = nil
                    await reload()
                } catch {
                    formError = error.localizedDescription
                }
            }
        }
    }

    func openEditCost(_ item: TenantItem) {
        editText = item.accountCost
        activeSheet = .editCost(item)
    }

    func saveEditCost(_ item: TenantItem) {
        let cost = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.updateAccountCost(tenantId: item.id, cost: cost)
                    activeSheet = nil
                    await reload()
                } catch {
                    formError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Add tenant

    func openAdd() {
        resetAdd()
        activeSheet = .add
    }

    func resetAdd() {
        addConfigText = ""
        addUserName = ""
        addTenantId = ""
        addFingerprint = ""
        addTenancy = ""
        addRegion = "ap-singapore-1"
        addKeyFileURL = nil
        formError = nil
    }

    func parseAddConfig() {
        let text = addConfigText
        // 1) key=value / key: value lines (Web parseOracleConfig)
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            let sep: Character? = s.contains("=") ? "=" : (s.contains(":") ? ":" : nil)
            guard let sep = sep, let idx = s.firstIndex(of: sep) else { continue }
            let k = String(s[..<idx]).trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
            var v = String(s[s.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            map[k] = v
        }
        if let v = map["user"] ?? map["username"] ?? map["userocid"] ?? map["apiuser"] { addTenantId = v }
        if let v = map["fingerprint"] ?? map["apifingerprint"] { addFingerprint = v }
        if let v = map["tenancy"] ?? map["tenancyocid"] ?? map["rootcompartment"] { addTenancy = v }
        if let v = map["region"] ?? map["homeregion"] { addRegion = v }
        if let v = map["name"] ?? map["label"] ?? map["username"] { if addUserName.isEmpty { addUserName = v } }
        // 2) OCI config file style [DEFAULT]
        if text.contains("ocid1.user") || text.contains("ocid1.tenancy") {
            let pattern = "ocid1\\.[a-z]+\\.oc1\\.[^\\s\"',}]+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                for m in matches {
                    let ocid = ns.substring(with: m.range)
                    if ocid.contains(".user.") { addTenantId = ocid }
                    if ocid.contains(".tenancy.") { addTenancy = ocid }
                }
            }
        }
        // 3) fingerprint pattern
        if addFingerprint.isEmpty {
            let fp = "([0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2}"
            if let regex = try? NSRegularExpression(pattern: fp),
               let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                addFingerprint = (text as NSString).substring(with: m.range)
            }
        }
        if addUserName.isEmpty, !addTenantId.isEmpty {
            addUserName = "api-\(String(addTenantId.suffix(6)))"
        }
    }

    func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 OCI API 私钥（.pem）"
        panel.allowedFileTypes = ["pem", "key", "txt", "json"]
        if panel.runModal() == .OK { addKeyFileURL = panel.url }
    }

    func submitAdd() {
        formError = nil
        parseAddConfig()
        let userName = addUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        let tenantId = addTenantId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprint = addFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        let tenancy = addTenancy.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = addRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userName.isEmpty, !tenantId.isEmpty, !fingerprint.isEmpty, !tenancy.isEmpty, !region.isEmpty else {
            formError = "请填写完整 API 配置（可用上方配置文本自动解析）"
            return
        }
        guard let keyURL = addKeyFileURL else {
            formError = "请选择私钥文件"
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.saveTenant(fields: [
                        "userName": userName,
                        "tenantId": tenantId,
                        "fingerprint": fingerprint,
                        "tenancy": tenancy,
                        "region": region,
                        "cloudType": "\(max(1, session.cloudProvider))",
                        "status": "0"
                    ], keyFileURL: keyURL)
                    activeSheet = nil
                    pageState.page = 0
                    await reload()
                } catch {
                    formError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Users sheet (users / notifications / mfa + password policy)

    func openUsers(_ item: TenantItem) {
        userManageParent = item
        userTab = .users
        users = []
        groups = []
        showAddUser = false
        showPasswordPolicy = false
        notifyEmails = []
        mfaStatusText = "加载中…"
        mfaDetailLines = []
        Task { await loadUsersAndGroups(item) }
    }

    func closeUserManage() {
        userManageParent = nil
        users = []
        groups = []
        showAddUser = false
        showPasswordPolicy = false
    }

    func loadUsersAndGroups(_ item: TenantItem) async {
        userManageLoading = true
        defer { userManageLoading = false }
        do {
            async let u = service.listUsers(tenantId: item.id)
            async let g = service.groups(tenantId: item.id)
            users = try await u
            groups = try await g
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func switchUserTab(_ tab: TenantUserTab, tenant: TenantItem) {
        userTab = tab
        switch tab {
        case .users: break
        case .notifications: Task { await loadNotifyEmails(tenant) }
        case .mfa: Task { await loadMfa(tenant) }
        }
    }

    func createUser(for item: TenantItem) {
        let email = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String = {
            if useEmailAsUsername { return email }
            return newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        let groupId = newGroupId
        let tenantId = item.id
        guard !name.isEmpty, !email.isEmpty else {
            ToastCenter.shared.error("请填写用户名和邮箱")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    let r = try await service.createUser(tenantId: tenantId, username: name, email: email, groupId: groupId)
                    showAddUser = false
                    newUsername = ""; newEmail = ""; newGroupId = ""
                    users = try await service.listUsers(tenantId: tenantId)
                    let pwd = r["password"] ?? ""
                    activeSheet = .passwordResult(title: "创建用户成功", username: r["username"] ?? name, password: pwd)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func resetUserPassword(for item: TenantItem, user: TenantOracleUser) {
        guard AppAlert.confirm(title: "重置密码", message: "确定重置用户 \(user.username) 的密码？") else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    let env = try await service.resetPassword(tenantId: item.id, userId: user.id)
                    let data = env.data?.dict
                    let login = data?["loginUser"]?.stringValue ?? user.username
                    let pwd = data?["temporaryPassword"]?.stringValue ?? ""
                    activeSheet = .passwordResult(title: "密码已重置", username: login, password: pwd)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func deleteUser(for item: TenantItem, user: TenantOracleUser) {
        guard AppAlert.confirm(title: "删除用户", message: "确定删除 \(user.username)？") else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.deleteUser(tenantId: item.id, userId: user.id)
                    users = try await service.listUsers(tenantId: item.id)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openPasswordPolicy(for item: TenantItem) {
        showPasswordPolicy = true
        policyEnableExpiry = false
        policyExpiryDays = "120"
        policyInfoLines = ["加载中…"]
        Task {
            do {
                let list = try await service.getPasswordPolicy(tenantId: item.id)
                if list.isEmpty {
                    policyInfoLines = ["当前无密码策略信息"]
                } else {
                    policyInfoLines = list.map { p in
                        "\(p.name): \(p.isEnabled ? "已启用" : "未启用") \(p.description)"
                    }
                }
            } catch {
                policyInfoLines = ["加载失败: \(error.localizedDescription)"]
            }
        }
    }

    func savePasswordPolicy(for item: TenantItem) {
        let days = Int(policyExpiryDays) ?? 120
        if policyEnableExpiry && (days < 0 || days > 365) {
            ToastCenter.shared.error("过期天数需在 0–365 之间（0 表示永不过期）")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.updatePasswordPolicy(tenantId: item.id, enable: policyEnableExpiry, days: days)
                    showPasswordPolicy = false
                    AppAlert.info(title: "成功", message: "密码策略已更新")
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func loadNotifyEmails(_ item: TenantItem) async {
        notifyEmailsLoading = true
        defer { notifyEmailsLoading = false }
        do {
            notifyEmails = try await service.notificationRecipients(tenantId: item.id)
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func addNotifyEmail(_ item: TenantItem) {
        let email = newNotifyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else {
            ToastCenter.shared.error("请输入有效邮箱")
            return
        }
        var list = notifyEmails
        if !list.contains(email) { list.append(email) }
        let next = list
        let tenantId = item.id
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.updateNotificationRecipients(tenantId: tenantId, emails: next)
                    notifyEmails = next
                    newNotifyEmail = ""
                    showAddNotify = false
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func removeNotifyEmail(_ item: TenantItem, email: String) {
        guard AppAlert.confirm(title: "移除邮箱", message: "确定移除 \(email)？") else { return }
        let next = notifyEmails.filter { $0 != email }
        guard !next.isEmpty else {
            ToastCenter.shared.error("至少保留一个通知邮箱")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.updateNotificationRecipients(tenantId: item.id, emails: next)
                    notifyEmails = next
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func loadMfa(_ item: TenantItem) async {
        mfaLoading = true
        mfaStatusText = "加载中…"
        mfaDetailLines = []
        defer { mfaLoading = false }
        do {
            let raw = try await service.mfaStatus(tenantId: item.id)
            if let ok = raw["success"] as? Bool, ok {
                let data = (raw["data"] as? [String: Any]) ?? raw
                mfaEmailEnabled = (data["emailEnabled"] as? Bool)
                    ?? (data["enableEmail"] as? Bool)
                    ?? false
                mfaStatusText = mfaEmailEnabled ? "邮箱 MFA：已启用" : "邮箱 MFA：未启用"
                var lines: [String] = []
                for (k, v) in data where k != "success" {
                    lines.append("\(k): \(v)")
                }
                mfaDetailLines = lines.sorted()
            } else {
                mfaStatusText = (raw["message"] as? String) ?? "获取 MFA 状态失败"
            }
        } catch {
            mfaStatusText = error.localizedDescription
        }
    }

    func setEmailMfa(_ item: TenantItem, enable: Bool) {
        let title = enable ? "启用邮箱 MFA" : "关闭邮箱 MFA"
        guard AppAlert.confirm(title: title, message: "将应用于当前租户下用户，是否继续？") else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.toggleEmailMFA(tenantId: item.id, enable: enable)
                    await loadMfa(item)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func resetMfa(_ item: TenantItem) {
        guard AppAlert.confirm(title: "重置 MFA", message: "确定重置该租户账号因子？") else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.resetAccountFactor(tenantId: item.id)
                    await loadMfa(item)
                    AppAlert.info(title: "成功", message: "MFA 已重置")
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Traffic / Audit / Email / Social / Quota / Volumes

    func openTraffic(_ item: TenantItem) {
        activeSheet = .traffic(item)
        Task {
            do {
                let cfg = try await service.trafficAlert(tenantId: item.id)
                trafficThreshold = cfg.thresholdText
                trafficAutoShutdown = cfg.autoShutdown ?? false
                trafficStats = cfg.statisticsEnabled ?? true
            } catch {
                trafficThreshold = ""
            }
        }
    }

    func saveTraffic(_ item: TenantItem) {
        guard let t = Double(trafficThreshold), t > 0 else {
            ToastCenter.shared.error("请设置有效的预警阈值")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.saveTrafficAlert(
                        tenantId: item.id,
                        threshold: t,
                        autoShutdown: trafficAutoShutdown,
                        stats: trafficStats
                    )
                    activeSheet = nil
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openAudit(_ item: TenantItem) {
        let today = Self.todayDateString()
        auditParent = item
        auditLogs = []
        auditNextPageToken = nil
        auditError = nil
        auditStart = today
        auditEnd = today
        Task { await loadAuditLogs(item, append: false) }
    }

    func closeAudit() {
        auditParent = nil
        auditLogs = []
        auditNextPageToken = nil
        auditError = nil
        auditLoading = false
        auditLoadingMore = false
    }

    func searchAudit(_ item: TenantItem) {
        let start = auditStart.trimmingCharacters(in: .whitespacesAndNewlines)
        let endRaw = auditEnd.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = endRaw.isEmpty ? start : endRaw
        guard !start.isEmpty else {
            ToastCenter.shared.error("请选择开始日期")
            return
        }
        if start > end {
            ToastCenter.shared.error("开始日期不能晚于结束日期")
            return
        }
        auditEnd = end
        Task { await loadAuditLogs(item, append: false) }
    }

    func loadMoreAudit(_ item: TenantItem) {
        guard auditNextPageToken != nil, !auditLoadingMore, !auditLoading else { return }
        Task { await loadAuditLogs(item, append: true) }
    }

    func loadAuditLogs(_ item: TenantItem, append: Bool) async {
        if append {
            guard let token = auditNextPageToken, !token.isEmpty else { return }
            auditLoadingMore = true
        } else {
            auditLoading = true
            auditNextPageToken = nil
            auditError = nil
            auditLogs = []
        }
        defer {
            auditLoading = false
            auditLoadingMore = false
        }
        do {
            let page = try await service.auditLogs(
                tenantId: item.id,
                start: auditStart.isEmpty ? nil : auditStart,
                end: auditEnd.isEmpty ? nil : auditEnd,
                pageToken: append ? auditNextPageToken : nil
            )
            if append {
                auditLogs.append(contentsOf: page.items)
            } else {
                auditLogs = page.items
            }
            auditNextPageToken = page.nextPageToken
        } catch {
            auditError = error.localizedDescription
            if !append {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    private static func todayDateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func openEmail(_ item: TenantItem) {
        activeSheet = .email(item)
        emailDomain = ""
        emailTestAddress = ""
        emailEnabled = item.emailEnable == 1
        emailViewOnly = item.emailEnable == 1
        emailInfo = item.emailEnable == 1 ? "已启用（可重置域名或禁用）" : "未启用"
        Task {
            do {
                let info = try await service.emailTenantGet(tenantId: item.id)
                // Web: res.data[0].domainName
                if let data = info["data"] as? [[String: Any]], let first = data.first {
                    emailDomain = (first["domainName"] as? String)
                        ?? (first["emailDomain"] as? String)
                        ?? emailDomain
                } else if let data = info["data"] as? [String: Any] {
                    emailDomain = (data["domainName"] as? String)
                        ?? (data["emailDomain"] as? String)
                        ?? emailDomain
                }
                if let d = info["emailDomain"] as? String { emailDomain = d }
                if let m = info["message"] as? String { emailInfo = m }
            } catch { /* optional */ }
        }
    }

    func enableEmail(_ item: TenantItem) {
        let domain = emailDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else {
            ToastCenter.shared.error("请输入邮箱域名")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.enableEmail(tenantId: item.id, domain: domain)
                    activeSheet = nil
                    await reload()
                    AppAlert.info(title: "成功", message: "邮箱服务已启用")
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func disableEmail(_ item: TenantItem) {
        guard AppAlert.confirm(title: "禁用邮箱服务", message: "确定禁用该租户邮箱服务？") else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.disableEmail(tenantId: item.id)
                    activeSheet = nil
                    await reload()
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func testEmailService(_ item: TenantItem) {
        let to = emailTestAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard to.contains("@") else {
            ToastCenter.shared.error("请输入测试收件邮箱")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.testEmail(tenantId: item.id, testEmail: to)
                    AppAlert.info(title: "已发送", message: "测试邮件已提交")
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openSocial(_ item: TenantItem) {
        activeSheet = .social(item)
        resetSocialDraft(item)
        Task {
            await LoadingHUD.shared.during {
                do {
                    async let types = service.socialTypes()
                    async let list = service.socialList(tenantId: item.id)
                    socialTypes = try await types
                    socialItems = try await list
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func resetSocialDraft(_ item: TenantItem) {
        socialDraft = TenantSocialItem()
        socialDraft.tenantId = item.id
        socialDraft.cloudType = item.cloudType
        socialDraft.socialStatus = "active"
    }

    func editSocial(_ item: TenantItem, social: TenantSocialItem) {
        socialDraft = social
        socialDraft.tenantId = item.id
    }

    func saveSocial(_ item: TenantItem) {
        socialDraft.tenantId = item.id
        guard !socialDraft.socialTypeStr.isEmpty, !socialDraft.clientId.isEmpty else {
            ToastCenter.shared.error("请填写类型与 Client ID")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    if socialDraft.id > 0 {
                        try await service.socialUpdate(socialDraft)
                    } else {
                        try await service.socialAdd(socialDraft)
                    }
                    socialItems = try await service.socialList(tenantId: item.id)
                    resetSocialDraft(item)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func toggleSocial(_ item: TenantItem, social: TenantSocialItem, enable: Bool) {
        Task {
            await LoadingHUD.shared.during {
                do {
                    var s = social
                    s.tenantId = item.id
                    s.socialStatus = enable ? "active" : "disabled"
                    if enable {
                        try await service.socialEnable(s)
                    } else {
                        try await service.socialDisable(s)
                    }
                    socialItems = try await service.socialList(tenantId: item.id)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openQuota(_ item: TenantItem) {
        quotaParent = item
        quotaPage = 0
        quotaPageSize = 20
        quotaService = "compute"
        quotaItems = []
        quotaError = ""
        quotaRegionLabel = ""
        quotaHasNext = false
        quotaLoading = false
        quotaTenantId = "\(item.id)"
        quotaRegions = []
        Task {
            do {
                let regs = try await service.listRegions(parentId: item.id)
                if regs.isEmpty {
                    quotaRegions = []
                    quotaTenantId = "\(item.id)"
                } else {
                    quotaRegions = regs
                    quotaTenantId = regs[0].id
                }
            } catch {
                quotaRegions = []
            }
            // 不自动查询，需用户点击「查询」按钮
        }
    }

    func closeQuota() {
        quotaParent = nil
        quotaRegions = []
        quotaItems = []
        quotaError = ""
        quotaRegionLabel = ""
        quotaHasNext = false
        quotaLoading = false
        quotaPage = 0
        quotaTenantId = ""
    }

    func queryQuota(page: Int? = nil) async {
        if let page = page { quotaPage = page }
        guard let tid = Int64(quotaTenantId) else {
            ToastCenter.shared.error("请选择租户")
            return
        }
        quotaLoading = true
        quotaError = ""
        defer { quotaLoading = false }
        do {
            let r = try await service.quota(
                tenantId: tid,
                service: quotaService,
                page: quotaPage,
                pageSize: quotaPageSize
            )
            if let err = r["error"] as? String {
                quotaError = err
                quotaItems = []
                return
            }
            let parsed = TenantQuotaItem.parseList(from: r)
            quotaItems = parsed.items
            quotaPage = parsed.page
            quotaHasNext = parsed.hasNext
            quotaRegionLabel = parsed.region
        } catch {
            quotaError = error.localizedDescription
            quotaItems = []
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func openVolumes(_ item: TenantItem) {
        activeSheet = .bootVolumes(item)
        volumes = []
        editingVolumeId = nil
        volumesLoading = true
        volumesBusy = false
        Task { await reloadVolumes(item) }
    }

    /// - Parameter quiet: 保存/删除后刷新时为 true，仅用 volumesBusy 遮罩，避免闪两次 loading。
    func reloadVolumes(_ item: TenantItem, quiet: Bool = false) async {
        if !quiet { volumesLoading = true }
        defer { if !quiet { volumesLoading = false } }
        do {
            volumes = try await service.bootVolumes(tenantId: item.id)
        } catch {
            volumes = []
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func beginEditVolume(_ v: TenantBootVolume) {
        editingVolumeId = v.id
        editVolumeName = v.displayName
        editVolumeVpus = Double(v.vpusPerGB > 0 ? v.vpusPerGB : 10)
    }

    func saveVolumeEdit(for item: TenantItem) {
        guard let vid = editingVolumeId else { return }
        let name = editVolumeName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Web: VPUs 10–120 step 10
        let raw = Int64(editVolumeVpus.rounded())
        let vpus = max(10 as Int64, min(120 as Int64, (raw / 10) * 10))
        let tenantId = item.id
        Task {
            await self.runSheetBusy(flag: \.volumesBusy) {
                try await self.service.updateBootVolume(tenantId: tenantId, volumeId: vid, name: name, vpus: vpus)
                self.editingVolumeId = nil
                await self.reloadVolumes(item, quiet: true)
            }
        }
    }

    func deleteVolume(for item: TenantItem, volume: TenantBootVolume) {
        guard AppAlert.confirm(title: "删除引导卷", message: "确定删除 \(volume.displayName)？") else { return }
        Task {
            await self.runSheetBusy(flag: \.volumesBusy) {
                try await self.service.deleteBootVolume(tenantId: item.id, volumeId: volume.id)
                await self.reloadVolumes(item, quiet: true)
            }
        }
    }

    // MARK: - Account check / Import / Export

    func startAccountCheck() {
        checkLines = []
        checkResult = nil
        checkPercent = 0
        activeSheet = .accountCheck
        // Box counters so SSE callback can mutate without capturing var across concurrency
        let counters = CheckCounters()
        Task {
            do {
                try await service.streamSSE(path: "/tenants/checkAccountsStream") { event, data in
                    DispatchQueue.main.async {
                        if event == "start" {
                            if let raw = data.data(using: .utf8),
                               let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
                                counters.total = obj["total"] as? Int ?? 0
                                self.checkLines.append((obj["message"] as? String) ?? data)
                            } else {
                                self.checkLines.append(data)
                            }
                        } else if event == "progress" {
                            counters.processed += 1
                            self.checkLines.append(data)
                            if counters.total > 0 {
                                self.checkPercent = min(100, counters.processed * 100 / counters.total)
                            }
                        } else if event == "complete" {
                            self.checkPercent = 100
                            if let raw = data.data(using: .utf8),
                               let r = try? JSONDecoder().decode(TenantAccountCheckResult.self, from: raw) {
                                self.checkResult = r
                            }
                            self.checkLines.append("检测完成")
                        } else if event == "error" {
                            ToastCenter.shared.error(data)
                        }
                    }
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    func openExportAll() {
        resetExportForm()
        activeSheet = .exportAll
        // Web: 打开导出即自动 POST sendExportCode
        sendExportCode(silentIfAlready: false)
    }

    func openExportOne(_ item: TenantItem) {
        resetExportForm()
        activeSheet = .exportOne(item)
        sendExportCode(silentIfAlready: false)
    }

    private func resetExportForm() {
        exportCode = ""
        exportSent = false
        exportSending = false
    }

    /// 发送导出验证码（Telegram/通知终端，非邮箱）。
    /// - Parameter silentIfAlready: 预留；当前每次调用都会请求后端。
    func sendExportCode(silentIfAlready: Bool = false) {
        if exportSending { return }
        if silentIfAlready, exportSent { return }
        exportSending = true
        Task { @MainActor in
            do {
                try await service.sendExportCode()
                exportSent = true
                ToastCenter.shared.success("验证码已发送至通知终端")
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            exportSending = false
        }
    }

    func doExportAll() {
        runExport(defaultName: "all_tenants_data.json") {
            try await self.service.exportAll(code: $0)
        }
    }

    func doExportOne(_ item: TenantItem) {
        runExport(defaultName: "tenant_\(item.id)_data.json") {
            try await self.service.exportTenant(id: item.id, code: $0)
        }
    }

    /// 校验验证码 → 拉 JSON → 关 sheet → 系统保存面板（避免 sheet 与 NSSavePanel 叠层冲突）。
    private func runExport(defaultName: String, fetch: @escaping (String) async throws -> (Data, String?)) {
        let code = exportCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            ToastCenter.shared.error("请输入 6 位验证码")
            return
        }
        Task { @MainActor in
            do {
                let (data, name) = try await LoadingHUD.shared.during {
                    try await fetch(code)
                }
                let out = Self.prettyJSONData(data) ?? data
                let fileName = name ?? defaultName
                activeSheet = nil
                exportCode = ""
                // 等 sheet 收起后再弹保存面板
                try? await Task.sleep(nanoseconds: 180_000_000)
                saveData(out, suggested: fileName)
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    /// Web 侧 `JSON.stringify(code, null, 2)` 对齐：导出可读 JSON。
    private static func prettyJSONData(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
        else { return nil }
        return pretty
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    let data = try Data(contentsOf: url)
                    try await service.importJSON(data)
                    await reload()
                    AppAlert.info(title: "导入成功", message: "租户数据已导入")
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Native subpages (no WebEmbed)

    func openBoot(_ item: TenantItem) {
        bootArchitecture = "ARM"
        bootOcpu = "1"; bootMemory = "6"; bootDisk = "50"
        bootLoopTime = "60"; bootCount = "1"; bootDayGap = ""
        bootImages = []; bootOSList = []; bootSelectedOS = ""
        bootVersions = []; bootSelectedVersion = ""; bootImageId = ""
        bootRootPassword = randomPassword()
        bootSelectedRegionTenantId = "\(item.id)"
        bootRegionOptions = [
            TenantRegionOption(id: "\(item.id)", tenancyName: item.displayName, region: item.region)
        ]
        bootPageParent = item
        Task {
            do {
                let regs = try await service.listRegions(parentId: item.id)
                if !regs.isEmpty {
                    bootRegionOptions = regs
                    bootSelectedRegionTenantId = regs[0].id
                }
                await loadBootImages(tenantId: Int64(bootSelectedRegionTenantId) ?? item.id)
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    func closeBootCreate() {
        bootPageParent = nil
        bootImages = []; bootOSList = []; bootVersions = []
    }

    func loadBootImages(tenantId: Int64) async {
        do {
            let imgs = try await service.querySystemImages(tenantId: tenantId, shapeType: bootArchitecture)
            bootImages = imgs
            let oss = Array(Set(imgs.map(\.operatingSystem))).sorted()
            bootOSList = oss
            if let first = oss.first {
                bootSelectedOS = first
                applyBootOS(first)
            }
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func applyBootOS(_ os: String) {
        bootSelectedOS = os
        bootVersions = bootImages.filter { $0.operatingSystem == os }
        if let v = bootVersions.first {
            bootSelectedVersion = v.operatingSystemVersion
            bootImageId = v.imageId
        } else {
            bootSelectedVersion = ""
            bootImageId = ""
        }
    }

    func applyBootVersion(_ ver: String) {
        bootSelectedVersion = ver
        if let hit = bootVersions.first(where: { $0.operatingSystemVersion == ver }) {
            bootImageId = hit.imageId
        }
    }

    func submitBoot(_ item: TenantItem) {
        guard !bootImageId.isEmpty else {
            ToastCenter.shared.error("请选择系统镜像")
            return
        }
        let tid = bootSelectedRegionTenantId.isEmpty ? "\(item.id)" : bootSelectedRegionTenantId
        let fields: [String: String] = [
            "tenantId": tid,
            "ocpu": bootOcpu,
            "memory": bootMemory,
            "disk": bootDisk,
            "architecture": bootArchitecture,
            "loopTime": bootLoopTime,
            "instanceCount": bootCount,
            "rootPassword": bootRootPassword.isEmpty ? randomPassword() : bootRootPassword,
            "imageId": bootImageId,
            "operatingSystem": bootSelectedOS,
            "operatingSystemVersion": bootSelectedVersion,
            "dayGap": bootDayGap,
            "notifyFlag": "NO",
            "cloudType": "1"
        ]
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.saveBootInstance(fields: fields)
                    bootPageParent = nil
                    activeSheet = nil
                    AppAlert.info(title: "成功", message: "开机任务已创建")
                    await reload()
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    /// 进入 Web「租户详情」整页（`/tenants/regionList`），非弹框
    func openRegionList(_ item: TenantItem) {
        detailParent = item
        detailRows = []
        detailError = nil
        detailNamesHidden = namesHidden
        Task { await reloadDetail() }
    }

    func closeDetail() {
        detailParent = nil
        detailRows = []
        detailError = nil
        regionChildren = []
    }

    func reloadDetail() async {
        guard let parent = detailParent else { return }
        detailLoading = true
        detailError = nil
        defer { detailLoading = false }
        do {
            // 优先全量接口（含 openBootFlag / apiSynced / supportAI / createdAt）
            let full = try await service.regionListDetail(tenantId: parent.id)
            if !full.isEmpty {
                detailRows = full
                regionChildren = full.map {
                    TenantRegionOption(
                        id: "\($0.id)",
                        tenancyName: $0.displayName,
                        userName: $0.userName,
                        region: $0.region,
                        tenantId: $0.tenantId,
                        isHomeRegion: $0.isHomeRegion,
                        hasChildren: $0.hasChildren
                    )
                }
                return
            }
            // 空结果时兜底 listRegions
            let regs = try await service.listRegions(parentId: parent.id)
            regionChildren = regs
            detailRows = detailRowsFallback(parent: parent, regs: regs)
        } catch {
            detailError = error.localizedDescription
            // 兜底：列表上的 children
            if !parent.children.isEmpty {
                detailRows = [parent] + parent.children
            } else {
                detailRows = [parent]
            }
        }
    }

    private func detailRowsFallback(parent: TenantItem, regs: [TenantRegionOption]) -> [TenantItem] {
        var known: [Int64: TenantItem] = [:]
        for t in [parent] + parent.children { known[t.id] = t }
        if regs.isEmpty { return [parent] }
        return regs.map { r in
            if let id = Int64(r.id), let full = known[id] {
                var merged = full
                if merged.region.isEmpty { merged.region = r.region }
                if merged.defName.isEmpty { merged.defName = parent.defName }
                merged.isHomeRegion = r.isHomeRegion || full.isHomeRegion
                return merged
            }
            return r.toTenantItem(fallback: parent)
        }
    }

    func syncDetailRow(_ item: TenantItem) {
        startOciSync(item, afterSuccess: { [weak self] in
            await self?.reloadDetail()
        })
    }

    /// 对齐 Web `handleSync`：进度条 + 长超时请求，避免 60s 误超时。
    private func startOciSync(_ item: TenantItem, afterSuccess: @escaping () async -> Void) {
        syncTickerTask?.cancel()
        syncPercent = 0
        syncPhase = .running
        syncTenantName = item.displayName
        syncStatusText = "正在同步 OCI 资源…"
        activeSheet = .syncProgress(tenantId: item.id, name: item.displayName)

        // 假进度：约 180s 爬到 98%（与 Web 一致）；真实完成再拉到 100%
        syncTickerTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let totalSeconds: Double = 180
            var elapsed: Double = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s 更丝滑
                guard !Task.isCancelled else { return }
                switch self.syncPhase {
                case .success, .error:
                    return
                case .running, .waitingLong:
                    break
                }
                elapsed += 0.25
                if elapsed >= totalSeconds {
                    if self.syncPhase == .running {
                        self.syncPhase = .waitingLong
                        self.syncPercent = 98
                        self.syncStatusText = "同步时间较长，仍在等待服务端完成…"
                    }
                    continue
                }
                let p = min(98, (elapsed / totalSeconds) * 100)
                if p > self.syncPercent { self.syncPercent = p }
            }
        }

        let tenantId = item.id
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.service.syncOci(tenantId: tenantId)
                await MainActor.run {
                    self.syncTickerTask?.cancel()
                    self.syncPercent = 100
                    self.syncPhase = .success
                    self.syncStatusText = "同步成功"
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run {
                    if case .syncProgress(let id, _) = self.activeSheet, id == tenantId {
                        self.activeSheet = nil
                    }
                }
                await afterSuccess()
            } catch {
                let msg = error.localizedDescription
                let friendly: String = {
                    let lower = msg.lowercased()
                    if lower.contains("timed out") || lower.contains("timeout") || lower.contains("超时") {
                        return "同步超时，请稍后重试或检查网络"
                    }
                    return msg.isEmpty ? "同步失败" : msg
                }()
                await MainActor.run {
                    self.syncTickerTask?.cancel()
                    self.syncPhase = .error
                    self.syncStatusText = friendly
                    if self.syncPercent < 20 { self.syncPercent = 20 }
                }
            }
        }
    }

    func dismissSyncProgress() {
        syncTickerTask?.cancel()
        syncTickerTask = nil
        if case .syncProgress = activeSheet {
            activeSheet = nil
        }
    }

    /// 详情页 → 实例列表（Web `/oci/list?tenantId=`）
    func openInstancesList(_ item: TenantItem) {
        let parentId = detailParent.map { "\($0.id)" } ?? "\(item.id)"
        let regionId = "\(item.id)"
        NavigationState.shared.openInstances(parentId: parentId, regionId: regionId)
    }

    /// 详情页 → 抢机/开机任务（Web `/boot/fullBootList?tenantId=`）
    func openBootTaskList(_ item: TenantItem) {
        let parentId = detailParent.map { "\($0.id)" } ?? "\(item.id)"
        let regionId = "\(item.id)"
        NavigationState.shared.openBootTasks(parentId: parentId, regionId: regionId)
    }

    func openSecurityRules(_ item: TenantItem) {
        rulesTab = "ingress"
        securityRules = []
        showAddRule = false
        rulesBusy = false
        activeSheet = .securityRules(item)
        loadSecurityRules(item)
    }

    func loadSecurityRules(_ item: TenantItem) {
        rulesLoading = true
        let tab = rulesTab
        let tid = item.id
        Task {
            do {
                let list = try await service.securityRules(tenantId: tid, type: tab)
                await MainActor.run {
                    self.securityRules = list
                    self.rulesLoading = false
                }
            } catch {
                await MainActor.run {
                    ToastCenter.shared.error(error.localizedDescription)
                    self.securityRules = []
                    self.rulesLoading = false
                }
            }
        }
    }

    func switchRulesTab(_ tab: String, item: TenantItem) {
        rulesTab = tab
        securityRules = []
        loadSecurityRules(item)
    }

    func saveSecurityRule(_ item: TenantItem) {
        let source = ruleSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let ports = rulePorts.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            ToastCenter.shared.error("请填写源地址")
            return
        }
        Task {
            await self.runSheetBusy(flag: \.rulesBusy) {
                try await self.service.addSecurityRule(
                    tenantId: item.id,
                    type: self.rulesTab,
                    protocolValue: self.ruleProtocol,
                    source: source,
                    ports: ports
                )
                self.showAddRule = false
                self.rulePorts = ""
                self.loadSecurityRules(item)
            }
        }
    }

    func deleteSecurityRule(at index: Int, item: TenantItem) {
        let composite = "\(item.id)_\(index)_\(rulesTab)"
        guard AppAlert.confirm(title: "删除规则", message: "确定删除该安全规则？") else { return }
        Task {
            await self.runSheetBusy(flag: \.rulesBusy) {
                try await self.service.deleteSecurityRule(compositeId: composite)
                self.loadSecurityRules(item)
            }
        }
    }

    func openMysql(_ item: TenantItem) {
        mysqlRows = []
        mysqlBusy = false
        mysqlRevealedPasswordIds = []
        activeSheet = .mysql(item)
        loadMysql(item)
    }

    func loadMysql(_ item: TenantItem) {
        mysqlLoading = true
        let tid = item.id
        Task {
            do {
                let list = try await service.mysqlInfo(tenantId: tid)
                await MainActor.run {
                    self.mysqlRows = list
                    self.mysqlLoading = false
                }
            } catch {
                await MainActor.run {
                    ToastCenter.shared.error(error.localizedDescription)
                    self.mysqlRows = []
                    self.mysqlLoading = false
                }
            }
        }
    }

    func syncMysqlCloud(_ item: TenantItem) {
        Task {
            await self.runSheetBusy(flag: \.mysqlBusy) {
                try await self.service.syncMysql(tenantId: item.id)
                self.loadMysql(item)
            }
        }
    }

    func createMysql(_ item: TenantItem) {
        guard AppAlert.confirm(
            title: "创建 MySQL",
            message: "将按免费额度创建 HeatWave MySQL 实例，确认继续？"
        ) else { return }
        Task {
            await self.runSheetBusy(flag: \.mysqlBusy) {
                try await self.service.createMysql(tenantId: item.id)
                AppAlert.info(title: "已提交", message: "创建任务已发送，请稍后刷新列表")
                self.loadMysql(item)
            }
        }
    }

    func syncSingleMysql(_ row: TenantMysqlInstance, tenant: TenantItem) {
        Task {
            await self.runSheetBusy(flag: \.mysqlBusy) {
                try await self.service.syncSingleMysql(id: row.id)
                self.loadMysql(tenant)
            }
        }
    }

    func bindMysqlPublicIp(_ row: TenantMysqlInstance, tenant: TenantItem) {
        guard AppAlert.confirm(title: "绑定公网 IP", message: "确认为该数据库绑定公网 IP？") else { return }
        Task {
            await self.runSheetBusy(flag: \.mysqlBusy) {
                try await self.service.bindMysqlPublicIp(id: row.id)
                self.loadMysql(tenant)
            }
        }
    }

    func resetMysqlAuth(_ row: TenantMysqlInstance, tenant: TenantItem) {
        guard AppAlert.confirm(
            title: "重置数据库密码",
            message: "将重置 \(row.displayName.isEmpty ? "该实例" : row.displayName) 的登录密码，确认？"
        ) else { return }
        Task {
            await self.runSheetBusy(flag: \.mysqlBusy) {
                try await self.service.resetMysqlAuth(id: row.id, tenantId: tenant.id)
                AppAlert.info(title: "成功", message: "密码已重置，请刷新后查看")
                self.loadMysql(tenant)
            }
        }
    }

    func deleteMysql(_ row: TenantMysqlInstance, tenant: TenantItem) {
        guard AppAlert.confirm(
            title: "终止数据库",
            message: "确定终止并删除 \(row.displayName.isEmpty ? "该实例" : row.displayName)？此操作不可恢复。"
        ) else { return }
        Task {
            await self.runSheetBusy(flag: \.mysqlBusy) {
                try await self.service.mysqlAction(tenantId: tenant.id, id: row.id, action: "delete")
                self.loadMysql(tenant)
            }
        }
    }

    func toggleMysqlPasswordReveal(_ id: String) {
        if mysqlRevealedPasswordIds.contains(id) {
            mysqlRevealedPasswordIds.remove(id)
        } else {
            mysqlRevealedPasswordIds.insert(id)
        }
    }

    func copyMysqlOcid(_ row: TenantMysqlInstance) {
        let text = row.dbId.isEmpty ? row.id : row.dbId
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastCenter.shared.success("OCID 已复制")
    }

    /// Sheet 内操作 loading（MainActor 安全；避免 Task 内 defer 触发 isolation 错误）。
    private func runSheetBusy(
        flag: ReferenceWritableKeyPath<TenantsViewModel, Bool>,
        _ work: () async throws -> Void
    ) async {
        self[keyPath: flag] = true
        do {
            try await work()
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
        self[keyPath: flag] = false
    }

    func openRegionSub(_ item: TenantItem) {
        subscribedRegions = []
        unsubscribedRegions = []
        selectedUnsubKeys = []
        regionSummaryText = ""
        regionSubTab = 0
        regionTotalCount = 0
        regionSubscribedCount = 0
        regionUnsubscribedCount = 0
        regionSubParent = item
        Task { await refreshRegionSub(item) }
    }

    func closeRegionSub() {
        regionSubParent = nil
        subscribedRegions = []
        unsubscribedRegions = []
        selectedUnsubKeys = []
    }

    func refreshRegionSub(_ item: TenantItem) async {
        regionSubLoading = true
        defer { regionSubLoading = false }
        do {
            async let sum = service.regionSummary(tenantId: item.id)
            async let sub = service.subscribedRegions(tenantId: item.id)
            async let unsub = service.unsubscribedRegions(tenantId: item.id)
            let s = try await sum
            subscribedRegions = try await sub
            unsubscribedRegions = try await unsub
            // Backend puts Integer sizes into JSON; JSONSerialization yields NSNumber, not String.
            regionTotalCount = Self.jsonInt(s["totalRegions"])
            regionSubscribedCount = Self.jsonInt(s["subscribedRegions"])
            regionUnsubscribedCount = Self.jsonInt(s["unsubscribedRegions"])
            // Fallback from list lengths if summary keys missing / zeroed incorrectly
            if regionSubscribedCount == 0, !subscribedRegions.isEmpty {
                regionSubscribedCount = subscribedRegions.count
            }
            if regionUnsubscribedCount == 0, !unsubscribedRegions.isEmpty {
                regionUnsubscribedCount = unsubscribedRegions.count
            }
            if regionTotalCount == 0 {
                regionTotalCount = regionSubscribedCount + regionUnsubscribedCount
            }
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    /// Parse JSON number/string values from `JSONSerialization` dictionaries.
    private static func jsonInt(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let n = any as? Int64 { return Int(n) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return 0
    }

    func toggleUnsubKey(_ key: String) {
        if selectedUnsubKeys.contains(key) { selectedUnsubKeys.remove(key) }
        else { selectedUnsubKeys.insert(key) }
    }

    func subscribeSelected(_ item: TenantItem) {
        let keys = Array(selectedUnsubKeys)
        guard !keys.isEmpty else {
            ToastCenter.shared.error("请先勾选要订阅的区域")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    let msg = try await service.subscribeRegions(tenantId: item.id, regionKeys: keys)
                    selectedUnsubKeys = []
                    await refreshRegionSub(item)
                    AppAlert.info(title: "订阅结果", message: msg)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openCost(_ item: TenantItem) {
        costParent = item
        costItems = []
        costError = nil
        costFilterPositiveOnly = false
        costChartType = "all"
        costPageState = PageState(page: 0, size: costPageState.size)
        applyCostPreset("month")
        // Web: 进入页后默认本月，需手动点查询（也可自动查一次）
        Task { await queryCost(item) }
    }

    func closeCost() {
        costParent = nil
        costItems = []
        costError = nil
        costLoading = false
        costPageState = PageState(page: 0, size: costPageState.size)
    }

    /// Web `selectCostTimePreset`: today / month / custom
    func applyCostPreset(_ preset: String) {
        costTimePreset = preset
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let now = Date()
        costEnd = f.string(from: now)
        switch preset {
        case "today":
            costStart = f.string(from: now)
        case "custom":
            // 保留当前起止，仅展示日期输入
            if costStart.isEmpty {
                let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
                costStart = f.string(from: lastMonth)
            }
        default: // month
            let comps = Calendar.current.dateComponents([.year, .month], from: now)
            costStart = f.string(from: Calendar.current.date(from: comps) ?? now)
            costTimePreset = "month"
        }
    }

    func queryCost(_ item: TenantItem) async {
        let start = costStart.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = costEnd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !start.isEmpty, !end.isEmpty else {
            ToastCenter.shared.error("请选择时间范围")
            return
        }
        if start > end {
            ToastCenter.shared.error("开始日期不能晚于结束日期")
            return
        }
        costLoading = true
        costError = nil
        defer { costLoading = false }
        do {
            costItems = try await service.queryCost(tenantId: item.id, start: start, end: end)
            costPageState.page = 0
            syncCostPagination()
        } catch {
            costError = error.localizedDescription
            costItems = []
            syncCostPagination()
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func toggleCostPositiveFilter() {
        costFilterPositiveOnly.toggle()
        costPageState.page = 0
        syncCostPagination()
    }

    /// 按筛选结果回填 `PageState` 总数（客户端分页，无服务端请求）。
    func syncCostPagination() {
        costPageState.apply(totalElements: Int64(filteredCostItems.count))
    }

    /// 筛选后的明细（Web toggleCostFilter）。
    var filteredCostItems: [TenantCostItem] {
        if costFilterPositiveOnly {
            return costItems.filter { $0.cost > 0 }
        }
        return costItems
    }

    var costPageItems: [TenantCostItem] {
        let all = filteredCostItems
        let start = costPageState.page * costPageState.size
        guard start < all.count else { return [] }
        let end = min(start + costPageState.size, all.count)
        return Array(all[start..<end])
    }

    // MARK: - Cost aggregations (mirror oci_cost.js)

    var costTotal: Double { costItems.reduce(0) { $0 + $1.cost } }
    var costCompute: Double { costItems.filter { $0.category == .compute }.reduce(0) { $0 + $1.cost } }
    var costStorage: Double { costItems.filter { $0.category == .storage }.reduce(0) { $0 + $1.cost } }
    var costNetwork: Double { costItems.filter { $0.category == .network }.reduce(0) { $0 + $1.cost } }
    var costOther: Double { costItems.filter { $0.category == .other }.reduce(0) { $0 + $1.cost } }

    /// 按日分系列（折线图）。
    var costTrendSeries: (days: [String], compute: [Double], storage: [Double], network: [Double], other: [Double]) {
        var map: [String: (c: Double, s: Double, n: Double, o: Double)] = [:]
        for item in costItems {
            let d = item.day.isEmpty ? "—" : item.day
            var cur = map[d] ?? (0, 0, 0, 0)
            switch item.category {
            case .compute: cur.c += item.cost
            case .storage: cur.s += item.cost
            case .network: cur.n += item.cost
            case .other: cur.o += item.cost
            }
            map[d] = cur
        }
        let days = map.keys.sorted()
        return (
            days,
            days.map { map[$0]?.c ?? 0 },
            days.map { map[$0]?.s ?? 0 },
            days.map { map[$0]?.n ?? 0 },
            days.map { map[$0]?.o ?? 0 }
        )
    }

    func openTrafficPage(_ item: TenantItem) {
        tqRows = []
        tqRegions = []
        tqSelectedRegionIds = []
        tqPeriod = "1d"
        tqThresholdGB = 10240
        trafficParent = item
        applyTrafficPreset("month")
        Task { await prepareTrafficPage(item) }
    }

    func closeTrafficPage() {
        trafficParent = nil
        tqRows = []
        tqRegions = []
        tqSelectedRegionIds = []
    }

    /// Web `selectTimePreset`: today / month / custom.
    func applyTrafficPreset(_ preset: String) {
        tqTimePreset = preset
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let now = Date()
        tqEnd = f.string(from: now)
        switch preset {
        case "today":
            tqStart = f.string(from: now)
        case "custom":
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            tqStart = f.string(from: lastMonth)
        default: // month
            let comps = Calendar.current.dateComponents([.year, .month], from: now)
            tqStart = f.string(from: Calendar.current.date(from: comps) ?? now)
            tqTimePreset = "month"
        }
    }

    func toggleTrafficRegion(_ id: String) {
        if tqSelectedRegionIds.contains(id) {
            tqSelectedRegionIds.remove(id)
        } else {
            tqSelectedRegionIds.insert(id)
        }
    }

    func selectAllTrafficRegions() {
        tqSelectedRegionIds = Set(tqRegions.map(\.id).filter { !$0.isEmpty })
        if tqSelectedRegionIds.isEmpty, let t = trafficParent {
            tqSelectedRegionIds = ["\(t.id)"]
        }
    }

    func clearTrafficRegions() {
        tqSelectedRegionIds = []
    }

    private func prepareTrafficPage(_ item: TenantItem) async {
        await LoadingHUD.shared.during {
            do {
                // Load regions (Web loadRegionsData) — do not auto query; wait for manual 查询
                let regions = try await service.listRegions(parentId: item.id)
                tqRegions = regions
                tqSelectedRegionIds = []
                tqRows = []

                // Threshold (Web fetchTrafficAlertThreshold)
                if let th = try? await service.monitorTrafficThreshold(tenantId: item.id) {
                    tqThresholdGB = th > 0 ? th : 10240
                }
            } catch {
                tqRegions = []
                tqSelectedRegionIds = []
                tqRows = []
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    func queryTraffic(_ item: TenantItem) async {
        // Resolve date range from preset (Web getStartDate / getEndDate)
        resolveTrafficDates()

        var ids = Array(tqSelectedRegionIds)
        if ids.isEmpty {
            // Prefer child regions; fall back to parent
            if !tqRegions.isEmpty {
                ToastCenter.shared.error("请选择区域")
                return
            }
            ids = ["\(item.id)"]
        }

        await LoadingHUD.shared.during {
            do {
                if let th = try? await service.monitorTrafficThreshold(tenantId: item.id) {
                    tqThresholdGB = th > 0 ? th : 10240
                }
                tqRows = try await service.instanceTraffic(
                    tenantIds: ids,
                    start: tqStart,
                    end: tqEnd,
                    period: tqPeriod
                )
            } catch {
                tqRows = []
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    private func resolveTrafficDates() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let now = Date()
        switch tqTimePreset {
        case "today":
            tqStart = f.string(from: now)
            tqEnd = f.string(from: now)
        case "custom":
            // keep tqStart / tqEnd as user-edited
            break
        default: // month
            let comps = Calendar.current.dateComponents([.year, .month], from: now)
            tqStart = f.string(from: Calendar.current.date(from: comps) ?? now)
            tqEnd = f.string(from: now)
        }
    }

    /// 跳转「我的工具 → AI 对话」整页，并预选当前租户（不再用 sheet）。
    func openAI(_ item: TenantItem) {
        closeAIChat()
        FloatingMenuDismiss.all()
        NavigationState.shared.openAiChat(tenantId: item.id)
    }

    func connectAIChat(tenantId: Int64) {
        closeAIChat()
        aiTenantId = tenantId
        guard var comps = URLComponents(string: session.serverURL) else { return }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        comps.path = "/ws/aiChat"
        comps.query = nil
        guard let url = comps.url else { return }

        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        let sess = URLSession(configuration: cfg)
        aiSession = sess
        let task = sess.webSocketTask(with: url)
        aiWS = task
        task.resume()
        aiStatus = "连接中…"
        receiveAILoop()
        // init after brief delay so socket is open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            let modelId = self.aiSelectedModelId
            let initMsg: [String: Any] = [
                "type": "init",
                "tenant": ["tenantId": "\(tenantId)", "modelId": modelId]
            ]
            self.sendAIJSON(initMsg)
            self.aiConnected = true
            self.aiStatus = "已连接"
        }
    }

    func sendAIMessage() {
        let text = aiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard aiConnected else {
            ToastCenter.shared.error("WebSocket 未连接")
            return
        }
        guard !aiSelectedModelId.isEmpty else {
            ToastCenter.shared.error("请选择模型")
            return
        }
        aiLines.append(TenantChatLine(role: "user", text: text))
        aiInput = ""
        sendAIJSON([
            "type": "chat",
            "message": text,
            "modelId": aiSelectedModelId,
            "tenantId": "\(aiTenantId)",
            "useHistory": aiUseHistory
        ])
    }

    func closeAIChat() {
        aiWS?.cancel(with: .goingAway, reason: nil)
        aiWS = nil
        aiSession = nil
        aiConnected = false
    }

    private func sendAIJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        aiWS?.send(.string(str)) { err in
            if let err = err {
                DispatchQueue.main.async {
                    ToastCenter.shared.error(err.localizedDescription)
                }
            }
        }
    }

    private func receiveAILoop() {
        aiWS?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.aiConnected = false
                    self.aiStatus = "断开: \(error.localizedDescription)"
                }
            case .success(let message):
                var text = ""
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
                @unknown default: break
                }
                if let data = text.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async { self.handleAIMessage(obj) }
                }
                self.receiveAILoop()
            }
        }
    }

    private func handleAIMessage(_ obj: [String: Any]) {
        let type = obj["type"] as? String ?? ""
        switch type {
        case "init":
            if let status = obj["status"] as? String, status != "success" {
                aiStatus = (obj["message"] as? String) ?? "初始化失败"
            } else {
                aiStatus = "已连接"
                aiConnected = true
            }
        case "chat":
            if let role = obj["role"] as? String, role == "assistant",
               let msg = obj["message"] as? String {
                if let isChunk = obj["isChunk"] as? Bool, isChunk {
                    if let last = aiLines.last, last.role == "ai" {
                        var updated = last
                        updated.text += msg
                        aiLines[aiLines.count - 1] = updated
                    } else {
                        aiLines.append(TenantChatLine(role: "ai", text: msg))
                    }
                } else {
                    aiLines.append(TenantChatLine(role: "ai", text: msg))
                }
            }
        case "chat_end":
            break
        case "error":
            ToastCenter.shared.error((obj["message"] as? String) ?? "AI 错误")
        default:
            break
        }
    }

    // MARK: - Helpers

    private func saveData(_ data: Data, suggested: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.allowedFileTypes = ["json"]
        panel.message = "导出租户 JSON（含 API 私钥内容，请妥善保管）"
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                try data.write(to: dest, options: .atomic)
                ToastCenter.shared.success("已保存 \(dest.lastPathComponent)")
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    private func randomPassword() -> String {
        let chars = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#")
        return String((0..<16).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private func prettyJSONValue(_ data: AnyCodableJSON?) -> String {
        guard let data = data else { return "无数据" }
        let obj = jsonBox(data)
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "\(obj)"
    }

    private func jsonBox(_ j: AnyCodableJSON) -> Any {
        switch j {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map { jsonBox($0) }
        case .object(let o):
            var d: [String: Any] = [:]
            for (k, v) in o { d[k] = jsonBox(v) }
            return d
        }
    }

}



/// Mutable counters for SSE progress (avoids capturing `var` in concurrent closures).
private final class CheckCounters {
    var total = 0
    var processed = 0
}
