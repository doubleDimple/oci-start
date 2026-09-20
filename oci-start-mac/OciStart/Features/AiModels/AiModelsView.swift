import SwiftUI
import AppKit

/// Native OCI AI page and Telegram model dialog share the same verified data flow.
struct AiModelsView: View {
    @EnvironmentObject private var navigation: NavigationState
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = AiModelsViewModel()
    @State private var guardID = UUID()

    var body: some View {
        AiModelsEditor(model: model, onBack: { navigation.select(.tenants) })
            .padding(AppTheme.pagePadding)
            .background(AppTheme.pageBg(appearance.isDarkEffective))
            .onAppear { navigation.setLeaveGuard(owner: guardID) { model.canLeave() }; model.start() }
            .onDisappear { model.stop(); navigation.removeLeaveGuard(owner: guardID) }
            .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in model.reload() }
    }
}

struct TelegramAiDialog: View {
    @ObservedObject var model: AiModelsViewModel
    let onClose: () -> Void
    @EnvironmentObject private var appearance: AppearanceController
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(language.text("Telegram AI 模型配置", "Telegram AI models"))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                AppButton(title: language.text("关闭", "Close"), systemImage: "xmark", kind: .secondary,
                          enabled: !model.isBusy && !model.requiresReview) { if model.canLeave() { onClose() } }
            }
            Text(language.text("选择支持 AI 的 OCI 租户与模型。右侧显示所有租户已配置的模型，包括停用的配置。",
                               "Choose an OCI tenant that supports AI. The right list includes configured models from every tenant, including disabled configurations."))
                .font(.system(size: AppTheme.secondarySize))
                .foregroundColor(AppTheme.textSecondary(appearance.isDarkEffective))
            AiModelsEditor(model: model)
        }
        .padding(24)
        .frame(width: min(1080, (NSScreen.main?.visibleFrame.width ?? 1200) - 80),
               height: min(720, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
        .foregroundColor(AppTheme.textPrimary(appearance.isDarkEffective))
        .background(AppTheme.pageBg(appearance.isDarkEffective))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

struct AiModelsEditor: View {
    @ObservedObject var model: AiModelsViewModel
    var onBack: (() -> Void)? = nil
    @EnvironmentObject private var appearance: AppearanceController
    @ObservedObject private var language = LanguageManager.shared
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            toolbar
            if let notice = model.notice {
                HStack(spacing: 12) {
                    if model.isBusy { ProgressView().scaleEffect(0.7).frame(width: 18, height: 18) }
                    VStack(alignment: .leading, spacing: 6) {
                        if !model.operationContext.isEmpty { Text(model.operationContext).fontWeight(.medium).lineLimit(2).help(model.operationContext) }
                        Text(notice).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: AppTheme.secondarySize))
                    Spacer(minLength: 0)
                    if model.requiresReview {
                        AppButton(title: language.text("刷新配置", "Refresh settings"), kind: .secondary,
                                  enabled: !model.isBusy && !model.isLoadingConfigs) { model.refreshConfigs() }
                        if model.telegram {
                            AppButton(title: language.text("已核对", "Reviewed"), kind: .primary,
                                      enabled: model.reviewReady) { model.acknowledgeReview() }
                        }
                    }
                }
                .padding(12)
                .background(AppTheme.hover(dark))
                .cornerRadius(8)
            }
            if let error = model.errorText { problem(error) }
            GeometryReader { geometry in
                Group {
                    if geometry.size.width >= 820 {
                        HStack(alignment: .top, spacing: 16) { availablePanel; configuredPanel }
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                availablePanel.frame(height: 490)
                                configuredPanel.frame(height: 520)
                            }
                        }
                    }
                }
            }
        }
        .font(.system(size: AppTheme.bodySize))
        .foregroundColor(AppTheme.textPrimary(dark))
    }

    private var toolbar: some View {
        SingleLineToolbar {
            if let onBack = onBack {
                PageToolbarIcon(title: language.text("返回", "Back"), systemImage: "chevron.left", disabled: model.isBusy) { onBack() }
            }
            Text(language.text("租户", "Tenant")).foregroundColor(AppTheme.textSecondary(dark))
            SelectMenu(options: model.sortedTenants.map { SelectOption(id: $0.id, title: model.tenantLabel($0.id)) },
                       selection: Binding(get: { model.selectedTenantId.isEmpty ? nil : model.selectedTenantId }, set: { model.onTenantChanged($0) }),
                       placeholder: language.text("选择支持 AI 的租户", "Select an AI-enabled tenant"),
                       width: 270, allowClear: true, searchable: true)
                .disabled(model.selectionLocked || model.isLoadingTenants || (model.telegram && model.tenantsError != nil))
            if model.isLoadingTenants { ProgressView().scaleEffect(0.7).frame(width: 20, height: 20) }
            if let error = model.tenantsError { PageErrorIndicator(message: error, retry: { model.reload() }) }
            Spacer(minLength: 0)
            AppButton(title: language.text("刷新", "Refresh"), systemImage: "arrow.clockwise", kind: .secondary,
                      isLoading: model.refreshing, enabled: !model.isBusy) { model.reload() }
        }
    }

    private var availablePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.text("可用 AI 模型", "Available AI models")).font(.system(size: 15, weight: .semibold))
                Spacer()
                PageToolbarIcon(title: language.text("刷新模型", "Refresh models"), systemImage: "arrow.clockwise",
                                disabled: model.selectionLocked || model.isLoadingModels || model.selectedTenantId.isEmpty) { model.refreshModels() }
            }.padding(16)
            if let error = model.modelsError { problem(error).padding(.horizontal, 16).padding(.bottom, 8) }
            Divider().background(AppTheme.border(dark))
            ScrollView {
                if model.pagedModels.isEmpty {
                    empty(model.selectedTenantId.isEmpty ? language.text("请先选择租户", "Choose a tenant") :
                          model.isLoadingModels ? language.text("正在读取模型…", "Loading models…") :
                          model.modelsError != nil ? language.text("模型读取失败", "Models could not be loaded") :
                          model.modelsLoaded ? language.text("暂无可用模型", "No available models") : language.text("尚未读取模型", "Models have not been loaded"))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.pagedModels) { row in availableRow(row); Divider().padding(.horizontal, 16) }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            PaginationBar(state: $model.modelPage, showsSizeSelector: false,
                          rangeTextOverride: model.modelsLoaded ? language.text("共 \(model.models.count) 个模型", "\(model.models.count) models") : "—",
                          disabled: model.isBusy || model.isLoadingModels)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.cardBg(dark)).cornerRadius(AppTheme.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.border(dark), lineWidth: 1))
    }

    private var configuredPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(language.text("已配置的模型", "Configured models")).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                    PageToolbarIcon(title: language.text("刷新配置", "Refresh settings"), systemImage: "arrow.clockwise",
                                    disabled: model.isBusy || model.isLoadingConfigs) { model.refreshConfigs() }
                }
                if !model.telegram {
                    HStack(spacing: 8) {
                        AppButton(title: language.text("全部启用", "Enable all"), kind: .secondary,
                                  enabled: model.canWrite && model.canEnableAll) { model.batchEnable(true) }
                        AppButton(title: language.text("全部禁用", "Disable all"), kind: .secondary,
                                  enabled: model.canWrite && model.canDisableAll) { model.batchEnable(false) }
                        Spacer(minLength: 0)
                    }
                    Toggle(language.text("仅显示当前租户配置", "Show selected tenant only"),
                           isOn: Binding(get: { model.linkTenantFilter }, set: { model.setTenantFilter($0) }))
                        .toggleStyle(SwitchToggleStyle()).disabled(model.isBusy)
                    Text(language.text("批量操作影响所有租户、所有页的 OCI 配置。", "Bulk actions affect OCI settings across all tenants and pages."))
                        .font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark))
                }
                if let error = model.configsError { problem(error) }
            }.padding(16)
            Divider().background(AppTheme.border(dark))
            ScrollView {
                if model.pagedConfigs.isEmpty {
                    empty(model.isLoadingConfigs ? language.text("正在读取配置…", "Loading settings…") :
                          model.configsError != nil ? language.text("配置读取失败", "Settings could not be loaded") :
                          !model.configsLoaded ? language.text("尚未读取配置", "Settings have not been loaded") :
                          model.linkTenantFilter && !model.selectedTenantId.isEmpty ? language.text("当前租户暂无配置", "No configurations for this tenant") : language.text("暂无配置", "No configurations"))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.pagedConfigs) { row in configuredRow(row); Divider().padding(.horizontal, 16) }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            PaginationBar(state: $model.configPage, showsSizeSelector: false,
                          rangeTextOverride: configCount, disabled: model.isBusy || model.isLoadingConfigs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.cardBg(dark)).cornerRadius(AppTheme.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.border(dark), lineWidth: 1))
    }
    private var configCount: String {
        guard model.configsLoaded else { return "—" }
        if model.linkTenantFilter && !model.selectedTenantId.isEmpty {
            return language.text("显示 \(model.visibleConfigs.count) / 共 \(model.configs.count) 条配置", "\(model.visibleConfigs.count) of \(model.configs.count) configurations")
        }
        return language.text("共 \(model.configs.count) 条配置", "\(model.configs.count) configurations")
    }
    private func availableRow(_ row: AiAvailableModel) -> some View {
        let configured = model.configuredModelIds.contains(row.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.displayName).font(.system(size: 14, weight: .medium)).lineLimit(1).help(row.id)
                Text([row.provider, row.modelName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark)).lineLimit(1)
                if model.telegram {
                    Text(row.id).font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark)).lineLimit(1).help(row.id)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            AppButton(title: configured ? language.text("已添加", "Added") : language.text("添加", "Add"),
                      kind: .secondary, enabled: !configured && model.canWrite && !model.isLoadingModels && model.modelsError == nil && model.tenantsError == nil) { model.addModel(row) }
        }.padding(16).help(row.description)
    }
    private func configuredRow(_ row: AiConfigItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.displayName).font(.system(size: 14, weight: .medium)).lineLimit(1).help(row.modelId)
                Text([model.configTenant(row), row.provider].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark)).lineLimit(1)
                if model.telegram {
                    Text(language.text("配置 ID: \(row.id)", "Config ID: \(row.id)"))
                        .font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark))
                    Text(row.modelId.isEmpty ? "—" : row.modelId).font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary(dark)).lineLimit(1).help(row.modelId)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(row.enabled == true ? language.text("启用", "Enabled") : row.enabled == false ? language.text("停用", "Disabled") : language.text("状态未知", "Unknown"))
                .font(.system(size: 12)).foregroundColor(row.enabled == true ? AppTheme.success : row.enabled == nil ? AppTheme.warning(dark) : AppTheme.textSecondary(dark))
            if model.telegram && row.enabled == nil {
                rowAction("play.circle", title: language.text("启用", "Enable"), enabled: model.canWrite && row.cloudType == 1) { model.toggle(row, enabled: true) }
                rowAction("pause.circle", title: language.text("停用", "Disable"), enabled: model.canWrite && row.cloudType == 1) { model.toggle(row, enabled: false) }
            } else {
                rowAction(row.enabled == true ? "pause.circle" : "play.circle", title: row.enabled == true ? language.text("停用", "Disable") : language.text("启用", "Enable"),
                          enabled: model.canWrite && row.cloudType == 1) { model.toggle(row) }
            }
            rowAction("trash", title: language.text("删除", "Delete"), enabled: model.canWrite, danger: true) { model.delete(row) }
        }.padding(16)
    }
    private func rowAction(_ symbol: String, title: String, enabled: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17))
                .foregroundColor(danger ? AppTheme.danger : AppTheme.textSecondary(dark))
                .frame(width: 30, height: 32).contentShape(Rectangle()).opacity(enabled ? 1 : 0.4)
        }.buttonStyle(PlainButtonStyle()).disabled(!enabled).help(title).accessibilityLabel(title)
    }
    private func empty(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundColor(AppTheme.textSecondary(dark))
            .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
    private func problem(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
            Text(message).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 13)).foregroundColor(AppTheme.danger)
    }
}
