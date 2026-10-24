import Foundation
import Combine

@MainActor
final class AiModelsViewModel: ObservableObject {
    @Published private(set) var tenants: [AiTenantOption] = []
    @Published private(set) var selectedTenantId = ""
    @Published private(set) var models: [AiAvailableModel] = []
    @Published private(set) var configs: [AiConfigItem] = []
    @Published private(set) var linkTenantFilter = false
    @Published private(set) var isLoadingTenants = false
    @Published private(set) var isLoadingModels = false
    @Published private(set) var isLoadingConfigs = false
    @Published private(set) var tenantsLoaded = false
    @Published private(set) var modelsLoaded = false
    @Published private(set) var configsLoaded = false
    @Published private(set) var isBusy = false
    @Published private(set) var requiresReview = false
    @Published private(set) var tenantsError: String?
    @Published private(set) var modelsError: String?
    @Published private(set) var configsError: String?
    @Published private(set) var errorText: String?
    @Published private(set) var notice: String?
    @Published private(set) var operationContext = ""
    @Published var modelPage: PageState
    @Published var configPage: PageState

    let telegram: Bool
    private let session: AppSession
    private var service: AiModelsService { AiModelsService(baseURL: session.serverURL) }
    private var active = false
    private var tenantGeneration = 0
    private var modelGeneration = 0
    private var configGeneration = 0
    private var configRevision = 0
    private var reviewRevision = 0
    private var language: LanguageManager { LanguageManager.shared }

    private enum Action {
        case add(AiAvailableModel)
        case toggle(AiConfigItem, Bool)
        case delete(AiConfigItem)
        case batch(Bool)
    }

    init(session: AppSession = .shared, pageSize: Int = 6, telegram: Bool = false) {
        self.session = session
        self.telegram = telegram
        modelPage = PageState(page: 0, size: pageSize)
        configPage = PageState(page: 0, size: pageSize)
    }
    var configuredModelIds: Set<String> { Set(configs.map(\.modelId).filter { !$0.isEmpty }) }
    var visibleConfigs: [AiConfigItem] {
        linkTenantFilter && !selectedTenantId.isEmpty ? configs.filter { $0.tenantId == selectedTenantId } : configs
    }
    var pagedModels: [AiAvailableModel] { Array(models.dropFirst(modelPage.page * modelPage.size).prefix(modelPage.size)) }
    var pagedConfigs: [AiConfigItem] { Array(visibleConfigs.dropFirst(configPage.page * configPage.size).prefix(configPage.size)) }
    var refreshing: Bool { isLoadingTenants || isLoadingModels || isLoadingConfigs }
    var selectionLocked: Bool { isBusy || (telegram && requiresReview) }
    var canWrite: Bool { active && !isBusy && !requiresReview && !isLoadingTenants && configsLoaded && !isLoadingConfigs && configsError == nil }
    var reviewReady: Bool { requiresReview && !isBusy && !isLoadingConfigs && configsError == nil && configsLoaded && configRevision >= reviewRevision }
    var canEnableAll: Bool { configs.contains { $0.enabled != true } }
    var canDisableAll: Bool { configs.contains { $0.enabled != false } }
    var sortedTenants: [AiTenantOption] {
        tenants.sorted { tenantLabel($0.id).localizedStandardCompare(tenantLabel($1.id)) == .orderedAscending }
    }
    func tenantLabel(_ id: String) -> String {
        if let tenant = tenants.first(where: { $0.id == id }), !tenant.name.isEmpty { return tenant.name }
        return language.text("租户 \(id.isEmpty ? "—" : id)", "Tenant \(id.isEmpty ? "—" : id)")
    }
    func configTenant(_ config: AiConfigItem) -> String {
        if tenants.contains(where: { $0.id == config.tenantId }) { return tenantLabel(config.tenantId) }
        let parts = [config.userName, config.region].filter { !$0.isEmpty }
        return parts.isEmpty ? tenantLabel(config.tenantId) : parts.joined(separator: " · ")
    }

