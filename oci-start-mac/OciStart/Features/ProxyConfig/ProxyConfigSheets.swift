import SwiftUI

/// Add / edit proxy modal — left config / right tenant binding (align `vpn_proxy.ftl`).
struct ProxyConfigSheet: View {
    @ObservedObject var model: ProxyConfigViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.presentationMode) private var presentationMode

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        AppSheetChrome(
            title: (model.activeForm?.isEditing == true) ? "编辑代理" : "新增代理",
            systemImage: "arrow.left.arrow.right",
            width: 760,
            height: 520,
            onClose: { model.closeForm() },
            footer: {
                HStack {
                    Spacer()
                    AppButton(title: "取消", kind: .secondary) {
                        model.closeForm()
                    }
                    AppButton(
                        title: "保存",
                        systemImage: "square.and.arrow.down",
                        kind: .primary,
                        isLoading: model.isSaving
                    ) {
                        model.saveForm()
                    }
                }
            },
            content: {
                if let form = model.activeForm {
                    HStack(alignment: .top, spacing: 16) {
                        leftPane(form)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                        rightPane(form)
                            .frame(width: 280, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        )
        .environmentObject(appearance)
    }

    // MARK: - Left

    private func leftPane(_ form: ProxyFormState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader(
                icon: "server.rack",
                title: "代理参数",
                desc: "类型、地址、认证与可用状态"
            )
            FormFieldRow(label: "自定义名称") {
                AppTextField(
                    text: Binding(
                        get: { model.activeForm?.customName ?? "" },
                        set: { val in
                            guard var f = model.activeForm else { return }
                            f.customName = val
                            model.activeForm = f
                        }
                    ),
                    placeholder: "可选，仅展示",
                    leadingSystemImage: "tag"
                )
            }
            FormFieldRow(label: "代理类型", required: true) {
                SelectMenu(
                    options: model.typeOptions,
                    selection: Binding(
                        get: { model.activeForm?.proxyType },
                        set: { val in
                            guard var f = model.activeForm else { return }
                            f.proxyType = val ?? "HTTP"
                            model.activeForm = f
                        }
                    ),
                    placeholder: "选择类型",
                    width: 180,
                    allowClear: false,
                    searchable: false
                )
            }
            HStack(spacing: 10) {
                FormFieldRow(label: "代理地址", required: true) {
                    AppTextField(
                        text: Binding(
                            get: { model.activeForm?.proxyHost ?? "" },
                            set: { val in
                                guard var f = model.activeForm else { return }
                                f.proxyHost = val
                                model.activeForm = f
                            }
                        ),
                        placeholder: "192.168.1.1 / 127.0.0.1",
                        leadingSystemImage: "globe"
                    )
                }
                FormFieldRow(label: "端口", required: true) {
                    AppTextField(
                        text: Binding(
                            get: { model.activeForm?.proxyPort ?? "" },
                            set: { val in
                                guard var f = model.activeForm else { return }
                                f.proxyPort = val.filter { $0.isNumber }
                                model.activeForm = f
                            }
                        ),
                        placeholder: "8080",
                        leadingSystemImage: "number"
                    )
                }
            }
            HStack(spacing: 10) {
                FormFieldRow(label: "用户名") {
                    AppTextField(
                        text: Binding(
                            get: { model.activeForm?.proxyUsername ?? "" },
                            set: { val in
                                guard var f = model.activeForm else { return }
                                f.proxyUsername = val
                                model.activeForm = f
                            }
                        ),
                        placeholder: "可选",
                        leadingSystemImage: "person"
                    )
                }
                FormFieldRow(label: "密码") {
                    AppTextField(
                        text: Binding(
                            get: { model.activeForm?.proxyPassword ?? "" },
                            set: { val in
                                guard var f = model.activeForm else { return }
                                f.proxyPassword = val
                                model.activeForm = f
                            }
                        ),
                        placeholder: "可选",
                        secure: true,
                        leadingSystemImage: "key"
                    )
                }
            }
            HStack(spacing: 10) {
                FormFieldRow(label: "状态", required: true) {
                    SelectMenu(
                        options: model.statusOptions,
                        selection: Binding(
                            get: { "\(model.activeForm?.availableStatus ?? 1)" },
                            set: { val in
                                guard var f = model.activeForm else { return }
                                f.availableStatus = Int(val ?? "1") ?? 1
                                model.activeForm = f
                            }
                        ),
                        placeholder: "状态",
                        width: 120,
                        allowClear: false,
                        searchable: false
                    )
                }
                FormFieldRow(label: "强制代理", required: true) {
                    SelectMenu(
                        options: model.forceOptions,
                        selection: Binding(
                            get: { "\(model.activeForm?.forceProxy ?? 0)" },
                            set: { val in
                                guard var f = model.activeForm else { return }
                                f.forceProxy = (val == "1") ? 1 : 0
                                model.activeForm = f
                            }
                        ),
                        placeholder: "强制",
                        width: 140,
                        allowClear: false,
                        searchable: false
                    )
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 11))
                    .foregroundColor(
                        (model.activeForm?.forceProxy == 1)
                            ? Color(hex: "e67e22")
                            : Color(hex: "1abc9c")
                    )
                Text(
                    (model.activeForm?.forceProxy == 1)
                        ? "已开启强制：代理不通时拒绝向云厂商发起请求"
                        : "非强制：代理不通时可回退直连"
                )
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppSheetSurface.surface2(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppSheetSurface.border(dark), lineWidth: 1)
        )
    }

    // MARK: - Right

    private func rightPane(_ form: ProxyFormState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            paneHeader(
                icon: "link",
                title: "绑定租户",
                desc: "可多选；空 = 全局共享代理池"
            )

            HStack(spacing: 8) {
                Image(systemName: form.tenantIds.isEmpty ? "globe" : "person.2")
                    .foregroundColor(AppTheme.sidebarActive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前绑定")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.sidebarText(dark))
                    Text(model.selectedTenantLabel())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.sidebarActive.opacity(0.12))
            )

            AppTextField(
                text: Binding(
                    get: { model.tenantSearch },
                    set: { val in
                        model.tenantSearch = val
                        model.onTenantSearchChange()
                    }
                ),
                placeholder: "搜索租户",
                leadingSystemImage: "magnifyingglass"
            )

            ScrollView {
                LazyVStack(spacing: 4) {
                    tenantRow(
                        id: nil,
                        title: "全局共享",
                        meta: "fallback pool",
                        selected: form.tenantIds.isEmpty
                    )
                    if model.pagedTenants.isEmpty {
                        Text("无匹配租户")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.sidebarText(dark))
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(model.pagedTenants) { t in
                            tenantRow(
                                id: Int64(t.id),
                                title: t.name,
                                meta: t.region.isEmpty ? "#\(t.id)" : t.region,
                                selected: Int64(t.id).map { form.tenantIds.contains($0) } ?? false
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: { model.changeTenantPage(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(model.tenantPageIndex <= 0)
                Spacer()
                Text("\(model.tenantPageIndex + 1) / \(model.tenantTotalPages) · 共 \(model.filteredTenants.count) 个")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
                Spacer()
                Button(action: { model.changeTenantPage(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(model.tenantPageIndex >= model.tenantTotalPages - 1)
            }
            .foregroundColor(dark ? Color.white.opacity(0.85) : Color.primary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppSheetSurface.surface2(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppSheetSurface.border(dark), lineWidth: 1)
        )
    }

    private func tenantRow(id: Int64?, title: String, meta: String, selected: Bool) -> some View {
        Button(action: { model.selectTenant(id) }) {
            HStack(spacing: 8) {
                // 全局用圆点；租户用方框多选
                if id == nil {
                    Circle()
                        .strokeBorder(selected ? AppTheme.sidebarActive : AppTheme.border(dark), lineWidth: 1.5)
                        .background(Circle().fill(selected ? AppTheme.sidebarActive : Color.clear))
                        .frame(width: 12, height: 12)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(selected ? AppTheme.sidebarActive : AppTheme.border(dark), lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(selected ? AppTheme.sidebarActive : Color.clear)
                        )
                        .frame(width: 12, height: 12)
                        .overlay(
                            Group {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        )
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                        .lineLimit(1)
                    Text(meta)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.sidebarText(dark))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? AppTheme.sidebarActive.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func paneHeader(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(AppTheme.sidebarActive)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
        }
    }
}
