import SwiftUI

// MARK: - DNS form

struct EdgeOneDnsSheet: View {
    @ObservedObject var model: EdgeOneViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var isEdit: Bool { model.dnsForm?.isEditing == true }
    private var showPriority: Bool {
        (model.dnsForm?.type ?? "").uppercased() == "MX"
    }

    var body: some View {
        AppSheetChrome(
            title: isEdit ? "编辑 DNS 记录" : "添加 DNS 记录",
            systemImage: isEdit ? "pencil" : "plus.circle",
            width: 480,
            height: showPriority ? 480 : 440,
            onClose: { model.closeDnsForm() },
            footer: {
                HStack {
                    Spacer()
                    AppButton(title: "取消", kind: .secondary) { model.closeDnsForm() }
                    AppButton(
                        title: isEdit ? "保存" : "添加",
                        systemImage: "square.and.arrow.down",
                        kind: .primary,
                        isLoading: model.isSaving
                    ) {
                        model.saveDnsForm()
                    }
                }
            },
            content: {
                if model.dnsForm != nil {
                    VStack(alignment: .leading, spacing: 14) {
                        FormFieldRow(label: "类型", required: true) {
                            if isEdit {
                                AppTextField(
                                    text: .constant(model.dnsForm?.type ?? ""),
                                    placeholder: "类型"
                                )
                                .disabled(true)
                            } else {
                                SelectMenu(
                                    options: EdgeOneJSON.typeOptions,
                                    selection: Binding(
                                        get: { model.dnsForm?.type },
                                        set: { val in
                                            guard var f = model.dnsForm else { return }
                                            f.type = val ?? "A"
                                            model.dnsForm = f
                                        }
                                    ),
                                    placeholder: "选择类型",
                                    width: 200,
                                    allowClear: false,
                                    searchable: false
                                )
                            }
                        }

                        FormFieldRow(label: "记录名", required: true) {
                            AppTextField(
                                text: Binding(
                                    get: { model.dnsForm?.name ?? "" },
                                    set: { val in
                                        guard var f = model.dnsForm else { return }
                                        f.name = val
                                        model.dnsForm = f
                                    }
                                ),
                                placeholder: "@ / www / mail",
                                leadingSystemImage: "textformat"
                            )
                            .disabled(isEdit)
                        }

                        FormFieldRow(label: "记录值", required: true) {
                            AppTextField(
                                text: Binding(
                                    get: { model.dnsForm?.content ?? "" },
                                    set: { val in
                                        guard var f = model.dnsForm else { return }
                                        f.content = val
                                        model.dnsForm = f
                                    }
                                ),
                                placeholder: "IP 或域名",
                                leadingSystemImage: "link"
                            )
                        }

                        FormFieldRow(label: "TTL") {
                            SelectMenu(
                                options: EdgeOneJSON.ttlOptions,
                                selection: Binding(
                                    get: { "\(model.dnsForm?.ttl ?? 300)" },
                                    set: { val in
                                        guard var f = model.dnsForm else { return }
                                        f.ttl = Int(val ?? "300") ?? 300
                                        model.dnsForm = f
                                    }
                                ),
                                placeholder: "TTL",
                                width: 160,
                                allowClear: false,
                                searchable: false
                            )
                        }

                        if showPriority {
                            FormFieldRow(label: "优先级") {
                                AppTextField(
                                    text: Binding(
                                        get: { model.dnsForm?.priority ?? "" },
                                        set: { val in
                                            guard var f = model.dnsForm else { return }
                                            f.priority = val.filter { $0.isNumber }
                                            model.dnsForm = f
                                        }
                                    ),
                                    placeholder: "10",
                                    leadingSystemImage: "number"
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        )
        .environmentObject(appearance)
    }
}

// MARK: - Config

struct EdgeOneConfigSheet: View {
    @ObservedObject var model: EdgeOneViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        AppSheetChrome(
            title: "EdgeOne 密钥配置",
            systemImage: "key.fill",
            width: 460,
            height: 360,
            onClose: { model.closeConfig() },
            footer: {
                HStack {
                    AppButton(
                        title: "测试连接",
                        systemImage: "bolt.horizontal.circle",
                        kind: .secondary,
                        isLoading: model.isConfigSaving
                    ) {
                        model.testConfig()
                    }
                    Spacer()
                    AppButton(title: "取消", kind: .secondary) { model.closeConfig() }
                    AppButton(
                        title: "保存",
                        systemImage: "square.and.arrow.down",
                        kind: .primary,
                        isLoading: model.isConfigSaving
                    ) {
                        model.saveConfig()
                    }
                }
            },
            content: {
                if model.configForm != nil {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("启用 EdgeOne")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.configForm?.enabled ?? false },
                                set: { val in
                                    guard var f = model.configForm else { return }
                                    f.enabled = val
                                    model.configForm = f
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "00b9ff")))
                        }

                        FormFieldRow(label: "SecretId", required: true) {
                            AppTextField(
                                text: Binding(
                                    get: { model.configForm?.secretId ?? "" },
                                    set: { val in
                                        guard var f = model.configForm else { return }
                                        f.secretId = val
                                        model.configForm = f
                                    }
                                ),
                                placeholder: "腾讯云 SecretId",
                                secure: true,
                                leadingSystemImage: "person"
                            )
                        }
                        Text("访问管理 → API 密钥管理")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.sidebarText(dark))

                        FormFieldRow(label: "SecretKey", required: true) {
                            AppTextField(
                                text: Binding(
                                    get: { model.configForm?.secretKey ?? "" },
                                    set: { val in
                                        guard var f = model.configForm else { return }
                                        f.secretKey = val
                                        model.configForm = f
                                    }
                                ),
                                placeholder: "腾讯云 SecretKey",
                                secure: true,
                                leadingSystemImage: "key"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        )
        .environmentObject(appearance)
    }
}