    func start() {
        guard !active else { return }
        if telegram {
            tenants = []; models = []; configs = []; selectedTenantId = ""
            tenantsLoaded = false; modelsLoaded = false; configsLoaded = false
            tenantsError = nil; modelsError = nil; configsError = nil; errorText = nil; notice = nil; operationContext = ""
            requiresReview = false; configRevision = 0; reviewRevision = 0
            modelPage.goFirst(); configPage.goFirst(); updatePages()
        }
        active = true
        reload()
    }
    func stop() { active = false; cancelReads() }
    func canLeave() -> Bool {
        if isBusy {
            ToastCenter.shared.error(language.text("AI 配置操作尚未完成，请等待结果。", "Wait for the AI configuration operation to finish."))
            return false
        }
        if telegram && requiresReview {
            ToastCenter.shared.error(language.text("请刷新并核对 AI 配置后再关闭。", "Refresh and review the AI settings before closing."))
            return false
        }
        return true
    }
    func setTenantFilter(_ enabled: Bool) {
        guard !isBusy else { return }
        linkTenantFilter = enabled; configPage.goFirst(); updatePages()
    }
    func onTenantChanged(_ id: String?) {
        guard !selectionLocked, !isLoadingTenants else { return }
        let value = id ?? ""
        guard value != selectedTenantId, value.isEmpty || tenants.contains(where: { $0.id == value }) else { return }
        resetTenant(value)
        if !value.isEmpty { refreshModels() }
    }
    private func resetTenant(_ value: String) {
        selectedTenantId = value; modelGeneration += 1; isLoadingModels = false
        models = []; modelsLoaded = false; modelsError = nil; modelPage.goFirst()
        if linkTenantFilter { configPage.goFirst() }
        updatePages()
    }
    func reload() {
        guard active, !isBusy else { return }
        Task { @MainActor in await loadTenants() }
        Task { @MainActor in _ = await loadConfigs() }
        if !telegram && !selectedTenantId.isEmpty { refreshModels() }
    }
    func refreshModels() {
        guard active, !selectionLocked, !selectedTenantId.isEmpty else { return }
        Task { @MainActor in await loadModels() }
    }
    func refreshConfigs() {
        guard active, !isBusy else { return }
        Task { @MainActor in _ = await loadConfigs() }
    }
    private func loadTenants() async {
        guard active else { return }
        tenantGeneration += 1; let generation = tenantGeneration
        isLoadingTenants = true; tenantsError = nil
        do {
            let rows = try await service.listTenants()
            guard active, generation == tenantGeneration else { return }
            tenants = rows; tenantsLoaded = true
            if !selectedTenantId.isEmpty && !rows.contains(where: { $0.id == selectedTenantId }) { resetTenant("") }
        } catch {
            guard active, generation == tenantGeneration else { return }
            tenantsError = describe(error)
        }
        if generation == tenantGeneration { isLoadingTenants = false }
    }
    private func loadModels() async {
        guard active, !selectedTenantId.isEmpty else { return }
        let tenant = selectedTenantId
        modelGeneration += 1; let generation = modelGeneration
        isLoadingModels = true; modelsError = nil
        do {
            let rows = try await service.listModels(tenantId: tenant)
            guard active, generation == modelGeneration, tenant == selectedTenantId else { return }
            models = rows; modelsLoaded = true; updatePages()
        } catch {
            guard active, generation == modelGeneration, tenant == selectedTenantId else { return }
            modelsError = describe(error)
        }
        if generation == modelGeneration { isLoadingModels = false }
    }
    @discardableResult private func loadConfigs() async -> Bool {
        guard active else { return false }
        configGeneration += 1; let generation = configGeneration
        isLoadingConfigs = true; configsError = nil
        do {
            let rows = try await service.listConfigs()
            guard active, generation == configGeneration else { return false }
            configs = rows; configsLoaded = true; configRevision += 1; updatePages()
            isLoadingConfigs = false
            if !telegram && !isBusy { requiresReview = false }
            return true
        } catch {
            guard active, generation == configGeneration else { return false }
            configsError = describe(error); isLoadingConfigs = false
            return false
        }
    }
    private func updatePages() {
        modelPage.apply(totalElements: Int64(models.count))
        configPage.apply(totalElements: Int64(visibleConfigs.count))
    }
    private func cancelReads() {
        tenantGeneration += 1; modelGeneration += 1; configGeneration += 1
        isLoadingTenants = false; isLoadingModels = false; isLoadingConfigs = false
    }
    func acknowledgeReview() {
        guard reviewReady else { return }
        requiresReview = false; errorText = nil; notice = nil; operationContext = ""
    }

