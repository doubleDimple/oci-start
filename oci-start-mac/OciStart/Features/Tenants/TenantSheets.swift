import SwiftUI
import AppKit

/// All tenant modals / subpages (Web modal-overlay equivalents).
struct TenantSheetHost: View {
    let sheet: TenantSheet
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        Group {
            switch sheet {
            case .add:
                addSheet
            case .editName(let t):
                editFieldSheet(title: "编辑自定义名称", item: t, save: { model.saveEditName(t) })
            case .editCost(let t):
                editFieldSheet(title: "编辑账号成本", item: t, save: { model.saveEditCost(t) })
            case .accountDetail(let t):
                accountDetail(t)
            case .users(let t):
                usersSheet(t)
            case .traffic(let t):
                trafficSheet(t)
            case .audit(let t):
                auditSheet(t)
            case .email(let t):
                emailSheet(t)
            case .social(let t):
                socialSheet(t)
            case .quota(let t):
                quotaSheet(t)
            case .bootVolumes(let t):
                volumesSheet(t)
            case .accountCheck:
                accountCheckSheet
            case .exportAll:
                exportSheet(title: "导出租户", onExport: { model.doExportAll() })
            case .exportOne(let t):
                exportSheet(title: "导出 \(t.displayName)", onExport: { model.doExportOne(t) })
            case .importJSON:
                EmptyView()
            case .updateProgress(_, let lines):
                progressSheet(title: "更新租户信息", lines: lines)
            case .bootCreate(let t):
                bootCreateSheet(t)
            case .regionSub(let t):
                regionSubSheet(t)
            case .cost(let t):
                costSheet(t)
            case .trafficQuery:
                EmptyView()
            case .aiChat(let t):
                aiChatSheet(t)
            case .passwordResult(let title, let user, let pwd):
                passwordResult(title: title, user: user, pwd: pwd)
            case .securityRules(let t):
                securityRulesSheet(t)
            case .mysql(let t):
                mysqlSheet(t)
            }
        }
        .onDisappear {
            // 关闭 AI 页时断开 WS
            if case .aiChat = sheet { model.closeAIChat() }
        }
    }

    // MARK: - Chrome（对齐 Web `.modal-container`）

    private func chrome<Content: View, Footer: View>(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = 520,
        height: CGFloat = 480,
        /// 为 true 时用固定宽高，避免 sheet 被系统撑满窗口
        fixedSize: Bool = false,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppSheetChrome(
            title: title,
            systemImage: systemImage,
            width: width,
            height: height,
            fixedSize: fixedSize,
            onClose: { presentationMode.wrappedValue.dismiss() },
            footer: footer,
            content: content
        )
    }

    private var primaryText: Color { AppSheetSurface.primaryText(dark) }
    private var mutedText: Color { AppSheetSurface.mutedText(dark) }
    private var panelBg: Color { AppSheetSurface.panelBg(dark) }
    private var border: Color { AppSheetSurface.border(dark) }

    // MARK: - Add

    /// Web: `tenant_speed_add.ftl` — form-card 配置导入
    private var addSheet: some View {
        chrome(title: "API 配置导入", systemImage: "bolt.fill", width: 560, height: 640, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存", systemImage: "checkmark", kind: .primary) { model.submitAdd() }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    Text("粘贴配置文本可自动解析字段")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(primaryText)
                        .padding(.bottom, 2)
                        .overlay(Rectangle().fill(border).frame(height: 1), alignment: .bottom)

                    if let err = model.formError, !err.isEmpty {
                        errorBanner(err)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("配置文本")
                        AppTextEditor(text: $model.addConfigText, minHeight: 96, monospaced: true)
                            .onChange(of: model.addConfigText) { _ in model.parseAddConfig() }
                    }
                    field("UserName", text: $model.addUserName)
                    field("User (API user) OCID", text: $model.addTenantId)
                    field("Fingerprint", text: $model.addFingerprint)
                    field("Tenancy OCID", text: $model.addTenancy)
                }
                Group {
                    sectionLabel("Region")
                    SelectMenu(
                        options: TenantKnownRegions.oci,
                        selection: Binding(
                            get: { model.addRegion as String? },
                            set: { model.addRegion = $0 ?? "ap-singapore-1" }
                        ),
                        placeholder: "区域",
                        width: 280,
                        allowClear: false
                    )
                    sectionLabel("API 私钥 (PEM)")
                    keyFileRow
                }
            }
        }
    }

    /// Web: `editCustomNameModal` / 编辑成本
    private func editFieldSheet(title: String, item: TenantItem, save: @escaping () -> Void) -> some View {
        chrome(title: title, systemImage: "pencil", width: 400, height: 260, footer: {
            HStack(spacing: 10) {
                AppButton(title: "保存", kind: .primary, action: save)
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel(title.contains("成本") ? "账号成本" : "自定义名称")
                AppTextField(text: $model.editText, placeholder: title)
                hint(title.contains("成本") ? "用于统计账号费用，可填数字" : "最长 100 字符，便于区分同区域账号")
                if let err = model.formError {
                    Text(err).font(.system(size: 12)).foregroundColor(AppSheetSurface.accentRed(dark))
                }
                Text(item.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                    .padding(.top, 4)
            }
        }
    }

    /// Web: `accountDetailModal` — `.detail-item` 键值行
    private func accountDetail(_ t: TenantItem) -> some View {
        chrome(title: "账号详情", systemImage: "person.circle", width: 480, height: 360, footer: {
            AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                AppDetailRow(label: "名称", value: t.displayName)
                AppDetailRow(label: "类型", value: t.typeText)
                AppDetailRow(label: "区域", value: t.region.isEmpty ? "—" : t.region)
                AppDetailRow(
                    label: "邮箱",
                    value: t.emailAddress.isEmpty ? "—" : t.emailAddress,
                    isLast: t.registerDetail == nil
                )
                if let d = t.registerDetail {
                    AppDetailRow(label: "计划", value: d.planType.isEmpty ? "—" : d.planType)
                    AppDetailRow(label: "城市", value: d.city.isEmpty ? "—" : d.city)
                    AppDetailRow(label: "国家", value: d.country.isEmpty ? "—" : d.country)
                    AppDetailRow(
                        label: "注册邮箱",
                        value: d.emailAddress.isEmpty ? "—" : d.emailAddress,
                        isLast: true
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Users (Web `userManagementModal` 三 Tab + 表格)

    private func usersSheet(_ t: TenantItem) -> some View {
        chrome(title: "用户管理", width: 900, height: 600, footer: {
            AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // Web: .user-management-tabs
                AppSheetTabBar(
                    titles: ["用户", "通知邮箱", "MFA"],
                    selectedIndex: TenantUserTab.allCases.firstIndex(of: model.userTab) ?? 0,
                    onSelect: { idx in
                        model.switchUserTab(TenantUserTab.allCases[idx], tenant: t)
                    }
                )

                if model.userTab == .users {
                    usersTabContent(t)
                } else if model.userTab == .notifications {
                    notifyTabContent(t)
                } else {
                    mfaTabContent(t)
                }

                if model.showPasswordPolicy {
                    passwordPolicyPanel(t)
                }
            }
        }
    }

    private func usersTabContent(_ t: TenantItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Web: btn-success 添加 / btn-primary 刷新 / btn-password-policy 橙色
            HStack(spacing: 6) {
                AppButton(title: "添加用户", systemImage: "plus", kind: .primary) { model.showAddUser.toggle() }
                AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) { model.openUsers(t) }
                Button(action: { model.openPasswordPolicy(for: t) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill").font(.system(size: 11, weight: .semibold))
                        Text("密码策略").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundColor(.white)
                    .background(Color(hex: "f39c12"))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if model.showAddUser {
                formPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        field("用户名", text: $model.newUsername)
                        field("邮箱", text: $model.newEmail)
                        Toggle("使用邮箱作为用户名", isOn: $model.useEmailAsUsername)
                            .foregroundColor(primaryText)
                        if !model.groups.isEmpty {
                            sectionLabel("用户组")
                            SelectMenu(
                                options: model.groups.map { SelectOption(id: $0.id, title: $0.name) },
                                selection: Binding(get: { model.newGroupId.isEmpty ? nil : model.newGroupId }, set: { model.newGroupId = $0 ?? "" }),
                                placeholder: "选择用户组",
                                width: 240,
                                allowClear: true
                            )
                        }
                        HStack(spacing: 8) {
                            AppButton(title: "保存", kind: .primary) { model.createUser(for: t) }
                            AppButton(title: "取消", kind: .danger) { model.showAddUser = false }
                        }
                    }
                }
            }

            // Web table: 域 / 用户名 / 邮箱 / 状态 / 创建时间 / 最后登录 / 操作
            AppSheetTableBox {
                AppSheetTableHeader(columns: [
                    ("域", 90), ("用户名", 110), ("邮箱", nil), ("状态", 80),
                    ("创建时间", 120), ("最后登录", 120), ("操作", 150)
                ])
                if model.users.isEmpty {
                    Text("暂无用户或加载中…")
                        .font(.system(size: 13))
                        .foregroundColor(mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else {
                    ForEach(Array(model.users.enumerated()), id: \.element.id) { idx, u in
                        AppSheetTableRow(striped: idx % 2 == 1) {
                            HStack(spacing: 0) {
                                tableCell(u.domain.isEmpty ? "Default" : u.domain, width: 90)
                                tableCell(u.username, width: 110, bold: true)
                                tableCell(u.email.isEmpty ? "—" : u.email, width: nil)
                                StatusBadge.state(u.lifecycleState)
                                    .frame(width: 80, alignment: .leading)
                                    .padding(.horizontal, 10)
                                tableCell(u.timeCreated.isEmpty ? "—" : u.timeCreated, width: 120, muted: true)
                                tableCell(u.lastSuccessfulLoginTime.isEmpty ? "—" : u.lastSuccessfulLoginTime, width: 120, muted: true)
                                HStack(spacing: 4) {
                                    AppButton(title: "重置", kind: .secondary) { model.resetUserPassword(for: t, user: u) }
                                    AppButton(title: "删除", kind: .danger) { model.deleteUser(for: t, user: u) }
                                }
                                .frame(width: 150, alignment: .leading)
                                .padding(.horizontal, 6)
                            }
                        }
                    }
                }
            }
        }
    }

    private func notifyTabContent(_ t: TenantItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                AppButton(title: "添加邮箱", systemImage: "plus", kind: .primary) { model.showAddNotify.toggle() }
                AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) { Task { await model.loadNotifyEmails(t) } }
            }
            if model.showAddNotify {
                formPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        field("邮箱地址 *", text: $model.newNotifyEmail)
                        HStack(spacing: 8) {
                            AppButton(title: "添加", kind: .primary) { model.addNotifyEmail(t) }
                            AppButton(title: "取消", kind: .danger) { model.showAddNotify = false }
                        }
                    }
                }
            }
            AppSheetTableBox {
                AppSheetTableHeader(columns: [
                    ("#", 50), ("邮箱", nil), ("状态", 100), ("操作", 90)
                ])
                if model.notifyEmails.isEmpty {
                    Text("暂无通知邮箱")
                        .font(.system(size: 13))
                        .foregroundColor(mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else {
                    ForEach(Array(model.notifyEmails.enumerated()), id: \.offset) { idx, email in
                        AppSheetTableRow(striped: idx % 2 == 1) {
                            HStack(spacing: 0) {
                                tableCell("\(idx + 1)", width: 50, muted: true)
                                tableCell(email, width: nil)
                                StatusBadge(text: "有效", tone: .success)
                                    .frame(width: 100, alignment: .leading)
                                    .padding(.horizontal, 10)
                                AppButton(title: "移除", kind: .danger) { model.removeNotifyEmail(t, email: email) }
                                    .frame(width: 90, alignment: .leading)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                }
            }
            Text("共 \(model.notifyEmails.count) 个收件人")
                .font(.system(size: 12))
                .foregroundColor(mutedText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panelBg)
                .cornerRadius(4)
        }
    }

    private func mfaTabContent(_ t: TenantItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                AppButton(title: "重置 MFA", kind: .secondary) { model.resetMfa(t) }
                AppButton(title: "启用邮箱 MFA", kind: .primary) { model.setEmailMfa(t, enable: true) }
                AppButton(title: "关闭邮箱 MFA", kind: .danger) { model.setEmailMfa(t, enable: false) }
                AppButton(title: "刷新", kind: .secondary) { Task { await model.loadMfa(t) } }
            }
            // Web: #mfaStatusSection hover-bg panel
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppSheetSurface.accentBlue(dark))
                    Text("MFA 状态")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(primaryText)
                }
                Text(model.mfaStatusText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryText)
                StatusBadge(
                    text: model.mfaEmailEnabled ? "邮箱 MFA 开" : "邮箱 MFA 关",
                    tone: model.mfaEmailEnabled ? .success : .neutral
                )
                ForEach(model.mfaDetailLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(mutedText)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelBg)
            .cornerRadius(4)
        }
    }

    private func passwordPolicyPanel(_ t: TenantItem) -> some View {
        formPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("密码策略配置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(primaryText)
                ForEach(model.policyInfoLines, id: \.self) { line in
                    Text(line).font(.system(size: 12)).foregroundColor(mutedText)
                }
                Toggle("启用密码过期策略", isOn: $model.policyEnableExpiry)
                    .foregroundColor(primaryText)
                if model.policyEnableExpiry {
                    field("过期天数", text: $model.policyExpiryDays)
                    hint("0 = 永不过期，默认 120 天")
                }
                AppSheetInfoBox(
                    text: "说明",
                    lines: [
                        "策略作用于该租户下 OCI 用户",
                        "过期后用户需重置密码",
                        "天数为 0 表示永不过期"
                    ]
                )
                HStack(spacing: 10) {
                    AppButton(title: "保存", kind: .primary) { model.savePasswordPolicy(for: t) }
                    AppButton(title: "取消", kind: .secondary) { model.showPasswordPolicy = false }
                }
            }
        }
    }

    // MARK: - Traffic / Audit / Email / Social / Quota / Volumes（对齐 Web 弹层）

    /// Web: `trafficAlertModal`
    private func trafficSheet(_ t: TenantItem) -> some View {
        chrome(title: "流量预警", width: 480, height: 380, footer: {
            HStack(spacing: 10) {
                AppButton(title: "保存", kind: .primary) { model.saveTraffic(t) }
                AppButton(title: "取消", kind: .danger) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("启用流量统计", isOn: $model.trafficStats)
                        .foregroundColor(primaryText)
                    hint("开启后按月统计流量并触发预警")
                }
                VStack(alignment: .leading, spacing: 6) {
                    field("预警阈值 (GB) *", text: $model.trafficThreshold)
                    hint("每月流量达到该值时预警")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("超限自动关机", isOn: $model.trafficAutoShutdown)
                        .foregroundColor(primaryText)
                    hint("达到阈值后自动停止相关实例")
                }
            }
        }
    }

    /// Web: `auditLogModal` — 日期筛选 + 表格
    private func auditSheet(_ t: TenantItem) -> some View {
        chrome(title: "审计日志", systemImage: "doc.text", width: 900, height: 560, footer: {
            AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("开始：").font(.system(size: 12)).foregroundColor(mutedText)
                    AppTextField(text: $model.auditStart, placeholder: "yyyy-MM-dd")
                        .frame(width: 150)
                    Text("结束：").font(.system(size: 12)).foregroundColor(mutedText)
                    AppTextField(text: $model.auditEnd, placeholder: "yyyy-MM-dd")
                        .frame(width: 150)
                    AppButton(title: "查询", kind: .primary) { model.searchAudit(t) }
                }
                AppSheetTableBox {
                    AppSheetTableHeader(columns: [
                        ("#", 40), ("用户", 100), ("来源 IP", 110),
                        ("事件", nil), ("时间", 140), ("说明", 160)
                    ])
                    if model.auditLogs.isEmpty {
                        Text("暂无日志")
                            .font(.system(size: 13))
                            .foregroundColor(mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(28)
                    } else {
                        ForEach(Array(model.auditLogs.enumerated()), id: \.element.id) { idx, log in
                            AppSheetTableRow(striped: idx % 2 == 1) {
                                HStack(spacing: 0) {
                                    tableCell("\(idx + 1)", width: 40, muted: true)
                                    tableCell(log.principalName.isEmpty ? "—" : log.principalName, width: 100)
                                    tableCell(log.sourceIP.isEmpty ? "—" : log.sourceIP, width: 110, muted: true)
                                    tableCell(log.eventName, width: nil, bold: true)
                                    tableCell(log.eventTime.isEmpty ? "—" : log.eventTime, width: 140, muted: true)
                                    tableCell(log.message.isEmpty ? "—" : log.message, width: 160, muted: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Web: `emailServiceModal`
    private func emailSheet(_ t: TenantItem) -> some View {
        chrome(title: "启用邮箱服务", systemImage: "envelope", width: 500, height: 420, footer: {
            HStack(spacing: 10) {
                if model.emailEnabled || model.emailViewOnly {
                    AppButton(title: "修改", kind: .secondary) { model.emailViewOnly = false }
                }
                AppButton(title: "启用/保存", kind: .primary) { model.enableEmail(t) }
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                if !model.emailInfo.isEmpty {
                    Text(model.emailInfo)
                        .font(.system(size: 13))
                        .foregroundColor(primaryText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(panelBg)
                        .cornerRadius(4)
                }
                field("邮箱域名 *", text: $model.emailDomain)
                hint("示例：example.com，用于 OCI Email Delivery")
                AppSheetInfoBox(
                    text: "域名说明",
                    lines: [
                        "需完成域名验证后方可发送",
                        "启用后可在此配置测试收件地址",
                        "禁用将停止该租户邮箱投递"
                    ]
                )
                Divider().opacity(0.5)
                field("测试收件地址", text: $model.emailTestAddress)
                AppButton(title: "发送测试邮件", kind: .secondary) { model.testEmailService(t) }
                if model.emailEnabled {
                    AppButton(title: "禁用邮箱服务", kind: .danger) { model.disableEmail(t) }
                }
            }
        }
    }

    /// Web: `socialLoginModal` — 列表表格 + 编辑表单
    private func socialSheet(_ t: TenantItem) -> some View {
        chrome(title: "社媒配置", systemImage: "link", width: 800, height: 580, footer: {
            AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    AppButton(title: "添加社媒", systemImage: "plus", kind: .primary) { model.resetSocialDraft(t) }
                    AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                        model.openSocial(t)
                    }
                }

                AppSheetTableBox {
                    AppSheetTableHeader(columns: [
                        ("类型", 90), ("Client ID", nil), ("回调 URL", 180), ("状态", 80), ("操作", 160)
                    ])
                    if model.socialItems.isEmpty {
                        Text("暂无社媒绑定")
                            .font(.system(size: 13))
                            .foregroundColor(mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else {
                        ForEach(Array(model.socialItems.enumerated()), id: \.element.id) { idx, s in
                            AppSheetTableRow(striped: idx % 2 == 1) {
                                HStack(spacing: 0) {
                                    tableCell(s.socialTypeStr, width: 90, bold: true)
                                    tableCell(s.clientId.isEmpty ? "—" : s.clientId, width: nil)
                                    tableCell(s.redirectUrl.isEmpty ? "—" : s.redirectUrl, width: 180, muted: true)
                                    StatusBadge(text: s.socialStatus, tone: s.socialStatus == "active" ? .success : .neutral)
                                        .frame(width: 80, alignment: .leading)
                                        .padding(.horizontal, 8)
                                    HStack(spacing: 4) {
                                        AppButton(title: "编辑", kind: .secondary) { model.editSocial(t, social: s) }
                                        if s.socialStatus == "active" {
                                            AppButton(title: "禁用", kind: .danger) { model.toggleSocial(t, social: s, enable: false) }
                                        } else {
                                            AppButton(title: "启用", kind: .primary) { model.toggleSocial(t, social: s, enable: true) }
                                        }
                                    }
                                    .frame(width: 160, alignment: .leading)
                                    .padding(.horizontal, 4)
                                }
                            }
                        }
                    }
                }

                sectionTitle(model.socialDraft.id > 0 ? "编辑配置" : "新增配置")
                formPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        if !model.socialTypes.isEmpty {
                            sectionLabel("社媒类型 *")
                            SelectMenu(
                                options: model.socialTypes.map { SelectOption(id: $0, title: $0) },
                                selection: Binding(
                                    get: { model.socialDraft.socialTypeStr.isEmpty ? nil : model.socialDraft.socialTypeStr },
                                    set: { model.socialDraft.socialTypeStr = $0 ?? "" }
                                ),
                                placeholder: "类型",
                                width: 200,
                                allowClear: false
                            )
                        }
                        field("Client ID *", text: Binding(get: { model.socialDraft.clientId }, set: { model.socialDraft.clientId = $0 }))
                        field("Client Secret *", text: Binding(get: { model.socialDraft.clientSecret }, set: { model.socialDraft.clientSecret = $0 }))
                        field("第三方账号", text: Binding(get: { model.socialDraft.thirdLoginAddress }, set: { model.socialDraft.thirdLoginAddress = $0 }))
                        field("回调 URL", text: Binding(get: { model.socialDraft.redirectUrl }, set: { model.socialDraft.redirectUrl = $0 }))
                        hint("回调地址用于 OAuth 完成跳转，可从服务端生成")
                        HStack(spacing: 10) {
                            AppButton(title: "保存", kind: .primary) { model.saveSocial(t) }
                            AppButton(title: "取消", kind: .secondary) { model.resetSocialDraft(t) }
                        }
                    }
                }
            }
        }
    }

    /// Web: `quotaModal` — 图标标题 + 筛选条 + 结果区
    private func quotaSheet(_ t: TenantItem) -> some View {
        chrome(title: "账号配额", systemImage: "chart.bar.fill", width: 860, height: 600, footer: {
            HStack(spacing: 8) {
                AppButton(title: "上一页", kind: .secondary, enabled: model.quotaPage > 0) {
                    model.queryQuota(page: model.quotaPage - 1)
                }
                AppButton(title: "下一页", kind: .secondary, enabled: model.quotaHasNext) {
                    model.queryQuota(page: model.quotaPage + 1)
                }
                AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.quotaRegionLabel.isEmpty
                     ? "选择租户和服务后点击查询"
                     : "\(model.quotaRegionLabel) · 第 \(model.quotaPage + 1) 页 · \(model.quotaItems.count) 条")
                    .font(.system(size: 11))
                    .foregroundColor(mutedText)
                    .padding(.bottom, 12)

                // Filter bar (Web surface-2 strip)
                HStack(alignment: .bottom, spacing: 12) {
                    if !model.quotaRegions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("租户")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(mutedText)
                            SelectMenu(
                                options: model.quotaRegions.map { SelectOption(id: $0.id, title: $0.label) },
                                selection: Binding(get: { model.quotaTenantId }, set: { model.quotaTenantId = $0 ?? "" }),
                                placeholder: "选择租户…",
                                width: 220,
                                allowClear: false
                            )
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("服务类型")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(mutedText)
                        SelectMenu(
                            options: [
                                SelectOption(id: "compute", title: "计算 (Compute)"),
                                SelectOption(id: "block-storage", title: "块存储"),
                                SelectOption(id: "object-storage", title: "对象存储"),
                                SelectOption(id: "mysql", title: "MySQL HeatWave"),
                                SelectOption(id: "database", title: "Oracle Database"),
                                SelectOption(id: "autonomous-database", title: "自治数据库"),
                                SelectOption(id: "nosql", title: "NoSQL")
                            ],
                            selection: Binding(get: { model.quotaService }, set: { model.quotaService = $0 ?? "compute" }),
                            placeholder: "服务",
                            width: 200,
                            allowClear: false
                        )
                    }
                    SelectMenu(
                        options: [10, 20, 50].map { SelectOption(id: "\($0)", title: "\($0)/页") },
                        selection: Binding(
                            get: { "\(model.quotaPageSize)" },
                            set: {
                                if let v = Int($0 ?? "20") {
                                    model.quotaPageSize = v
                                    model.queryQuota(page: 0)
                                }
                            }
                        ),
                        placeholder: "每页",
                        width: 90,
                        allowClear: false
                    )
                    AppButton(title: "查询", systemImage: "magnifyingglass", kind: .primary) {
                        model.queryQuota(page: 0)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppSheetSurface.surface2(dark))
                .overlay(Rectangle().fill(border).frame(height: 1), alignment: .bottom)
                .padding(.bottom, 14)

                if !model.quotaError.isEmpty {
                    errorBanner(model.quotaError).padding(.bottom, 10)
                }

                if model.quotaItems.isEmpty && model.quotaError.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 36))
                            .foregroundColor(mutedText.opacity(0.35))
                        Text("选择租户和服务类型，点击查询")
                            .font(.system(size: 13))
                            .foregroundColor(mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    AppSheetTableBox {
                        AppSheetTableHeader(columns: [
                            ("资源", nil), ("类型", 90), ("可用", 70), ("已用", 70), ("限额", 70)
                        ])
                        ForEach(Array(model.quotaItems.enumerated()), id: \.element.id) { idx, row in
                            AppSheetTableRow(striped: idx % 2 == 1) {
                                HStack(spacing: 0) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(row.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(primaryText)
                                            .lineLimit(2)
                                        if !row.scope.isEmpty {
                                            Text(row.scope).font(.system(size: 10)).foregroundColor(mutedText)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    tableCell(row.instanceType, width: 90)
                                    tableCell(row.available, width: 70)
                                    tableCell(row.used, width: 70)
                                    tableCell(row.limit, width: 70)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Web: `bootVolumesModal` — 表格：实例 / 卷名 / 大小 / VPUs / 操作
    private func volumesSheet(_ t: TenantItem) -> some View {
        chrome(title: "引导卷管理", systemImage: "externaldrive", width: 720, height: 520, footer: {
            AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                AppSheetTableBox {
                    AppSheetTableHeader(columns: [
                        ("实例", 140), ("卷名称", nil), ("大小(GB)", 80), ("VPUs", 60), ("操作", 140)
                    ])
                    if model.volumes.isEmpty {
                        Text("暂无引导卷")
                            .font(.system(size: 13))
                            .foregroundColor(mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(28)
                    } else {
                        ForEach(Array(model.volumes.enumerated()), id: \.element.id) { idx, v in
                            AppSheetTableRow(striped: idx % 2 == 1) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 0) {
                                        tableCell(v.instanceName.isEmpty ? "—" : v.instanceName, width: 140)
                                        tableCell(v.displayName, width: nil, bold: true)
                                        tableCell("\(v.sizeInGBs)", width: 80)
                                        tableCell("\(v.vpusPerGB)", width: 60)
                                        HStack(spacing: 4) {
                                            AppButton(title: "编辑", kind: .secondary) { model.beginEditVolume(v) }
                                            AppButton(title: "删除", kind: .danger) { model.deleteVolume(for: t, volume: v) }
                                        }
                                        .frame(width: 140, alignment: .leading)
                                        .padding(.horizontal, 4)
                                    }
                                    if model.editingVolumeId == v.id {
                                        formPanel {
                                            VStack(alignment: .leading, spacing: 8) {
                                                field("卷名称", text: $model.editVolumeName)
                                                Text("VPUs: \(Int(model.editVolumeVpus)) (10–120)")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(primaryText)
                                                Slider(value: $model.editVolumeVpus, in: 10...120, step: 10)
                                                HStack(spacing: 8) {
                                                    AppButton(title: "保存", kind: .primary) { model.saveVolumeEdit(for: t) }
                                                    AppButton(title: "取消", kind: .secondary) { model.editingVolumeId = nil }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.bottom, 6)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Check / Export / Progress / Subpage

    private var accountCheckSheet: some View {
        chrome(title: "批量账号检测", width: 560, height: 520, footer: {
            AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: Double(model.checkPercent), total: 100)
                Text("\(model.checkPercent)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(mutedText)
                if let r = model.checkResult {
                    HStack(spacing: 12) {
                        stat("总计", "\(r.totalAccounts)")
                        stat("有效", "\(r.activeAccounts)")
                        stat("失效", "\(r.inactiveAccounts)")
                    }
                    if !r.inactiveAccountNames.isEmpty {
                        sectionTitle("失效账号列表")
                        ForEach(r.inactiveAccountNames, id: \.self) { name in
                            Text("· \(name)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "f85149"))
                        }
                    }
                }
                sectionTitle("日志")
                formPanel {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.checkLines.suffix(40)), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(primaryText.opacity(0.88))
                        }
                    }
                }
            }
        }
    }

    private func exportSheet(title: String, onExport: @escaping () -> Void) -> some View {
        chrome(title: title, width: 420, height: 280, footer: {
            HStack(spacing: 8) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "导出", kind: .primary, action: onExport)
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                formPanel {
                    hint("导出需邮箱验证码（与 Web 一致）")
                }
                AppButton(title: model.exportSent ? "重新发送验证码" : "发送验证码", kind: .secondary) {
                    model.sendExportCode()
                }
                field("验证码", text: $model.exportCode)
            }
        }
    }

    private func progressSheet(title: String, lines: [String]) -> some View {
        chrome(title: title, width: 520, height: 400, footer: {
            AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("处理中…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(mutedText)
                }
                formPanel {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(lines.suffix(50), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(primaryText.opacity(0.88))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Native subpages

    private func bootCreateSheet(_ t: TenantItem) -> some View {
        // 宽扁弹框，避免竖向撑满主窗口
        // Web: `add_boot.ftl` form-card
        chrome(title: "预开机配置", systemImage: "plus.circle", width: 760, height: 480, fixedSize: true, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存任务", kind: .primary) { model.submitBoot(t) }
            }
        }) {
            HStack(alignment: .top, spacing: 24) {
                // 左列：规格
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("选择区域 / 规格")
                    labeledSelect("架构", width: 200) {
                        SelectMenu(
                            options: [
                                SelectOption(id: "ARM", title: "ARM"),
                                SelectOption(id: "AMD", title: "AMD"),
                                SelectOption(id: "X86", title: "X86")
                            ],
                            selection: Binding(
                                get: { model.bootArchitecture },
                                set: {
                                    model.bootArchitecture = $0 ?? "ARM"
                                    Task {
                                        let tid = Int64(model.bootSelectedRegionTenantId) ?? t.id
                                        await model.loadBootImages(tenantId: tid)
                                    }
                                }
                            ),
                            placeholder: "架构", width: 200, allowClear: false
                        )
                    }
                    if !model.bootRegionOptions.isEmpty {
                        labeledSelect("区域租户", width: 280) {
                            SelectMenu(
                                options: model.bootRegionOptions.map { SelectOption(id: $0.id, title: $0.label) },
                                selection: Binding(
                                    get: { model.bootSelectedRegionTenantId },
                                    set: {
                                        model.bootSelectedRegionTenantId = $0 ?? "\(t.id)"
                                        Task {
                                            let tid = Int64(model.bootSelectedRegionTenantId) ?? t.id
                                            await model.loadBootImages(tenantId: tid)
                                        }
                                    }
                                ),
                                placeholder: "区域", width: 280, allowClear: false
                            )
                        }
                    }
                    HStack(spacing: 12) {
                        field("OCPU", text: $model.bootOcpu)
                        field("内存 (GB)", text: $model.bootMemory)
                        field("磁盘 (GB)", text: $model.bootDisk)
                    }
                    HStack(spacing: 12) {
                        field("循环间隔(秒)", text: $model.bootLoopTime)
                        field("实例数量", text: $model.bootCount)
                    }
                    field("时段 dayGap (如 0-8)", text: $model.bootDayGap)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 右列：镜像与密码
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("镜像与访问")
                    field("root 密码", text: $model.bootRootPassword)
                    labeledSelect("操作系统", width: 280) {
                        if model.bootOSList.isEmpty {
                            Text("加载镜像中或暂无镜像…")
                                .font(.system(size: 12))
                                .foregroundColor(mutedText)
                                .frame(height: AppInputStyle.height, alignment: .leading)
                        } else {
                            SelectMenu(
                                options: model.bootOSList.map { SelectOption(id: $0, title: $0) },
                                selection: Binding(
                                    get: { model.bootSelectedOS.isEmpty ? nil : model.bootSelectedOS },
                                    set: { if let v = $0 { model.applyBootOS(v) } }
                                ),
                                placeholder: "OS", width: 280, allowClear: false
                            )
                        }
                    }
                    labeledSelect("系统版本", width: 280) {
                        if model.bootVersions.isEmpty {
                            Text("—")
                                .font(.system(size: 12))
                                .foregroundColor(mutedText)
                                .frame(height: AppInputStyle.height, alignment: .leading)
                        } else {
                            SelectMenu(
                                options: model.bootVersions.map {
                                    SelectOption(id: $0.operatingSystemVersion, title: $0.operatingSystemVersion)
                                },
                                selection: Binding(
                                    get: { model.bootSelectedVersion.isEmpty ? nil : model.bootSelectedVersion },
                                    set: { if let v = $0 { model.applyBootVersion(v) } }
                                ),
                                placeholder: "版本", width: 280, allowClear: false
                            )
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionLabel("Image ID")
                        Text(model.bootImageId.isEmpty ? "—" : model.bootImageId)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(mutedText)
                            .lineLimit(2)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(AppInputStyle.fill(dark))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppTheme.border(dark).opacity(0.6), lineWidth: 1)
                            )
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func labeledSelect<Content: View>(_ title: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            content()
                .frame(width: width, alignment: .leading)
        }
    }

    /// Web: `securityRulesModal`（租户详情页）
    private func securityRulesSheet(_ t: TenantItem) -> some View {
        chrome(title: "安全规则配置", systemImage: "shield", width: 640, height: 520, footer: {
            AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                AppSheetTabBar(
                    titles: ["入站规则", "出站规则"],
                    selectedIndex: model.rulesTab == "egress" ? 1 : 0,
                    onSelect: { idx in
                        model.switchRulesTab(idx == 1 ? "egress" : "ingress", item: t)
                    }
                )
                HStack {
                    AppButton(title: "添加规则", systemImage: "plus", kind: .primary) {
                        model.showAddRule.toggle()
                    }
                    if model.rulesLoading {
                        ProgressView().scaleEffect(0.7)
                    }
                    Spacer()
                }
                if model.showAddRule {
                    formPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("协议")
                            SelectMenu(
                                options: [
                                    SelectOption(id: "all", title: "全部协议"),
                                    SelectOption(id: "tcp", title: "TCP"),
                                    SelectOption(id: "udp", title: "UDP"),
                                    SelectOption(id: "icmp", title: "ICMP")
                                ],
                                selection: Binding(
                                    get: { model.ruleProtocol },
                                    set: { model.ruleProtocol = $0 ?? "tcp" }
                                ),
                                placeholder: "协议", width: 160, allowClear: false
                            )
                            field("源地址 *", text: $model.ruleSource)
                            field("端口范围", text: $model.rulePorts)
                            hint("示例：80,443 或 80-443；ICMP 可留空")
                            HStack(spacing: 8) {
                                AppButton(title: "保存", kind: .primary) { model.saveSecurityRule(t) }
                                AppButton(title: "取消", kind: .danger) { model.showAddRule = false }
                            }
                        }
                    }
                }
                AppSheetTableBox {
                    AppSheetTableHeader(columns: [
                        ("#", 40), ("类型", 70), ("协议", 70), ("源", nil), ("端口", 90), ("操作", 70)
                    ])
                    if model.securityRules.isEmpty {
                        Text(model.rulesLoading ? "加载中…" : "暂无规则")
                            .font(.system(size: 13))
                            .foregroundColor(mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else {
                        ForEach(Array(model.securityRules.enumerated()), id: \.offset) { idx, rule in
                            AppSheetTableRow(striped: idx % 2 == 1) {
                                HStack(spacing: 0) {
                                    tableCell("\(idx + 1)", width: 40, muted: true)
                                    tableCell(rule.type.isEmpty ? model.rulesTab : rule.type, width: 70)
                                    tableCell(rule.protocolDisplay, width: 70)
                                    tableCell(rule.source.isEmpty ? "—" : rule.source, width: nil)
                                    tableCell(rule.portsDisplay, width: 90)
                                    AppButton(title: "删除", kind: .danger) {
                                        model.deleteSecurityRule(at: idx, item: t)
                                    }
                                    .frame(width: 70, alignment: .leading)
                                    .padding(.horizontal, 4)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Web: `mysqlManagementModal`
    private func mysqlSheet(_ t: TenantItem) -> some View {
        chrome(title: "数据库管理", systemImage: "cylinder", width: 720, height: 480, footer: {
            HStack(spacing: 8) {
                AppButton(title: "从云同步", kind: .secondary) { model.syncMysqlCloud(t) }
                AppButton(title: "刷新", kind: .secondary) { model.loadMysql(t) }
                AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                if model.mysqlLoading {
                    HStack { ProgressView(); Text("加载 MySQL 实例…").foregroundColor(mutedText) }
                }
                AppSheetTableBox {
                    AppSheetTableHeader(columns: [
                        ("名称", nil), ("版本", 80), ("状态", 80), ("连接", 160), ("规格", 90), ("存储", 70)
                    ])
                    if model.mysqlRows.isEmpty && !model.mysqlLoading {
                        Text("暂无数据库实例")
                            .font(.system(size: 13))
                            .foregroundColor(mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(28)
                    } else {
                        ForEach(Array(model.mysqlRows.enumerated()), id: \.element.id) { idx, row in
                            AppSheetTableRow(striped: idx % 2 == 1) {
                                HStack(spacing: 0) {
                                    tableCell(row.displayName.isEmpty ? "未命名" : row.displayName, width: nil, bold: true)
                                    tableCell(row.dbVersion.isEmpty ? "—" : row.dbVersion, width: 80)
                                    tableCell(row.dbStatus.isEmpty ? "—" : row.dbStatus, width: 80)
                                    tableCell(
                                        "\(row.dbPublicUrl.isEmpty ? "—" : row.dbPublicUrl)/\(row.dbPort.isEmpty ? "3306" : row.dbPort)",
                                        width: 160, muted: true
                                    )
                                    tableCell(row.shape.isEmpty ? "—" : row.shape, width: 90)
                                    tableCell(row.dataStorageSizeInGBs.isEmpty ? "—" : row.dataStorageSizeInGBs, width: 70)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Web: `region_sub.ftl` — 摘要 + 已订阅 / 未订阅
    private func regionSubSheet(_ t: TenantItem) -> some View {
        chrome(title: "区域订阅 — \(t.displayName)", systemImage: "globe", width: 680, height: 580, footer: {
            HStack(spacing: 8) {
                AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                    Task { await model.refreshRegionSub(t) }
                }
                AppButton(title: "订阅所选", kind: .primary) { model.subscribeSelected(t) }
                AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.regionSummaryText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panelBg)
                    .cornerRadius(4)

                sectionTitle("已订阅")
                if model.subscribedRegions.isEmpty {
                    emptyHint("无已订阅区域")
                } else {
                    AppSheetTableBox {
                        AppSheetTableHeader(columns: [("区域", nil), ("标记", 70), ("状态", 90)])
                        ForEach(Array(model.subscribedRegions.enumerated()), id: \.element.id) { idx, r in
                            AppSheetTableRow(striped: idx % 2 == 1) {
                                HStack(spacing: 0) {
                                    tableCell(r.regionName.isEmpty ? r.regionKey : r.regionName, width: nil, bold: true)
                                    Group {
                                        if r.isHomeRegion {
                                            StatusBadge(text: "Home", tone: .info)
                                        } else {
                                            Text("—").foregroundColor(mutedText).font(.system(size: 12))
                                        }
                                    }
                                    .frame(width: 70, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    StatusBadge(text: r.status.isEmpty ? "—" : r.status, tone: .success)
                                        .frame(width: 90, alignment: .leading)
                                        .padding(.horizontal, 10)
                                }
                            }
                        }
                    }
                }

                sectionTitle("未订阅（勾选后点订阅）")
                if model.unsubscribedRegions.isEmpty {
                    emptyHint("无未订阅区域")
                } else {
                    ForEach(model.unsubscribedRegions) { r in
                        Button(action: { model.toggleUnsubKey(r.key) }) {
                            HStack(spacing: 10) {
                                Image(systemName: model.selectedUnsubKeys.contains(r.key) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(AppTheme.sidebarActive)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.cnName.isEmpty ? r.name : r.cnName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(primaryText)
                                    Text("\(r.key) · \(r.name)")
                                        .font(.system(size: 11))
                                        .foregroundColor(mutedText)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(model.selectedUnsubKeys.contains(r.key) ? AppTheme.sidebarActive.opacity(0.08) : panelBg.opacity(0.5))
                            .overlay(Rectangle().fill(border.opacity(0.6)).frame(height: 1), alignment: .bottom)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    /// Web: `oci_cost.ftl` — 时间预设 + 查询
    private func costSheet(_ t: TenantItem) -> some View {
        chrome(title: "费用统计", systemImage: "dollarsign.circle", width: 600, height: 520, footer: {
            HStack(spacing: 10) {
                AppButton(title: "查询", kind: .primary) { model.queryCost(t) }
                AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("时间范围")
                HStack(spacing: 8) {
                    costPresetBtn("今天") {
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                        let s = f.string(from: Date())
                        model.costStart = s; model.costEnd = s
                    }
                    costPresetBtn("本月") {
                        let cal = Calendar.current
                        let now = Date()
                        let comps = cal.dateComponents([.year, .month], from: now)
                        let start = cal.date(from: comps) ?? now
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                        model.costStart = f.string(from: start)
                        model.costEnd = f.string(from: now)
                    }
                    costPresetBtn("自定义") {}
                }
                HStack(spacing: 10) {
                    field("开始日期", text: $model.costStart)
                    field("结束日期", text: $model.costEnd)
                }
                sectionTitle("查询结果")
                Text(model.costResultText.isEmpty ? "选择时间范围后点击查询" : model.costResultText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(primaryText)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .padding(14)
                    .background(AppSheetSurface.surface2(dark))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                    .cornerRadius(8)
            }
        }
    }

    private func costPresetBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(border, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func aiChatSheet(_ t: TenantItem) -> some View {
        chrome(title: "OCI AI — \(t.displayName)", width: 640, height: 580, footer: {
            AppButton(title: "关闭", kind: .secondary) {
                model.closeAIChat()
                presentationMode.wrappedValue.dismiss()
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(model.aiStatus)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(mutedText)
                    Spacer()
                    Toggle("上下文", isOn: $model.aiUseHistory)
                        .foregroundColor(primaryText)
                }
                if !model.aiModels.isEmpty {
                    SelectMenu(
                        options: model.aiModels.map {
                            SelectOption(id: $0.id, title: "\($0.displayName) (\($0.version.isEmpty ? "latest" : $0.version))")
                        },
                        selection: Binding(
                            get: { model.aiSelectedModelId.isEmpty ? nil : model.aiSelectedModelId },
                            set: {
                                model.aiSelectedModelId = $0 ?? ""
                                model.connectAIChat(tenantId: t.id)
                            }
                        ),
                        placeholder: "选择模型", width: 320, allowClear: false
                    )
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.aiLines) { line in
                            HStack(alignment: .top) {
                                if line.role == "user" { Spacer(minLength: 40) }
                                Text(line.text)
                                    .font(.system(size: 12))
                                    .foregroundColor(primaryText)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(line.role == "user"
                                                  ? AppTheme.sidebarActive.opacity(0.22)
                                                  : AppSheetSurface.panelBg(dark))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(AppTheme.border(dark).opacity(0.45), lineWidth: 1)
                                    )
                                if line.role != "user" { Spacer(minLength: 40) }
                            }
                        }
                    }
                }
                .frame(minHeight: 280)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppSheetSurface.rowHover(dark).opacity(0.5))
                )

                HStack(spacing: 8) {
                    AppTextField(text: $model.aiInput, placeholder: "输入消息…", onCommit: { model.sendAIMessage() })
                    AppButton(title: "发送", kind: .primary) { model.sendAIMessage() }
                }
            }
        }
    }

    private func passwordResult(title: String, user: String, pwd: String) -> some View {
        chrome(title: title, width: 420, height: 260, footer: {
            AppButton(title: "关闭", kind: .primary) { presentationMode.wrappedValue.dismiss() }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                formPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        kv("用户名", user)
                        kv("临时密码", pwd.isEmpty ? "（见服务端返回）" : pwd)
                    }
                }
                if !pwd.isEmpty {
                    AppButton(title: "复制密码", kind: .secondary) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pwd, forType: .string)
                    }
                }
            }
        }
    }

    // MARK: - Helpers（对齐 Web form-group / table cell）

    private var keyFileRow: some View {
        HStack(spacing: 10) {
            Text(model.addKeyFileURL?.lastPathComponent ?? "未选择私钥文件")
                .font(.system(size: 13))
                .foregroundColor(model.addKeyFileURL == nil ? mutedText : primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(dark ? Color(hex: "161820") : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(border, lineWidth: 1)
                )
            AppButton(title: "选择文件…", kind: .secondary) { model.pickKeyFile() }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            AppTextField(text: text, placeholder: title)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(mutedText)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(primaryText)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(mutedText)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(mutedText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 28)
            .background(panelBg)
            .cornerRadius(4)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(AppSheetSurface.accentRed(dark))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSheetSurface.accentRed(dark).opacity(0.12))
        .cornerRadius(4)
    }

    /// Web `.edit-rule-form` / form 面板
    private func formPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelBg)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(border.opacity(0.8), lineWidth: 1)
            )
            .cornerRadius(4)
    }

    private func listRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelBg.opacity(0.55))
            .overlay(
                Rectangle()
                    .fill(border.opacity(0.7))
                    .frame(height: 1),
                alignment: .bottom
            )
    }

    private func tableCell(_ text: String, width: CGFloat?, bold: Bool = false, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: bold ? .semibold : .regular))
            .foregroundColor(muted ? mutedText : primaryText)
            .lineLimit(2)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 10)
    }

    private func kv(_ k: String, _ v: String) -> some View {
        AppDetailRow(label: k, value: v)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(primaryText)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(panelBg)
        .cornerRadius(4)
    }
}


