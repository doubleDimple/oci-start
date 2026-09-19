import SwiftUI

/// Native counterpart of settings/ApiTokensView.vue: overview and full-page generation editor.
struct ApiTokensView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @ObservedObject private var language = LanguageManager.shared
    @StateObject private var model = ApiTokensViewModel()
    private var dark: Bool { appearance.isDarkEffective }
    private func t(_ zh: String, _ en: String) -> String { language.text(zh, en) }

    var body: some View {
        PageScaffold(title: model.editing ? t("生成 Token", "Generate token") : t("Token 配置", "API token"),
                     subtitle: "", systemImage: "key", layout: .card,
                     toolbar: { toolbar }, content: {
            VStack(spacing: 0) {
                Rectangle().fill(AppTheme.border(dark)).frame(height: 1)
                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.requiresReview ? "exclamationmark.triangle" : "checkmark.circle")
                        Text(notice).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 14)).foregroundColor(model.requiresReview ? AppTheme.warning(dark) : AppTheme.textSecondary(dark))
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.hover(dark))
                }
                if model.requiresReview { review }
                ScrollView {
                    if model.editing { editor.padding(24) }
                    else { overview.padding(24) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.isLoading && model.status == nil)
            }
        }, footer: { footer })
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in Task { await model.reload() } }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            AppButton(title: t("返回上一页", "Go back"), systemImage: "arrow.left", kind: .secondary,
                      enabled: !model.busy && !model.requiresReview) { model.back() }
            if !model.editing { Text(statusText).font(.system(size: 14)).foregroundColor(AppTheme.textSecondary(dark)) }
            Spacer(minLength: 8)
            if let error = model.errorText { PageErrorIndicator(message: error) { Task { await model.reload() } } }
            PageToolbarIcon(title: t("刷新", "Refresh"), systemImage: "arrow.clockwise",
                            disabled: model.isLoading || model.busy) { Task { await model.reload() } }
            if model.editing {
                AppButton(title: t("取消", "Cancel"), kind: .secondary, enabled: !model.busy && !model.requiresReview) { model.back() }
            } else {
                AppButton(title: t("撤销", "Revoke"), kind: .danger,
                          enabled: model.canMutate && (model.status?.hasToken == true || model.status?.enabled == true)) { model.revoke() }
                AppButton(title: model.status?.hasToken == true ? t("替换 Token", "Replace token") : t("生成 Token", "Generate token"),
                          systemImage: "key", kind: .primary, enabled: model.canMutate) { model.openEditor() }
            }
        }
    }

    private var statusText: String {
        guard let state = model.status else { return t("尚未加载", "Not loaded") }
        if !state.hasToken { return t("未生成", "Not generated") }
        if !state.enabled { return t("已停用", "Disabled") }
        if model.expired == true { return t("已过期", "Expired") }
        if model.expired == nil { return t("有效期未确认", "Expiry unverified") }
        return t("有效", "Active")
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 32) {
                detail(t("名称", "Name"), model.status?.tokenName)
                detail(t("有效期", "Validity"), model.status.map { t("\($0.expirationDays) 天", "\($0.expirationDays) days") })
            }
            HStack(alignment: .top, spacing: 32) {
                detail(t("创建时间", "Created"), model.status?.createdAt?.replacingOccurrences(of: "T", with: " "))
                VStack(alignment: .leading, spacing: 5) {
                    detail(t("过期时间", "Expires"), model.status?.expiresAt?.replacingOccurrences(of: "T", with: " "))
                    if let zone = model.status?.serverTimeZone, !zone.isEmpty {
                        Text(zone).font(.system(size: 12)).foregroundColor(AppTheme.textMuted(dark))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            detail(t("描述", "Description"), model.status?.description)
            Rectangle().fill(AppTheme.border(dark)).frame(height: 1)
            HStack {
                Text(t("Token 密钥", "Token secret")).font(.system(size: 16, weight: .semibold))
                Spacer()
                AppButton(title: model.displayToken.isEmpty ? t("查看", "Reveal") : t("隐藏", "Hide"),
                          systemImage: model.displayToken.isEmpty ? "eye" : "eye.slash", kind: .secondary,
                          isLoading: model.materialLoading, enabled: !model.displayToken.isEmpty || model.canReveal) {
                    if model.displayToken.isEmpty { model.reveal() } else { model.hideMaterial() }
                }
            }
            if model.displayToken.isEmpty {
                Text("•••• •••• •••• ••••").font(.system(size: 20, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted(dark)).padding(.vertical, 12)
            } else {
                HStack(spacing: 10) {
                    Text(model.displayToken).font(.system(size: 14, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    AppButton(title: t("复制", "Copy"), systemImage: "doc.on.doc", kind: .secondary) { model.copyToken() }
                }.padding(16).background(AppTheme.inputBg(dark)).cornerRadius(12)
            }
        }
        .foregroundColor(AppTheme.textPrimary(dark))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func detail(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(AppTheme.textSecondary(dark))
                .frame(width: 100, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "—").font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 15).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .bottom)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 22) {
            if model.staleEditor {
                HStack {
                    Text(t("配置版本已变化，请核对后使用最新版本。", "Configuration changed. Review before using the latest revision."))
                    AppButton(title: t("使用最新版本", "Use latest"), kind: .secondary,
                              enabled: !model.isLoading && model.errorText == nil && !model.busy) { model.useLatest() }
                }
            }
            FormFieldRow(label: t("Token 名称", "Token name"), required: true) {
                AppTextField(text: $model.form.tokenName, placeholder: t("例如：生产环境 API", "For example: production API"))
            }
            FormFieldRow(label: t("有效期", "Validity")) {
                SelectMenu(options: model.expireOptions, selection: Binding(
                    get: { "\(model.form.expirationDays)" },
                    set: { model.form.expirationDays = Int($0 ?? "") ?? 30 }),
                    placeholder: t("选择天数", "Select days"), width: 180, allowClear: false, searchable: false)
            }
            FormFieldRow(label: t("描述", "Description")) {
                TextEditor(text: $model.form.description).font(.system(size: 14))
                    .frame(height: 130).padding(10).background(AppTheme.inputBg(dark))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border(dark), lineWidth: 1))
                Text("\(model.form.description.utf16.count) / 1000").font(.system(size: 12)).foregroundColor(AppTheme.textMuted(dark))
            }
        }
        .disabled(model.busy || model.requiresReview)
        .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var review: some View {
        HStack(spacing: 12) {
            Toggle(t("已核对服务器结果", "I have reviewed the server result"), isOn: $model.reviewChecked)
                .toggleStyle(CheckboxToggleStyle()).disabled(!model.reviewReady || model.busy)
            Spacer()
            AppButton(title: t("完成核对", "Finish review"), kind: .secondary,
                      enabled: model.reviewChecked && model.reviewReady && !model.busy) { model.acknowledgeReview() }
        }.padding(16)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.editing {
                Text(model.busy ? t("正在等待服务器回执…", "Waiting for the server…") : "")
                    .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
                Spacer()
                AppButton(title: t("继续", "Continue"), systemImage: "arrow.right", kind: .primary,
                          isLoading: model.busy, enabled: model.canMutate && model.form.valid && !model.staleEditor) { model.generate() }
            } else {
                Group {
                    if let date = model.lastUpdated {
                        Text(t("最近读取 ", "Last read ") + DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium))
                    } else { Text(t("尚未加载", "Not loaded")) }
                }.font(.system(size: 12)).foregroundColor(AppTheme.textMuted(dark))
                Spacer(minLength: 8)
                Button("Swagger") { model.openURL("/swagger-ui/index.html") }
                Button("OpenAPI JSON") { model.openURL("/v3/api-docs") }
                Button(t("复制请求头格式", "Copy header format")) { model.copyAuthHeader() }
            }
        }.buttonStyle(PlainButtonStyle()).padding(.horizontal, 20).frame(height: 64)
            .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .top)
    }
}
