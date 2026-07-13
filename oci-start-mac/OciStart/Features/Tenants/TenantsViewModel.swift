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

    // Audit
    @Published var auditLogs: [TenantAuditLogEntry] = []
    @Published var auditStart = ""
    @Published var auditEnd = ""

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

    // Quota
    @Published var quotaRegions: [TenantRegionOption] = []
    @Published var quotaTenantId = ""
    @Published var quotaService = "compute"
    @Published var quotaPage = 0
    @Published var quotaPageSize = 20
    @Published var quotaItems: [TenantQuotaItem] = []
    @Published var quotaHasNext = false
    @Published var quotaRegionLabel = ""
    @Published var quotaError = ""

    // Boot volumes
    @Published var volumes: [TenantBootVolume] = []
    @Published var editingVolumeId: String?
    @Published var editVolumeName = ""
    @Published var editVolumeVpus: Double = 10

    // Account check
    @Published var checkLines: [String] = []
    @Published var checkResult: TenantAccountCheckResult?
    @Published var checkPercent: Int = 0

    // Export
    @Published var exportCode = ""
    @Published var exportSent = false

    // Update SSE
    @Published var updateLines: [String] = []

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
    @Published var ruleProtocol = "tcp"
    @Published var ruleSource = "0.0.0.0/0"
    @Published var rulePorts = ""
    @Published var showAddRule = false

    // MySQL sheet
    @Published var mysqlRows: [TenantMysqlInstance] = []
    @Published var mysqlLoading = false

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

    // Cost
    @Published var costStart = ""
    @Published var costEnd = ""
    @Published var costResultText = ""

    // Traffic query page
    @Published var trafficParent: TenantItem?
    @Published var tqStart = ""
    @Published var tqEnd = ""
    @Published var tqPeriod = "1d"
    @Published var tqRows: [TenantTrafficRow] = []

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
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.syncOci(tenantId: item.id)
                    await reload()
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
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
        activeSheet = .audit(item)
        auditLogs = []
        Task {
            await LoadingHUD.shared.during {
                do {
                    auditLogs = try await service.auditLogs(tenantId: item.id, start: auditStart, end: auditEnd, pageToken: nil)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func searchAudit(_ item: TenantItem) {
        Task {
            await LoadingHUD.shared.during {
                do {
                    auditLogs = try await service.auditLogs(tenantId: item.id, start: auditStart, end: auditEnd, pageToken: nil)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
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
        activeSheet = .quota(item)
        quotaPage = 0
        quotaPageSize = 20
        quotaService = "compute"
        quotaItems = []
        quotaError = ""
        quotaRegionLabel = ""
        quotaTenantId = "\(item.id)"
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
        }
    }

    func queryQuota(page: Int? = nil) {
        if let page = page { quotaPage = page }
        guard let tid = Int64(quotaTenantId) else {
            ToastCenter.shared.error("请选择租户")
            return
        }
        Task {
            await LoadingHUD.shared.during {
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
                    quotaError = ""
                    let parsed = TenantQuotaItem.parseList(from: r)
                    quotaItems = parsed.items
                    quotaPage = parsed.page
                    quotaHasNext = parsed.hasNext
                    quotaRegionLabel = parsed.region
                } catch {
                    quotaError = error.localizedDescription
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openVolumes(_ item: TenantItem) {
        activeSheet = .bootVolumes(item)
        volumes = []
        editingVolumeId = nil
        Task {
            await LoadingHUD.shared.during {
                do {
                    volumes = try await service.bootVolumes(tenantId: item.id)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
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
            await LoadingHUD.shared.during {
                do {
                    try await service.updateBootVolume(tenantId: tenantId, volumeId: vid, name: name, vpus: vpus)
                    editingVolumeId = nil
                    volumes = try await service.bootVolumes(tenantId: tenantId)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func deleteVolume(for item: TenantItem, volume: TenantBootVolume) {
        guard AppAlert.confirm(title: "删除引导卷", message: "确定删除 \(volume.displayName)？") else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.deleteBootVolume(tenantId: item.id, volumeId: volume.id)
                    volumes = try await service.bootVolumes(tenantId: item.id)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
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
        exportCode = ""
        exportSent = false
        activeSheet = .exportAll
    }

    func openExportOne(_ item: TenantItem) {
        exportCode = ""
        exportSent = false
        activeSheet = .exportOne(item)
    }

    func sendExportCode() {
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.sendExportCode()
                    exportSent = true
                    AppAlert.info(title: "验证码已发送", message: "请查收邮箱/通知中的导出验证码")
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func doExportAll() {
        let code = exportCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            ToastCenter.shared.error("请输入验证码")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    let (data, name) = try await service.exportAll(code: code)
                    saveData(data, suggested: name ?? "all_tenants_data.json")
                    activeSheet = nil
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func doExportOne(_ item: TenantItem) {
        let code = exportCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            ToastCenter.shared.error("请输入验证码")
            return
        }
        Task {
            await LoadingHUD.shared.during {
                do {
                    let (data, name) = try await service.exportTenant(id: item.id, code: code)
                    saveData(data, suggested: name ?? "tenant_\(item.id)_data.json")
                    activeSheet = nil
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
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
            let regs = try await service.listRegions(parentId: parent.id)
            regionChildren = regs
            var known: [Int64: TenantItem] = [:]
            for t in [parent] + parent.children { known[t.id] = t }
            if regs.isEmpty {
                // 无子区域时页面仍展示当前租户一行
                detailRows = [parent]
            } else {
                detailRows = regs.map { r in
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

    func syncDetailRow(_ item: TenantItem) {
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.syncOci(tenantId: item.id)
                    AppAlert.info(title: "成功", message: "已同步 \(item.displayName)")
                    await reloadDetail()
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openSecurityRules(_ item: TenantItem) {
        rulesTab = "ingress"
        securityRules = []
        showAddRule = false
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
            await LoadingHUD.shared.during {
                do {
                    try await service.addSecurityRule(
                        tenantId: item.id,
                        type: rulesTab,
                        protocolValue: ruleProtocol,
                        source: source,
                        ports: ports
                    )
                    showAddRule = false
                    rulePorts = ""
                    loadSecurityRules(item)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func deleteSecurityRule(at index: Int, item: TenantItem) {
        let composite = "\(item.id)_\(index)_\(rulesTab)"
        guard AppAlert.confirm(title: "删除规则", message: "确定删除该安全规则？") else { return }
        Task {
            await LoadingHUD.shared.during {
                do {
                    try await service.deleteSecurityRule(compositeId: composite)
                    loadSecurityRules(item)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openMysql(_ item: TenantItem) {
        mysqlRows = []
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
            await LoadingHUD.shared.during {
                do {
                    try await service.syncMysql(tenantId: item.id)
                    loadMysql(item)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
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
            regionTotalCount = Int((s["totalRegions"] as? String) ?? "0") ?? 0
            regionSubscribedCount = Int((s["subscribedRegions"] as? String) ?? "0") ?? 0
            regionUnsubscribedCount = Int((s["unsubscribedRegions"] as? String) ?? "0") ?? 0
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
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
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        costStart = f.string(from: start)
        costEnd = f.string(from: end)
        costResultText = ""
        activeSheet = .cost(item)
    }

    func queryCost(_ item: TenantItem) {
        Task {
            await LoadingHUD.shared.during {
                do {
                    let data = try await service.queryCost(tenantId: item.id, start: costStart, end: costEnd)
                    costResultText = prettyJSONValue(data)
                } catch {
                    ToastCenter.shared.error(error.localizedDescription)
                }
            }
        }
    }

    func openTrafficPage(_ item: TenantItem) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        tqStart = f.string(from: start)
        tqEnd = f.string(from: end)
        tqPeriod = "1d"
        tqRows = []
        trafficParent = item
        Task { await queryTraffic(item) }
    }

    func closeTrafficPage() {
        trafficParent = nil
        tqRows = []
    }

    func queryTraffic(_ item: TenantItem) async {
        await LoadingHUD.shared.during {
            do {
                // Include children region tenant ids when available
                var ids = [item.id]
                if let children = try? await service.listRegions(parentId: item.id) {
                    for c in children {
                        if let id = Int64(c.id) { ids.append(id) }
                    }
                }
                tqRows = try await service.instanceTraffic(
                    tenantIds: Array(Set(ids)),
                    start: tqStart,
                    end: tqEnd,
                    period: tqPeriod
                )
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    func openAI(_ item: TenantItem) {
        closeAIChat()
        aiModels = []
        aiSelectedModelId = ""
        aiLines = []
        aiInput = ""
        aiConnected = false
        aiStatus = "加载模型…"
        aiTenantId = item.id
        activeSheet = .aiChat(item)
        Task {
            do {
                let models = try await service.aiModels(tenantId: item.id)
                aiModels = models
                aiSelectedModelId = models.first?.id ?? ""
                if models.isEmpty {
                    aiStatus = "暂无可用模型"
                } else {
                    connectAIChat(tenantId: item.id)
                }
            } catch {
                aiStatus = error.localizedDescription
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
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
        if panel.runModal() == .OK, let dest = panel.url {
            do { try data.write(to: dest, options: .atomic) }
            catch { ToastCenter.shared.error(error.localizedDescription) }
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
