import SwiftUI
import AppKit

/// 用户管理整页 — 对应 Web 用户管理 modal（三标签），从租户列表进入，非弹框。
struct TenantUserManageView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var tenant: TenantItem? { model.userManageParent }

    private var primaryText: Color { dark ? Color.white.opacity(0.9) : Color.primary }
    private var mutedText: Color { AppTheme.sidebarText(dark) }
    private var panelBg: Color { dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03) }
    private var border: Color { AppTheme.border(dark) }

    var body: some View {
        PageScaffold(
            title: "用户管理",
            subtitle: tenant.map { "\($0.displayName) · \($0.region.isEmpty ? "—" : $0.region)" },
            systemImage: "person.2",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    tabBar
                    tabContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "返回列表", systemImage: "chevron.left", kind: .secondary) {
                model.closeUserManage()
            }
            Divider().frame(height: 18)
            switch model.userTab {
            case .users:
                usersToolbar
            case .notifications:
                notifyToolbar
            case .mfa:
                mfaToolbar
            }
        }
    }

    private var usersToolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: model.showAddUser ? "收起" : "添加用户",
                      systemImage: model.showAddUser ? "chevron.up" : "plus",
                      kind: .primary) {
                model.showAddUser.toggle()
                if model.showAddUser { model.showPasswordPolicy = false }
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                guard let t = tenant else { return }
                Task { await model.loadUsersAndGroups(t) }
            }
            Button(action: {
                guard let t = tenant else { return }
                model.showAddUser = false
                model.openPasswordPolicy(for: t)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").font(.system(size: 11, weight: .semibold))
                    Text("密码策略").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundColor(.white)
                .background(Color(hex: "f39c12"))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            if model.userManageLoading {
                ProgressView().scaleEffect(0.7)
            }
        }
    }

    private var notifyToolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: model.showAddNotify ? "收起" : "添加邮箱",
                      systemImage: model.showAddNotify ? "chevron.up" : "plus",
                      kind: .primary) {
                model.showAddNotify.toggle()
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                guard let t = tenant else { return }
                Task { await model.loadNotifyEmails(t) }
            }
            if model.notifyEmailsLoading {
                ProgressView().scaleEffect(0.7)
            }
        }
    }

    private var mfaToolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "重置 MFA", kind: .secondary) {
                guard let t = tenant else { return }
                model.resetMfa(t)
            }
            AppButton(title: "启用邮箱 MFA", kind: .primary) {
                guard let t = tenant else { return }
                model.setEmailMfa(t, enable: true)
            }
            AppButton(title: "关闭邮箱 MFA", kind: .danger) {
                guard let t = tenant else { return }
                model.setEmailMfa(t, enable: false)
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                guard let t = tenant else { return }
                Task { await model.loadMfa(t) }
            }
            if model.mfaLoading {
                ProgressView().scaleEffect(0.7)
            }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TenantUserTab.allCases) { tab in
                tabItem(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .background(dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.3)), alignment: .bottom)
    }

    private func tabItem(_ tab: TenantUserTab) -> some View {
        let active = model.userTab == tab
        return Button(action: {
            model.userTab = tab
            model.showAddUser = false
            model.showAddNotify = false
            model.showPasswordPolicy = false
            guard let t = tenant else { return }
            switch tab {
            case .users: break
            case .notifications: Task { await model.loadNotifyEmails(t) }
            case .mfa: Task { await model.loadMfa(t) }
            }
        }) {
            VStack(spacing: 0) {
                Text(tab.title)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundColor(active ? AppTheme.sidebarActive : mutedText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Rectangle()
                    .fill(active ? AppTheme.sidebarActive : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch model.userTab {
        case .users:    usersTab
        case .notifications: notificationsTab
        case .mfa:      mfaTab
        }
    }

    // MARK: - 用户 tab

    private var usersTab: some View {
        VStack(spacing: 0) {
            if model.showAddUser {
                addUserForm
            }
            if model.showPasswordPolicy {
                passwordPolicyForm
            }
            usersTable
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addUserForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加用户").font(.system(size: 13, weight: .semibold)).foregroundColor(primaryText)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    formField("用户名", text: $model.newUsername)
                    formField("邮箱", text: $model.newEmail)
                    Toggle("使用邮箱作为用户名", isOn: $model.useEmailAsUsername)
                        .font(.system(size: 12))
                        .foregroundColor(primaryText)
                }
                .frame(width: 280)
                if !model.groups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("用户组").font(.system(size: 11, weight: .semibold)).foregroundColor(mutedText)
                        SelectMenu(
                            options: model.groups.map { SelectOption(id: $0.id, title: $0.name) },
                            selection: Binding(
                                get: { model.newGroupId.isEmpty ? nil : model.newGroupId },
                                set: { model.newGroupId = $0 ?? "" }
                            ),
                            placeholder: "选择用户组（可选）",
                            width: 220,
                            allowClear: true
                        )
                    }
                }
                Spacer()
            }
            HStack(spacing: 8) {
                AppButton(title: "保存", kind: .primary) {
                    guard let t = tenant else { return }
                    model.createUser(for: t)
                }
                AppButton(title: "取消", kind: .secondary) { model.showAddUser = false }
            }
        }
        .padding(16)
        .background(panelBg)
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.4)), alignment: .bottom)
    }

    private var passwordPolicyForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("密码策略配置").font(.system(size: 13, weight: .semibold)).foregroundColor(primaryText)
                Spacer()
                Button(action: { model.showPasswordPolicy = false }) {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(mutedText)
                }
                .buttonStyle(PlainButtonStyle())
            }
            ForEach(model.policyInfoLines, id: \.self) { line in
                Text(line).font(.system(size: 12)).foregroundColor(mutedText)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("启用密码过期策略", isOn: $model.policyEnableExpiry)
                        .font(.system(size: 12)).foregroundColor(primaryText)
                    if model.policyEnableExpiry {
                        formField("过期天数 (0=永不)", text: $model.policyExpiryDays, width: 160)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("说明").font(.system(size: 11, weight: .semibold)).foregroundColor(mutedText)
                    Text("· 策略作用于该租户下 OCI 用户").font(.system(size: 11)).foregroundColor(mutedText)
                    Text("· 过期后用户需重置密码").font(.system(size: 11)).foregroundColor(mutedText)
                    Text("· 天数为 0 表示永不过期").font(.system(size: 11)).foregroundColor(mutedText)
                }
            }
            HStack(spacing: 8) {
                AppButton(title: "保存", kind: .primary) {
                    guard let t = tenant else { return }
                    model.savePasswordPolicy(for: t)
                }
                AppButton(title: "取消", kind: .secondary) { model.showPasswordPolicy = false }
            }
        }
        .padding(16)
        .background(Color(hex: "f39c12").opacity(0.06))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(hex: "f39c12").opacity(0.3)), alignment: .bottom)
    }

    private var usersTable: some View {
        Group {
            if model.userManageLoading && model.users.isEmpty {
                loadingView("加载用户列表…")
            } else if model.users.isEmpty {
                EmptyStateView(
                    icon: "person.slash",
                    title: "暂无用户",
                    subtitle: "该租户下还没有 OCI 用户",
                    actionTitle: "添加用户",
                    action: { model.showAddUser = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let wDomain: CGFloat = 90
                    let wStatus: CGFloat = 88
                    let wCreated: CGFloat = 130
                    let wLogin: CGFloat = 130
                    let wAction: CGFloat = 130
                    let wUser: CGFloat = 120
                    let hPad: CGFloat = 16
                    let fixed = wDomain + wUser + wStatus + wCreated + wLogin + wAction + hPad * 2
                    let totalW = max(geo.size.width, fixed + 160)
                    let wEmail = max(120, totalW - fixed)

                    VStack(spacing: 0) {
                        usersHeader(wDomain: wDomain, wUser: wUser, wEmail: wEmail, wStatus: wStatus,
                                    wCreated: wCreated, wLogin: wLogin, wAction: wAction,
                                    width: totalW, hPad: hPad)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(model.users.enumerated()), id: \.element.id) { idx, u in
                                    userRow(index: idx, user: u,
                                            wDomain: wDomain, wUser: wUser, wEmail: wEmail,
                                            wStatus: wStatus, wCreated: wCreated, wLogin: wLogin,
                                            wAction: wAction, width: totalW, hPad: hPad)
                                }
                            }
                        }
                    }
                    .frame(width: totalW, height: geo.size.height, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func usersHeader(wDomain: CGFloat, wUser: CGFloat, wEmail: CGFloat, wStatus: CGFloat,
                              wCreated: CGFloat, wLogin: CGFloat, wAction: CGFloat,
                              width: CGFloat, hPad: CGFloat) -> some View {
        HStack(spacing: 0) {
            colHeader("域", wDomain)
            colHeader("用户名", wUser)
            colHeader("邮箱", wEmail)
            colHeader("状态", wStatus)
            colHeader("创建时间", wCreated)
            colHeader("最后登录", wLogin)
            colHeader("操作", wAction)
        }
        .padding(.horizontal, hPad).padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.5)), alignment: .bottom)
    }

    private func userRow(index: Int, user: TenantOracleUser,
                         wDomain: CGFloat, wUser: CGFloat, wEmail: CGFloat,
                         wStatus: CGFloat, wCreated: CGFloat, wLogin: CGFloat,
                         wAction: CGFloat, width: CGFloat, hPad: CGFloat) -> some View {
        HStack(spacing: 0) {
            cell(user.domain.isEmpty ? "Default" : user.domain, wDomain, muted: true)
            cell(user.username, wUser, bold: true)
            cell(user.email.isEmpty ? "—" : user.email, wEmail)
            StatusBadge.state(user.lifecycleState)
                .frame(width: wStatus, alignment: .leading)
            cell(user.timeCreated.isEmpty ? "—" : user.timeCreated, wCreated, muted: true)
            cell(user.lastSuccessfulLoginTime.isEmpty ? "—" : user.lastSuccessfulLoginTime, wLogin, muted: true)
            HStack(spacing: 4) {
                AppButton(title: "重置", kind: .secondary) {
                    guard let t = tenant else { return }
                    model.resetUserPassword(for: t, user: user)
                }
                AppButton(title: "删除", kind: .danger) {
                    guard let t = tenant else { return }
                    model.deleteUser(for: t, user: user)
                }
            }
            .frame(width: wAction, alignment: .leading)
        }
        .padding(.horizontal, hPad).padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(index % 2 == 1 ? AppTheme.sidebarHover(dark).opacity(0.18) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.3)), alignment: .bottom)
    }

    // MARK: - 通知邮箱 tab

    private var notificationsTab: some View {
        VStack(spacing: 0) {
            if model.showAddNotify {
                addNotifyForm
            }
            notifyTable
            notifyFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addNotifyForm: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("添加通知邮箱").font(.system(size: 13, weight: .semibold)).foregroundColor(primaryText)
                formField("邮箱地址 *", text: $model.newNotifyEmail, width: 300)
            }
            Spacer()
            VStack(alignment: .leading) {
                Spacer()
                HStack(spacing: 8) {
                    AppButton(title: "添加", kind: .primary) {
                        guard let t = tenant else { return }
                        model.addNotifyEmail(t)
                    }
                    AppButton(title: "取消", kind: .secondary) { model.showAddNotify = false }
                }
            }
        }
        .padding(16)
        .background(panelBg)
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.4)), alignment: .bottom)
    }

    private var notifyTable: some View {
        Group {
            if model.notifyEmailsLoading && model.notifyEmails.isEmpty {
                loadingView("加载通知邮箱…")
            } else if model.notifyEmails.isEmpty {
                EmptyStateView(
                    icon: "envelope.badge.slash",
                    title: "暂无通知邮箱",
                    subtitle: "添加收件人后，系统事件通知将发送至这些邮箱",
                    actionTitle: "添加邮箱",
                    action: { model.showAddNotify = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let wNo: CGFloat = 60
                    let wStatus: CGFloat = 80
                    let wAction: CGFloat = 80
                    let hPad: CGFloat = 16
                    let fixed = wNo + wStatus + wAction + hPad * 2
                    let totalW = max(geo.size.width, fixed + 200)
                    let wEmail = max(200, totalW - fixed)

                    VStack(spacing: 0) {
                        notifyHeader(wNo: wNo, wEmail: wEmail, wStatus: wStatus, wAction: wAction, width: totalW, hPad: hPad)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(model.notifyEmails.enumerated()), id: \.offset) { idx, email in
                                    notifyRow(index: idx, email: email, wNo: wNo, wEmail: wEmail, wStatus: wStatus, wAction: wAction, width: totalW, hPad: hPad)
                                }
                            }
                        }
                    }
                    .frame(width: totalW, height: geo.size.height, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func notifyHeader(wNo: CGFloat, wEmail: CGFloat, wStatus: CGFloat, wAction: CGFloat, width: CGFloat, hPad: CGFloat) -> some View {
        HStack(spacing: 0) {
            colHeader("#", wNo)
            colHeader("邮箱地址", wEmail)
            colHeader("状态", wStatus)
            colHeader("操作", wAction)
        }
        .padding(.horizontal, hPad).padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.sidebarHover(dark).opacity(0.65))
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.5)), alignment: .bottom)
    }

    private func notifyRow(index: Int, email: String, wNo: CGFloat, wEmail: CGFloat, wStatus: CGFloat, wAction: CGFloat, width: CGFloat, hPad: CGFloat) -> some View {
        HStack(spacing: 0) {
            cell("\(index + 1)", wNo, muted: true)
            cell(email, wEmail, bold: true)
            StatusBadge(text: "有效", tone: .success)
                .frame(width: wStatus, alignment: .leading)
            AppButton(title: "移除", kind: .danger) {
                guard let t = tenant else { return }
                model.removeNotifyEmail(t, email: email)
            }
            .frame(width: wAction, alignment: .leading)
        }
        .padding(.horizontal, hPad).padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(index % 2 == 1 ? AppTheme.sidebarHover(dark).opacity(0.18) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.3)), alignment: .bottom)
    }

    private var notifyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundColor(AppTheme.sidebarActive)
            Text("共 \(model.notifyEmails.count) ���收件人，系统通知将发送至全部邮箱")
                .font(.system(size: 12)).foregroundColor(mutedText)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(AppTheme.sidebarActive.opacity(0.06))
        .overlay(Rectangle().frame(height: 1).foregroundColor(border.opacity(0.3)), alignment: .top)
    }

    // MARK: - MFA tab

    private var mfaTab: some View {
        Group {
            if model.mfaLoading {
                loadingView("加载 MFA 状态…")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        mfaStatusCard
                        mfaDetailCard
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var mfaStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(AppTheme.sidebarActive)
                Text("MFA 状态").font(.system(size: 13, weight: .semibold)).foregroundColor(primaryText)
            }
            HStack(spacing: 12) {
                Text(model.mfaStatusText)
                    .font(.system(size: 13))
                    .foregroundColor(primaryText)
                StatusBadge(
                    text: model.mfaEmailEnabled ? "邮箱 MFA 开" : "邮箱 MFA 关",
                    tone: model.mfaEmailEnabled ? .success : .neutral
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(border.opacity(0.4), lineWidth: 1))
    }

    private var mfaDetailCard: some View {
        Group {
            if !model.mfaDetailLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("详细信息").font(.system(size: 12, weight: .semibold)).foregroundColor(mutedText)
                    ForEach(model.mfaDetailLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(mutedText)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panelBg)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border.opacity(0.4), lineWidth: 1))
            }
        }
    }

    // MARK: - Helpers

    private func loadingView(_ text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
            Text(text).font(.system(size: 12)).foregroundColor(mutedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func colHeader(_ title: String, _ w: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(mutedText)
            .frame(width: w, alignment: .leading)
    }

    private func cell(_ text: String, _ w: CGFloat, muted: Bool = false, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: bold ? .semibold : .regular))
            .foregroundColor(muted ? mutedText : primaryText)
            .lineLimit(1)
            .frame(width: w, alignment: .leading)
    }

    private func formField(_ label: String, text: Binding<String>, width: CGFloat = 240) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(mutedText)
            AppTextField(text: text, placeholder: label).frame(width: width)
        }
    }
}
