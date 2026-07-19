import SwiftUI

/// 原生 Token 配置（对齐 Web `/system/apiTokens`）。
/// UI 标准：`ModuleSettingsCard` + `EqualHeightCardRow`（同质量管理页）。
struct ApiTokensView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = ApiTokensViewModel()

    private var dark: Bool { appearance.isDarkEffective }
    private let cardMinHeight: CGFloat = 360

    var body: some View {
        PageScaffold(
            title: "Token 配置",
            subtitle: "Open API 访问令牌 · 生成 / 撤销 / 使用说明",
            systemImage: "key.fill",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let err = model.errorText, !err.isEmpty {
                            errorBanner(err)
                        }
                        VStack(spacing: 14) {
                            EqualHeightCardRow(minHeight: cardMinHeight) {
                                statusCard
                            } second: {
                                configCard
                            }
                            EqualHeightCardRow(minHeight: cardMinHeight) {
                                docsCard
                            } second: {
                                usageCard
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

    // MARK: - Status

    private var statusCard: some View {
        ModuleSettingsCard(
            title: "Token 状态",
            subtitle: model.status.enabled ? "已启用" : "未启用 / 已撤销",
            systemImage: "info.circle",
            accent: model.status.enabled ? Color(hex: "3fb950") : Color(hex: "adbac7"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            infoRow("名称", model.status.tokenName.isEmpty ? "—" : model.status.tokenName)
            infoRow("状态", model.status.hasToken ? (model.status.enabled ? "已生成 · 有效" : "已生成 · 已停用") : "未生成")
            if !model.status.expiresAt.isEmpty {
                infoRow("过期时间", model.status.expiresAt)
                let days = model.status.daysUntilExpiration
                infoRow(
                    "剩余天数",
                    model.status.isExpired ? "已过期" : "\(days) 天",
                    warn: days < 7 || model.status.isExpired
                )
            }
            infoRow("说明", model.status.description.isEmpty ? "—" : model.status.description)

            if model.status.hasToken, model.status.enabled, !model.displayToken.isEmpty {
                FormFieldRow(label: "当前 Token") {
                    HStack(spacing: 8) {
                        AppTextField(text: .constant(model.displayToken), placeholder: "—")
                            .disabled(true)
                        AppButton(title: "复制", systemImage: "doc.on.doc", kind: .secondary) {
                            model.copyToken()
                        }
                    }
                }
            }
        } footer: {
            if model.status.enabled {
                StatusBadge(text: "运行中", tone: .success)
            } else {
                StatusBadge(text: "未启用", tone: .neutral)
            }
        }
    }

    // MARK: - Config

    private var configCard: some View {
        ModuleSettingsCard(
            title: "Token 配置",
            subtitle: "生成或撤销 API 访问令牌",
            systemImage: "gearshape",
            accent: Color(hex: "4a9eff"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "Token 名称", required: true) {
                AppTextField(
                    text: $model.form.tokenName,
                    placeholder: "如：生产环境 API",
                    leadingSystemImage: "tag"
                )
            }
            FormFieldRow(label: "有效期") {
                SelectMenu(
                    options: model.expireOptions,
                    selection: Binding(
                        get: { "\(model.form.expirationDays)" },
                        set: { model.form.expirationDays = Int($0 ?? "30") ?? 30 }
                    ),
                    placeholder: "选择天数",
                    width: 140,
                    allowClear: false,
                    searchable: false
                )
            }
            FormFieldRow(label: "描述") {
                AppTextField(
                    text: $model.form.description,
                    placeholder: "可选说明"
                )
            }
            Text("生成新 Token 会使旧 Token 立即失效。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: "生成 Token",
                    systemImage: "key",
                    kind: .primary,
                    isLoading: model.savingKey == "generate"
                ) {
                    model.generate()
                }
                AppButton(
                    title: "撤销",
                    systemImage: "xmark.shield",
                    kind: .danger,
                    isLoading: model.savingKey == "revoke"
                ) {
                    model.revoke()
                }
            }
        }
    }

    // MARK: - Docs

    private var docsCard: some View {
        ModuleSettingsCard(
            title: "API 文档",
            subtitle: "Swagger / OpenAPI",
            systemImage: "book",
            accent: Color(hex: "9b59b6"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            Text("使用 Bearer Token 调用 Open API。可在浏览器打开 Swagger 或下载 OpenAPI JSON。")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                docLinkRow(title: "Swagger UI", path: "/swagger-ui/index.html", icon: "safari")
                docLinkRow(title: "OpenAPI JSON", path: "/v3/api-docs", icon: "curlybraces")
            }
            .padding(.top, 4)
        } footer: {
            AppButton(title: "打开 Swagger", systemImage: "arrow.up.right.square", kind: .secondary) {
                model.openURL("/swagger-ui/index.html")
            }
        }
    }

    // MARK: - Usage

    private var usageCard: some View {
        ModuleSettingsCard(
            title: "使用说明",
            subtitle: "请求头携带 Authorization",
            systemImage: "terminal",
            accent: Color(hex: "f0881a"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            Text("在 HTTP 请求头中加入：")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))

            Text(authHeaderSample)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(dark ? Color.black.opacity(0.25) : Color(hex: "f1f5f9"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border(dark).opacity(0.7), lineWidth: 1)
                )

            Text("示例路径：/open-api/v1/system/info")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
        } footer: {
            AppButton(title: "复制请求头", systemImage: "doc.on.doc", kind: .secondary) {
                model.copyAuthHeader()
            }
        }
    }

    private var authHeaderSample: String {
        let token = model.displayToken.isEmpty ? "{your_token}" : model.displayToken
        return "Authorization: Bearer \(token)"
    }

    private func docLinkRow(title: String, path: String, icon: String) -> some View {
        Button(action: { model.openURL(path) }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(Color(hex: "9b59b6"))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                Spacer()
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.sidebarText(dark))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.sidebarBg(dark).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border(dark).opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func infoRow(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: warn ? .semibold : .regular))
                .foregroundColor(
                    warn
                        ? Color(hex: "f0881a")
                        : (dark ? Color.white.opacity(0.9) : Color.primary)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
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