    func addModel(_ model: AiAvailableModel) {
        guard canWrite, modelsLoaded, !isLoadingModels, modelsError == nil, tenantsError == nil,
              model.tenantId == selectedTenantId, !configuredModelIds.contains(model.id) else { return }
        if telegram && !confirm(title: language.text("添加 AI 模型", "Add AI model"), name: model.displayName, modelId: model.id, tenant: model.tenantId) { return }
        perform(.add(model))
    }
    func toggle(_ item: AiConfigItem, enabled: Bool? = nil) {
        guard canWrite, item.cloudType == 1 else { return }
        let value = enabled ?? (item.enabled != true)
        if telegram && !confirm(title: language.text(value ? "启用 AI 模型" : "停用 AI 模型", value ? "Enable AI model" : "Disable AI model"), name: item.displayName, modelId: item.modelId, tenant: item.tenantId) { return }
        perform(.toggle(item, value))
    }
    func delete(_ item: AiConfigItem) {
        guard canWrite, confirm(title: language.text("删除 AI 配置", "Delete AI configuration"), name: item.displayName,
                                modelId: item.modelId, tenant: item.tenantId, deleting: true) else { return }
        perform(.delete(item))
    }
    func batchEnable(_ enabled: Bool) {
        guard !telegram, canWrite, (enabled ? canEnableAll : canDisableAll) else { return }
        let title = language.text(enabled ? "全部启用" : "全部停用", enabled ? "Enable all" : "Disable all")
        guard AppAlert.confirm(title: title,
            message: language.text("将修改全部 \(configs.count) 条 OCI AI 配置，包含其他租户和其他页；当前租户筛选不限制操作范围。",
                                   "This changes all \(configs.count) OCI AI configurations, including other tenants and pages. The current tenant filter does not limit the operation."), confirmTitle: title) else { return }
        perform(.batch(enabled))
    }
    private func confirm(title: String, name: String, modelId: String, tenant: String, deleting: Bool = false) -> Bool {
        AppAlert.confirm(title: title, message: "\(name)\n\(tenantLabel(tenant))\nModel ID: \(modelId)\nTenant ID: \(tenant.isEmpty ? "—" : tenant)",
                         confirmTitle: language.text(deleting ? "删除" : "确认", deleting ? "Delete" : "Confirm"), style: deleting ? .critical : .warning)
    }
    private func perform(_ action: Action) {
        guard canWrite else { return }
        let interruptedModels = isLoadingModels
        cancelReads(); isBusy = true; errorText = nil
        switch action {
        case .add(let row): operationContext = "\(row.displayName) · \(tenantLabel(row.tenantId))\nModel ID: \(row.id)"
        case .toggle(let row, _), .delete(let row): operationContext = "\(row.displayName) · \(configTenant(row))\nModel ID: \(row.modelId)"
        case .batch: operationContext = language.text("全部 OCI AI 配置", "All OCI AI configurations")
        }
        notice = language.text("正在更新 AI 配置…", "Updating AI settings…")
        Task { @MainActor in
            var receipt: AiConfigItem?
            var batch: AiModelsBatchReceipt?
            var failure: AiModelsFailure?
            var saved = false
            do {
                switch action {
                case .add(let model): receipt = try await service.addConfig(tenantId: model.tenantId, model: model)
                case .toggle(let item, let enabled): receipt = try await service.toggleConfig(item, enabled: enabled)
                case .delete(let item): try await service.deleteConfig(id: item.id)
                case .batch(let enabled): batch = try await service.batchToggle(enabled: enabled)
                }
                saved = true
            } catch { failure = AiModelsFailure.sanitized(error) }
            guard active else { isBusy = false; return }
            reviewRevision = configRevision + 1
            notice = language.text("正在重新读取配置确认结果…", "Reading settings to confirm the result…")
            let readBack = await loadConfigs()
            guard active else { isBusy = false; return }
            if saved && readBack {
                let matches: Bool
                switch action {
                case .delete(let item): matches = !configs.contains(where: { $0.id == item.id })
                case .batch(let enabled): matches = configs.filter { $0.cloudType == 1 }.allSatisfy { $0.enabled == enabled }
                default:
                    if let expected = receipt { matches = configs.first(where: { $0.id == expected.id })?.matchesReceipt(expected) == true }
                    else { matches = false }
                }
                if !matches { failure = AiModelsFailure(reason: .saveMismatch, writeAttempted: true) }
            }
            requiresReview = failure?.writeAttempted == true || (saved && !readBack)
            if let failure = failure { errorText = describe(failure) }
            if requiresReview {
                notice = language.text("操作结果需要核对。请刷新配置并检查实际状态，确认后再继续。", "Review the operation result. Refresh settings and check the actual state before continuing.")
            } else if saved {
                if let batch = batch {
                    notice = language.text("已更新 \(batch.updatedCount) 条配置，并重新读取确认。", "Updated \(batch.updatedCount) configurations and confirmed the refreshed state.")
                } else { notice = language.text("配置已更新，并重新读取确认。", "Settings updated and confirmed by a fresh read.") }
            } else { notice = nil }
            if let receipt = receipt, let index = visibleConfigs.firstIndex(where: { $0.id == receipt.id }) {
                configPage.go(to: index / configPage.size)
            }
            isBusy = false
            if interruptedModels && !selectedTenantId.isEmpty { refreshModels() }
        }
    }
    private func describe(_ error: Error) -> String {
        switch AiModelsFailure.sanitized(error).reason {
        case .invalidInput: return language.text("模型或租户信息无效，请重新选择。", "Invalid model or tenant. Select it again.")
        case .invalidResponse: return language.text("服务器返回的 AI 配置格式不正确，请刷新后检查。", "The server returned an invalid AI configuration response. Refresh and review it.")
        case .requestFailed: return language.text("AI 配置请求未完成，请检查连接后刷新。", "The AI settings request did not complete. Check the connection and refresh.")
        case .alreadyConfigured: return language.text("该模型已经配置，包括其他租户或停用的配置。", "This model is already configured, including disabled configurations or other tenants.")
        case .configMissing: return language.text("该配置已不存在，请刷新列表。", "This configuration no longer exists. Refresh the list.")
        case .saveMismatch: return language.text("重新读取的配置与操作回执不一致，请检查实际状态。", "The refreshed settings differ from the operation receipt. Check the actual state.")
        }
    }
}
