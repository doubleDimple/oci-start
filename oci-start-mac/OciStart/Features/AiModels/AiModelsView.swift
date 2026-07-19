import SwiftUI

/// 原生 OCI AI 管理（对齐 Web `/system/ai/models`）。
struct AiModelsView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = AiModelsViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(
            title: "OCI AI 管理",
            subtitle: "可用模型与已配置模型",
            systemImage: "sparkles",
            toolbar: {
                HStack(spacing: 8) {
                    AppButton(title: "全部启用", kind: .secondary) { model.batchEnable(true) }
                    AppButton(title: "全部禁用", kind: .secondary) { model.batchEnable(false) }
                    AppButton(
                        title: "刷新",
                        systemImage: "arrow.clockwise",
                        kind: .secondary,
                        isLoading: model.isLoadingConfigs || model.isLoadingModels
                    ) { model.reload() }
                }
            },
            content: {
                VStack(spacing: 0) {
                    filterBar
                    if let err = model.errorText, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "f85149"))
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        availablePanel
                        configuredPanel
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .appLoading(model.isBusy)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            model.reload()
        }
    }

    private var filterBar: some View {
        FilterBar(
            leading: {
                HStack(spacing: 10) {
                    Text("租户")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.sidebarText(dark))
                    SelectMenu(
                        options: model.tenants.map { SelectOption(id: $0.id, title: $0.name) },
                        selection: Binding(
                            get: { model.selectedTenantId.isEmpty ? nil : model.selectedTenantId },
                            set: { model.onTenantChanged($0) }
                        ),
                        placeholder: model.isLoadingTenants ? "加载中…" : "选择支持 AI 的租户…",
                        width: 280,
                        allowClear: true,
                        searchable: true
                    )
                }
            },
            trailing: {
                Toggle(isOn: $model.linkTenantFilter) {
                    Text("仅显示当前租户配置")
                        .font(.system(size: 12))
                }
                .toggleStyle(SwitchToggleStyle(tint: AppTheme.sidebarActive))
            }
        )
    }

    private var availablePanel: some View {
        panelCard(title: "可用 AI 模型", icon: "cpu") {
            if model.selectedTenantId.isEmpty {
                EmptyStateView(icon: "hand.point.up", title: "请先选择租户", subtitle: "选择支持 AI 的租户后查看模型")
                    .frame(maxHeight: .infinity)
            } else if model.isLoadingModels && model.models.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.models.isEmpty {
                EmptyStateView(icon: "sparkles", title: "暂无可用模型", subtitle: "该租户下没有可列出的模型")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.models) { m in
                            modelRow(m)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var configuredPanel: some View {
        panelCard(title: "已配置的模型", icon: "gearshape") {
            if model.isLoadingConfigs && model.configs.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleConfigs.isEmpty {
                EmptyStateView(icon: "tray", title: "暂无配置", subtitle: "从左侧添加模型")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.visibleConfigs) { c in
                            configRow(c)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func modelRow(_ m: AiAvailableModel) -> some View {
        let added = model.configuredModelIds.contains(m.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name.isEmpty ? m.id : m.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                    .lineLimit(1)
                Text(m.provider.isEmpty ? "OCI" : m.provider)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
            Spacer()
            if added {
                Text("已添加")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "3fb950"))
            } else {
                AppButton(title: "添加", kind: .primary) { model.addModel(m) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.sidebarBg(dark)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1))
    }

    private func configRow(_ c: AiConfigItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.modelName.isEmpty ? c.modelId : c.modelName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("租户 \(c.tenantId.isEmpty ? "—" : c.tenantId)")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
            Spacer()
            StatusBadge(text: c.enabled ? "启用" : "禁用", tone: c.enabled ? .success : .neutral)
            AppButton(title: c.enabled ? "禁用" : "启用", kind: .secondary) { model.toggle(c) }
            AppButton(title: "删除", kind: .danger) { model.delete(c) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.sidebarBg(dark)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1))
    }

    private func panelCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.sidebarActive)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.sidebarHover(dark).opacity(0.55))
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.sidebarBg(dark)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1))
    }
}
