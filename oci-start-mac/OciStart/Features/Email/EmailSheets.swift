import SwiftUI

/// Email modals: compose / add contact / record detail.
struct EmailSheetHost: View {
    let sheet: EmailSheet
    @ObservedObject var model: EmailViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.presentationMode) private var presentationMode

    private var dark: Bool { appearance.isDarkEffective }
    private var primaryText: Color { AppSheetSurface.primaryText(dark) }
    private var mutedText: Color { AppSheetSurface.mutedText(dark) }

    var body: some View {
        switch sheet {
        case .compose:
            composeSheet
        case .addContact:
            addContactSheet
        case .recordDetail:
            detailSheet
        }
    }

    // MARK: - Chrome

    private func chrome<Content: View, Footer: View>(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = 520,
        height: CGFloat = 480,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppSheetChrome(
            title: title,
            systemImage: systemImage,
            width: width,
            height: height,
            fixedSize: true,
            onClose: { presentationMode.wrappedValue.dismiss() },
            footer: footer,
            content: content
        )
    }

    private func formErrorLine() -> some View {
        Group {
            if let err = model.formError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(AppSheetSurface.accentRed(dark))
            }
        }
    }

    // MARK: - Compose

    private var composeSheet: some View {
        chrome(title: "编写邮件", systemImage: "square.and.pencil", width: 560, height: 620, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "发送", systemImage: "paperplane.fill", kind: .primary, isLoading: model.formBusy) {
                    model.submitSend()
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                FormFieldRow(label: "主题", required: true) {
                    AppTextField(text: $model.composeTitle, placeholder: "邮件主题")
                }
                FormFieldRow(label: "内容", required: true) {
                    TextEditor(text: $model.composeContent)
                        .font(.system(size: 13))
                        .frame(minHeight: 120, maxHeight: 160)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: AppInputStyle.radius)
                                .fill(AppInputStyle.fill(dark))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppInputStyle.radius)
                                .stroke(AppInputStyle.border(dark), lineWidth: 1)
                        )
                }
                FormFieldRow(label: "发件租户", required: true) {
                    SelectMenu(
                        options: model.composeConfigOptions,
                        selection: Binding(
                            get: { model.composeConfigId > 0 ? "\(model.composeConfigId)" : nil },
                            set: { model.composeConfigId = Int64($0 ?? "") ?? 0 }
                        ),
                        placeholder: "选择发件邮箱…",
                        width: 360,
                        allowClear: false
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("收件人")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.sidebarText(dark))
                        Spacer()
                        AppButton(title: "全选", kind: .secondary) { model.selectAllComposeRecipients() }
                        AppButton(title: "清空", kind: .secondary) { model.clearComposeRecipients() }
                        Text("已选 \(model.composeSelectedIds.count) 人")
                            .font(.system(size: 11))
                            .foregroundColor(mutedText)
                    }
                    if model.composeContacts.isEmpty {
                        Text("暂无收件人，请先添加联系人")
                            .font(.system(size: 12))
                            .foregroundColor(mutedText)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(model.composeContacts) { c in
                                    recipientRow(c)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                        .background(AppSheetSurface.surface2(dark))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppSheetSurface.border(dark), lineWidth: 1)
                        )
                    }
                }
                formErrorLine()
            }
        }
    }

    private func recipientRow(_ c: EmailContactItem) -> some View {
        let on = model.composeSelectedIds.contains(c.id)
        return Button(action: { model.toggleComposeRecipient(c.id) }) {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundColor(on ? AppTheme.sidebarActive : mutedText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name.isEmpty ? "—" : c.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(primaryText)
                    Text(c.email)
                        .font(.system(size: 11))
                        .foregroundColor(mutedText)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Add contact

    private var addContactSheet: some View {
        chrome(title: "添加收件人", systemImage: "person.badge.plus", width: 420, height: 280, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy) {
                    model.submitAddContact()
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                FormFieldRow(label: "姓名", required: true) {
                    AppTextField(text: $model.newContactName, placeholder: "收件人姓名")
                }
                FormFieldRow(label: "邮箱地址", required: true) {
                    AppTextField(text: $model.newContactEmail, placeholder: "name@example.com")
                }
                formErrorLine()
            }
        }
    }

    // MARK: - Detail

    private var detailSheet: some View {
        chrome(title: detailTitle, systemImage: "envelope.open", width: 560, height: 520, footer: {
            HStack {
                Spacer()
                AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                if let r = model.detailRecord {
                    detailInfo(r)
                }
                Text("收件明细")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryText)
                if model.detailLoading && model.detailRecipients.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else if model.detailRecipients.isEmpty {
                    EmptyStateView(icon: "person.2", title: "无收件记录", subtitle: "该邮件暂无收件明细")
                        .frame(minHeight: 120)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.detailRecipients) { row in
                            HStack {
                                Text(row.receiveEmailAddress.isEmpty ? "—" : row.receiveEmailAddress)
                                    .font(.system(size: 13))
                                    .foregroundColor(primaryText)
                                Spacer()
                                StatusBadge(text: row.stateLabel, tone: row.stateTone)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            Divider().opacity(0.35)
                        }
                    }
                    .background(AppSheetSurface.surface2(dark))
                    .cornerRadius(8)
                }
                if model.detailPage.totalElements > 0 {
                    PaginationBar(state: $model.detailPage) {
                        model.onDetailPageChange()
                    }
                }
            }
        }
    }

    private var detailTitle: String {
        if let t = model.detailRecord?.subjectText, !t.isEmpty { return t }
        return "邮件详情"
    }

    private func detailInfo(_ r: EmailBodyItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            infoLine("发送时间", r.createTime.isEmpty ? "—" : r.createTime)
            infoLine("发件人", r.senderEmail.isEmpty ? "—" : r.senderEmail)
            infoLine("租户", r.tenantText)
            Text("内容")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(mutedText)
            Text(r.content.isEmpty ? "（无内容）" : r.content)
                .font(.system(size: 13))
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppSheetSurface.surface2(dark))
                .cornerRadius(8)
        }
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(label)：")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(mutedText)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(primaryText)
            Spacer()
        }
    }
}
