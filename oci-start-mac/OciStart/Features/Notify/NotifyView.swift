import SwiftUI

/// 原生通知管理（对齐 Web `/system/notifySettings`）。
/// Section navigation and a single settings editor follow the current Vue page.
struct NotifyView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = NotifyViewModel()
    @StateObject private var aiModel = AiModelsViewModel(pageSize: 7, telegram: true)
    @EnvironmentObject private var navigation: NavigationState
    @ObservedObject private var language = LanguageManager.shared
    @State private var active = "task"
    @State private var guardID = UUID()
    @State private var showAI = false

    private var dark: Bool { appearance.isDarkEffective }

    /// 通道卡片统一高度
    private let channelMinHeight: CGFloat = 400
    /// 定时任务全宽卡（内容横向展开，高度可略低）
    private let taskMinHeight: CGFloat = 340

    var body: some View {
        NativeSettingsWorkspace(sections: [
            ("task", language.text("定时任务", "Scheduled tasks")), ("telegram", "Telegram"),
            ("proxy", language.text("Telegram 代理", "Telegram proxy")), ("bark", "Bark"),
            ("dingTalk", language.text("钉钉", "DingTalk")), ("feishu", language.text("飞书", "Feishu"))
        ], selection: Binding(get: { active }, set: { next in
            guard next != active, model.canLeave() else { return }
            active = next
            if model.hasUnsavedChanges || model.requiresReview { Task { await model.reload() } }
        }), disabled: model.savingKey != nil || model.isLoading, toolbar: {
            HStack {
                if let notice = model.notice { Text(notice).font(.system(size: AppTheme.secondarySize)) }
                Spacer()
                AppButton(title: language.text("刷新配置", "Refresh settings"), systemImage: "arrow.clockwise", kind: .secondary,
                          isLoading: model.isLoading, enabled: model.savingKey == nil) { model.requestReload() }
            }
        }, content: {
            VStack(alignment: .leading, spacing: 12) {
                if let error = model.errorText { errorBanner(error) }
                Group {
                    switch active {
                    case "telegram": telegramCard
                    case "proxy": proxyCard
                    case "bark": barkCard
                    case "dingTalk": dingTalkCard
                    case "feishu": feishuCard
                    default: taskCard
                    }
                }.disabled(!model.canMutate)
            }
        })
        .sheet(isPresented: Binding(get: { showAI }, set: { value in
            if value || aiModel.canLeave() { showAI = value }
        })) {
            TelegramAiDialog(model: aiModel, onClose: { showAI = false }).environmentObject(appearance)
        }
        .onAppear {
            navigation.setLeaveGuard(owner: guardID) { (!showAI || aiModel.canLeave()) && model.canLeave() }
            model.start()
        }
        .onDisappear { showAI = false; model.stop(); aiModel.stop(); navigation.removeLeaveGuard(owner: guardID) }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in model.requestReload() }
    }

    // MARK: - 定时任务（全宽）

    private var taskCard: some View {
        NativeSettingsPanel(
            title: language.text("定时任务", "Scheduled tasks"),
            subtitle: language.text("每天固定时刻执行所选检测任务", "Run selected checks at a scheduled time each day"),
            systemImage: "clock",
            accent: Color(hex: "4a9eff"),
            enabled: $model.task.enabled,
            minHeight: taskMinHeight
        ) {
            FormFieldRow(label: language.text("执行时间", "Scheduled time")) {
                VStack(alignment: .leading, spacing: 6) {
                    SelectMenu(
                        options: model.hourOptions,
                        selection: Binding(
                            get: { "\(model.task.executeHour)" },
                            set: { model.task.executeHour = Int($0 ?? "9") ?? 9 }
                        ),
                        placeholder: "选择小时",
                        width: 160,
                        allowClear: false,
                        searchable: false
                    )
                    Text(language.text("服务器时区", "Server time zone") + " · \(model.serverTimeZone) · \(String(format: "%02d:00", model.task.executeHour))")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(dark))
                        .lineLimit(1)
                }
            }

            // 下排：三项任务等宽选项卡
            FormFieldRow(label: language.text("任务项目", "Checks")) {
                VStack(alignment: .leading, spacing: 10) {
                    taskOptionTile(
                        title: language.text("账号测活", "Account checks"),
                        subtitle: "检测租户账号可用性",
                        systemImage: "person.2",
                        accent: Color(hex: "3fb950"),
                        isOn: $model.task.enableAccountCheck
                    )
                    taskOptionTile(
                        title: language.text("开机日志统计", "Launch log summary"),
                        subtitle: "汇总抢机/开机日志",
                        systemImage: "doc.text",
                        accent: Color(hex: "4a9eff"),
                        isOn: $model.task.enableBootLog
                    )
                    taskOptionTile(
                        title: language.text("OCI 费用检查", "OCI cost checks"),
                        subtitle: "检查账单与费用异常",
                        systemImage: "creditcard",
                        accent: Color(hex: "f0881a"),
                        isOn: $model.task.enableCostCheck
                    )
                }
            }
            NativeSecretEditor(title: language.text("通知校验密钥", "Notification verification secret"),
                               hasSaved: model.task.hasNotificationSecret, mode: $model.task.secretMode,
                               value: $model.task.notificationSecret)
        } footer: {
            AppButton(
                title: language.text("保存配置", "Save settings"),
                systemImage: "square.and.arrow.down",
                kind: .primary,
                isLoading: model.savingKey == "task"
            ) {
                model.saveTask()
            }
        }
    }

    /// 任务项目等宽瓷砖：图标 + 标题副标题 + 开关
    private func taskOptionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: AppTheme.bodySize, weight: .medium))
                Text(subtitle).font(.system(size: AppTheme.secondarySize))
            }
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(SwitchToggleStyle()).labelsHidden()
        }
        .foregroundColor(AppTheme.textPrimary(dark))
        .padding(.vertical, 8)
    }

    // MARK: - 通道卡片

    private var telegramCard: some View {
        NativeSettingsPanel(
            title: "Telegram",
            subtitle: "Bot 消息推送",
            systemImage: "paperplane",
            accent: Color(hex: "2aabee"),
            enabled: $model.telegram.enabled,
            minHeight: channelMinHeight
        ) {
            NativeSecretEditor(title: "Bot Token", hasSaved: model.telegram.hasBotToken,
                               mode: $model.telegram.secretMode, value: $model.telegram.botToken, required: model.telegram.enabled)
            FormFieldRow(label: "Chat ID") {
                AppTextField(
                    text: $model.telegram.chatId,
                    placeholder: "会话 ID",
                    leadingSystemImage: "number"
                )
            }
            FormFieldRow(label: "Chat Name") {
                AppTextField(
                    text: $model.telegram.chatName,
                    placeholder: "可选备注名",
                    leadingSystemImage: "person"
                )
            }
            Text(language.text("测试消息由服务器直接发送，不使用机器人代理；请在接收端确认。", "Test messages are sent directly by the server, without the bot proxy. Confirm delivery in Telegram."))
                .font(.system(size: AppTheme.secondarySize))
        } footer: {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    AppButton(title: language.text("AI 模型配置", "AI models"), kind: .secondary) { showAI = true }
                    AppButton(title: language.text("重新注册机器人", "Re-register bot"), kind: .secondary,
                              enabled: !model.hasUnsavedChanges) { model.startBot() }
                }
                HStack(spacing: 8) {
                    AppButton(title: language.text("测试", "Send test"), systemImage: "paperplane", kind: .secondary,
                              isLoading: model.savingKey == "telegramTest") { model.testTelegram() }
                    AppButton(title: language.text("保存", "Save"), systemImage: "square.and.arrow.down", kind: .primary,
                              isLoading: model.savingKey == "telegram") { model.saveTelegram() }
                }
            }
        }
    }

    private var proxyCard: some View {
        NativeSettingsPanel(
            title: language.text("Telegram 代理", "Telegram proxy"),
            subtitle: "访问 Telegram API 的出站代理",
            systemImage: "globe",
            accent: Color(hex: "9b59b6"),
            enabled: $model.proxy.enabled,
            minHeight: channelMinHeight
        ) {
            FormFieldRow(label: language.text("代理类型", "Proxy type")) {
                SelectMenu(
                    options: model.proxyTypeOptions,
                    selection: Binding(
                        get: { model.proxy.type },
                        set: { model.proxy.type = $0 ?? "HTTP" }
                    ),
                    placeholder: "类型",
                    width: 140,
                    allowClear: false,
                    searchable: false
                )
            }
            FormFieldRow(label: language.text("地址", "Host")) {
                AppTextField(
                    text: $model.proxy.host,
                    placeholder: "127.0.0.1",
                    leadingSystemImage: "server.rack"
                )
            }
            FormFieldRow(label: language.text("端口", "Port")) {
                AppTextField(
                    text: Binding(
                        get: { model.proxy.port == 0 ? "" : "\(model.proxy.port)" },
                        set: { model.proxy.port = Int($0.filter { $0.isNumber }) ?? 0 }
                    ),
                    placeholder: "7890",
                    leadingSystemImage: "number"
                )
            }
            FormFieldRow(label: language.text("用户名", "Username")) {
                AppTextField(text: $model.proxy.username, placeholder: language.text("可选", "Optional"))
            }
            NativeSecretEditor(title: language.text("代理密码", "Proxy password"), hasSaved: model.proxy.hasPassword,
                               mode: $model.proxy.secretMode, value: $model.proxy.password)
            Text(language.text("端口检测只检查 TCP 连接，不验证代理认证。保存代理后可重新注册 Telegram 机器人。", "The port check tests TCP connectivity, without verifying proxy authentication. Re-register the Telegram bot after saving proxy settings."))
                .font(.system(size: AppTheme.secondarySize))
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: language.text("检测端口", "Check port"),
                    systemImage: "network",
                    kind: .secondary,
                    isLoading: model.savingKey == "proxyTest"
                ) {
                    model.testProxy()
                }
                AppButton(
                    title: language.text("保存", "Save"),
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "proxy"
                ) {
                    model.saveProxy()
                }
            }
        }
    }

    private var barkCard: some View {
        NativeSettingsPanel(
            title: "Bark",
            subtitle: "iOS 推送通知",
            systemImage: "bell.badge",
            accent: Color(hex: "f0881a"),
            enabled: $model.bark.enabled,
            minHeight: channelMinHeight
        ) {
            FormFieldRow(label: language.text("服务 URL", "Service URL")) {
                AppTextField(text: $model.bark.url, placeholder: "https://api.day.app")
            }
            NativeSecretEditor(title: "Device Key", hasSaved: model.bark.hasDeviceKey,
                               mode: $model.bark.secretMode, value: $model.bark.deviceKey, required: model.bark.enabled)
            Text("用于 iOS Bark App 接收推送；服务 URL 可自建。")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(dark))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: language.text("测试", "Send test"),
                    systemImage: "paperplane",
                    kind: .secondary,
                    isLoading: model.savingKey == "barkTest"
                ) {
                    model.testBark()
                }
                AppButton(
                    title: language.text("保存", "Save"),
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "bark"
                ) {
                    model.saveBark()
                }
            }
        }
    }

    private var dingTalkCard: some View {
        NativeSettingsPanel(
            title: language.text("钉钉", "DingTalk"),
            subtitle: "群机器人 Webhook",
            systemImage: "message",
            accent: Color(hex: "0089ff"),
            enabled: $model.dingTalk.enabled,
            minHeight: channelMinHeight
        ) {
            NativeSecretEditor(title: "Webhook", hasSaved: model.dingTalk.hasWebhook,
                               mode: $model.dingTalk.webhookMode, value: $model.dingTalk.webhook, required: model.dingTalk.enabled)
            NativeSecretEditor(title: language.text("签名密钥", "Signing secret"), hasSaved: model.dingTalk.hasSecret,
                               mode: $model.dingTalk.secretMode, value: $model.dingTalk.secret, required: model.dingTalk.enabled)
            Text("在钉钉群「智能群助手」中添加自定义机器人获取 Webhook。")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(dark))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: language.text("测试", "Send test"),
                    systemImage: "paperplane",
                    kind: .secondary,
                    isLoading: model.savingKey == "dingTalkTest"
                ) {
                    model.testDingTalk()
                }
                AppButton(
                    title: language.text("保存", "Save"),
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "dingTalk"
                ) {
                    model.saveDingTalk()
                }
            }
        }
    }

    private var feishuCard: some View {
        NativeSettingsPanel(
            title: language.text("飞书", "Feishu"),
            subtitle: "群机器人 Webhook",
            systemImage: "bubble.left.and.bubble.right",
            accent: Color(hex: "00d6b9"),
            enabled: $model.feishu.enabled,
            minHeight: channelMinHeight
        ) {
            // 与 Bark / 钉钉同结构：单列 Webhook + 签名密钥
            NativeSecretEditor(title: "Webhook", hasSaved: model.feishu.hasWebhook,
                               mode: $model.feishu.webhookMode, value: $model.feishu.webhook, required: model.feishu.enabled)
            NativeSecretEditor(title: language.text("签名密钥", "Signing secret"), hasSaved: model.feishu.hasSecret,
                               mode: $model.feishu.secretMode, value: $model.feishu.secret, required: false)
            Text("在飞书群「设置 → 群机器人」中添加自定义机器人。")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(dark))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: language.text("测试", "Send test"),
                    systemImage: "paperplane",
                    kind: .secondary,
                    isLoading: model.savingKey == "feishuTest"
                ) {
                    model.testFeishu()
                }
                AppButton(
                    title: language.text("保存", "Save"),
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "feishu"
                ) {
                    model.saveFeishu()
                }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f85149"))
            Text(text).font(.system(size: 14))
            Spacer()
            Button(language.text("重新读取并核对", "Reload and review")) { model.requestReload() }
                .disabled(model.isLoading || model.savingKey != nil)
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }
}
