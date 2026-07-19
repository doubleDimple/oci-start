import SwiftUI

/// 原生 IP 质量管理（对齐 Web `/system/ipSettings` · `ip_settings.ftl`）。
///
/// **Mac 原生 UI 基准页**：后续设置/配置类页面布局与模块卡片样式以此为准。
/// 规范见 `tasks/macos-ui-standard.md`；组件见 `ModuleSettingsCard` / `EqualHeightCardRow`。
struct IpQualityView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = IpQualityViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    private let cardMinHeight: CGFloat = 380

    var body: some View {
        PageScaffold(
            title: "质量管理",
            subtitle: "IP 质量检测开关 · 三网 VPS SSH 探测节点",
            systemImage: "shield",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let err = model.errorText, !err.isEmpty {
                            errorBanner(err)
                        }
                        VStack(spacing: 14) {
                            EqualHeightCardRow(minHeight: cardMinHeight) {
                                ipCheckCard
                            } second: {
                                vpsCard(.telecom)
                            }
                            EqualHeightCardRow(minHeight: cardMinHeight) {
                                vpsCard(.unicom)
                            } second: {
                                vpsCard(.mobile)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.isLoading)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reload() }
        }
        .environmentObject(appearance)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        AppButton(
            title: "刷新",
            systemImage: "arrow.clockwise",
            kind: .secondary,
            isLoading: model.isLoading
        ) {
            Task { await model.reload() }
        }
    }

    // MARK: - IP check card

    private var ipCheckCard: some View {
        ModuleSettingsCard(
            title: "IP 质量检测",
            subtitle: "定时检测实例公网 IP 质量",
            systemImage: "network",
            accent: Color(hex: "4a9eff"),
            enabled: $model.ipCheckEnabled,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "检测间隔") {
                SelectMenu(
                    options: model.intervalOptions,
                    selection: Binding(
                        get: { "\(model.checkInterval)" },
                        set: { model.checkInterval = Int($0 ?? "1") ?? 1 }
                    ),
                    placeholder: "选择间隔",
                    width: 160,
                    allowClear: false,
                    searchable: false
                )
            }
            Text("按设定小时周期执行 IP 质量检测任务")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
        } footer: {
            AppButton(
                title: "保存配置",
                systemImage: "square.and.arrow.down",
                kind: .primary,
                isLoading: model.savingKey == "ipCheck"
            ) {
                model.saveIpCheck()
            }
        }
    }

    // MARK: - VPS card

    private func vpsCard(_ carrier: IpCarrier) -> some View {
        ModuleSettingsCard(
            title: carrier.title,
            subtitle: carrier.subtitle,
            systemImage: carrier.systemImage,
            accent: AppTheme.sidebarActive,
            enabled: Binding(
                get: { model.binding(for: carrier).enabled },
                set: { newVal in
                    var v = model.binding(for: carrier)
                    v.enabled = newVal
                    model.update(carrier, v)
                }
            ),
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "服务器地址") {
                AppTextField(
                    text: Binding(
                        get: { model.binding(for: carrier).serverIp },
                        set: { newVal in
                            var v = model.binding(for: carrier)
                            v.serverIp = newVal
                            model.update(carrier, v)
                        }
                    ),
                    placeholder: "IP 或域名",
                    leadingSystemImage: "server.rack"
                )
            }
            HStack(spacing: 10) {
                FormFieldRow(label: "用户名") {
                    AppTextField(
                        text: Binding(
                            get: { model.binding(for: carrier).username },
                            set: { newVal in
                                var v = model.binding(for: carrier)
                                v.username = newVal
                                model.update(carrier, v)
                            }
                        ),
                        placeholder: "root",
                        leadingSystemImage: "person"
                    )
                }
                FormFieldRow(label: "SSH 端口") {
                    AppTextField(
                        text: Binding(
                            get: { "\(model.binding(for: carrier).sshPort)" },
                            set: { newVal in
                                var v = model.binding(for: carrier)
                                let digits = newVal.filter { $0.isNumber }
                                let port = Int(digits) ?? 0
                                v.sshPort = min(max(port == 0 && digits.isEmpty ? 22 : port, 0), 65535)
                                if v.sshPort == 0 { v.sshPort = 22 }
                                model.update(carrier, v)
                            }
                        ),
                        placeholder: "22",
                        leadingSystemImage: "number"
                    )
                }
            }
            FormFieldRow(label: "SSH 密码") {
                AppTextField(
                    text: Binding(
                        get: { model.binding(for: carrier).password },
                        set: { newVal in
                            var v = model.binding(for: carrier)
                            v.password = newVal
                            model.update(carrier, v)
                        }
                    ),
                    placeholder: "SSH 密码",
                    secure: true,
                    leadingSystemImage: "key"
                )
            }
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: "测试连接",
                    systemImage: "bolt.horizontal.circle",
                    kind: .secondary,
                    isLoading: model.savingKey == "test-\(carrier.rawValue)"
                ) {
                    model.testVPS(carrier)
                }
                AppButton(
                    title: "保存",
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == carrier.rawValue
                ) {
                    model.saveVPS(carrier)
                }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f85149"))
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reload() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }
}
