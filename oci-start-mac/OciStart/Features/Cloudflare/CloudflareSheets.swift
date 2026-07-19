import SwiftUI

// MARK: - Add / Edit DNS

struct CloudflareDnsSheet: View {
    @ObservedObject var model: CloudflareViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var isEdit: Bool { model.dnsForm?.isEditing == true }

    var body: some View {
        AppSheetChrome(
            title: isEdit ? "编辑 DNS 记录" : "添加 DNS 记录",
            systemImage: isEdit ? "pencil" : "plus.circle",
            width: 480,
            height: isEdit ? 420 : 460,
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
                                    options: CloudflareJSON.typeOptions,
                                    selection: Binding(
                                        get: { model.dnsForm?.type },
                                        set: { val in
                                            guard var f = model.dnsForm else { return }
                                            f.type = val ?? "A"
                                            if !["A", "AAAA", "CNAME"].contains(f.type) {
                                                f.proxied = false
                                            }
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
                        if !isEdit {
                            Text("根域名使用 @")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.sidebarText(dark))
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
                                options: CloudflareJSON.ttlOptions,
                                selection: Binding(
                                    get: { "\(model.dnsForm?.ttl ?? 1)" },
                                    set: { val in
                                        guard var f = model.dnsForm else { return }
                                        f.ttl = Int(val ?? "1") ?? 1
                                        model.dnsForm = f
                                    }
                                ),
                                placeholder: "TTL",
                                width: 160,
                                allowClear: false,
                                searchable: false
                            )
                        }

                        if canProxy {
                            Toggle(isOn: Binding(
                                get: { model.dnsForm?.proxied ?? false },
                                set: { val in
                                    guard var f = model.dnsForm else { return }
                                    f.proxied = val
                                    model.dnsForm = f
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cloudflare 代理")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("橙云代理可隐藏源站 IP")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.sidebarText(dark))
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "f38020")))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        )
        .environmentObject(appearance)
    }

    private var canProxy: Bool {
        let t = (model.dnsForm?.type ?? "A").uppercased()
        return ["A", "AAAA", "CNAME"].contains(t)
    }
}

// MARK: - Secret config

struct CloudflareConfigSheet: View {
    @ObservedObject var model: CloudflareViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        AppSheetChrome(
            title: "Cloudflare 密钥配置",
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
                            Text("启用 Cloudflare")
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
                            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "f38020")))
                        }

                        FormFieldRow(label: "API Key", required: true) {
                            AppTextField(
                                text: Binding(
                                    get: { model.configForm?.apiToken ?? "" },
                                    set: { val in
                                        guard var f = model.configForm else { return }
                                        f.apiToken = val
                                        model.configForm = f
                                    }
                                ),
                                placeholder: "Global API Key",
                                secure: true,
                                leadingSystemImage: "key"
                            )
                        }
                        Text("My Profile → API Tokens → Global API Key")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.sidebarText(dark))

                        FormFieldRow(label: "账户邮箱", required: true) {
                            AppTextField(
                                text: Binding(
                                    get: { model.configForm?.email ?? "" },
                                    set: { val in
                                        guard var f = model.configForm else { return }
                                        f.email = val
                                        model.configForm = f
                                    }
                                ),
                                placeholder: "Cloudflare 账户邮箱",
                                leadingSystemImage: "envelope"
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
