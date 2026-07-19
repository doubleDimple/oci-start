import SwiftUI

/// 原生通知管理（对齐 Web `/system/notifySettings`）。
/// UI 标准：`ModuleSettingsCard` + `EqualHeightCardRow`（同质量管理页）。
struct NotifyView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = NotifyViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    /// 通道卡片统一高度
    private let channelMinHeight: CGFloat = 400
    /// 定时任务全宽卡（内容横向展开，高度可略低）
    private let taskMinHeight: CGFloat = 340

    var body: some View {
        PageScaffold(
            title: "通知管理",
            subtitle: "定时任务 · Telegram · Bark · 钉钉 · 飞书",
            systemImage: "bell",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let err = model.errorText, !err.isEmpty {
                            errorBanner(err)
                        }

                        // 1) 定时任务：全宽独立区（与 Web 一致，避免与通道表单混排）
                        taskCard

                        // 2) 通知通道：相关卡片成对
                        EqualHeightCardRow(minHeight: channelMinHeight) {
                            telegramCard
                        } second: {
                            proxyCard
                        }
                        EqualHeightCardRow(minHeight: channelMinHeight) {
                            barkCard
                        } second: {
                            dingTalkCard
                        }
                        // 飞书与 Bark / 钉钉同尺寸：半宽 + 同 minHeight
                        EqualHeightCardRow(minHeight: channelMinHeight) {
                            feishuCard
                        } second: {
                            Color.clear
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

    // MARK: - 定时任务（全宽）

    private var taskCard: some View {
        ModuleSettingsCard(
            title: "定时任务",
            subtitle: "每天固定时刻执行所选检测任务",
            systemImage: "clock",
            accent: Color(hex: "4a9eff"),
            enabled: $model.task.enabled,
            minHeight: taskMinHeight
        ) {
            FormFieldRow(label: "执行时间") {
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
                    Text("系统时区下每天 \(String(format: "%02d:00", model.task.executeHour)) 触发")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.sidebarText(dark))
                        .lineLimit(1)
                }
            }

            // 下排：三项任务等宽选项卡
            FormFieldRow(label: "任务项目") {
                HStack(alignment: .top, spacing: 10) {
                    taskOptionTile(
                        title: "账号测活",
                        subtitle: "检测租户账号可用性",
                        systemImage: "person.2",
                        accent: Color(hex: "3fb950"),
                        isOn: $model.task.enableAccountCheck
                    )
                    taskOptionTile(
                        title: "开机日志统计",
                        subtitle: "汇总抢机/开机日志",
                        systemImage: "doc.text",
                        accent: Color(hex: "4a9eff"),
                        isOn: $model.task.enableBootLog
                    )
                    taskOptionTile(
                        title: "OCI 费用检查",
                        subtitle: "检查账单与费用异常",
                        systemImage: "creditcard",
                        accent: Color(hex: "f0881a"),
                        isOn: $model.task.enableCostCheck
                    )
                }
            }
        } footer: {
            AppButton(
                title: "保存配置",
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                }
                Spacer(minLength: 4)
                Toggle("", isOn: isOn)
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppInputStyle.fill(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isOn.wrappedValue
                        ? accent.opacity(dark ? 0.45 : 0.35)
                        : AppTheme.border(dark).opacity(0.7),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isOn.wrappedValue)
    }

    // MARK: - 通道卡片

    private var telegramCard: some View {
        ModuleSettingsCard(
            title: "Telegram",
            subtitle: "Bot 消息推送",
            systemImage: "paperplane",
            accent: Color(hex: "2aabee"),
            enabled: $model.telegram.enabled,
            minHeight: channelMinHeight
        ) {
            FormFieldRow(label: "Bot Token") {
                AppTextField(text: $model.telegram.botToken, placeholder: "从 @BotFather 获取")
            }
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
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: "测试",
                    systemImage: "paperplane",
                    kind: .secondary,
                    isLoading: model.savingKey == "telegramTest"
                ) {
                    model.testTelegram()
                }
                AppButton(
                    title: "保存",
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    isLoading: model.savingKey == "telegram"
                ) {
                    model.saveTelegram()
                }
            }
        }
    }

    private var proxyCard: some View {
        ModuleSettingsCard(
            title: "Telegram 代理",
            subtitle: "访问 Telegram API 的出站代理",
            systemImage: "globe",
            accent: Color(hex: "9b59b6"),
            enabled: $model.proxy.enabled,
            minHeight: channelMinHeight
        ) {
            FormFieldRow(label: "代理类型") {
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
            FormFieldRow(label: "地址") {
                AppTextField(
                    text: $model.proxy.host,
                    placeholder: "127.0.0.1",
                    leadingSystemImage: "server.rack"
                )
            }
            FormFieldRow(label: "端口") {
                AppTextField(
                    text: Binding(
                        get: { model.proxy.port == 0 ? "" : "\(model.proxy.port)" },
                        set: { model.proxy.port = Int($0.filter { $0.isNumber }) ?? 0 }
                    ),
                    placeholder: "7890",
                    leadingSystemImage: "number"
                )
            }
            HStack(spacing: 10) {
                FormFieldRow(label: "用户名") {
                    AppTextField(text: $model.proxy.username, placeholder: "可选")
                }
                FormFieldRow(label: "密码") {
                    AppTextField(text: $model.proxy.password, placeholder: "可选", secure: true)
                }
            }
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: "测试",
                    systemImage: "network",
                    kind: .secondary,
                    isLoading: model.savingKey == "proxyTest"
                ) {
                    model.testProxy()
                }
                AppButton(
                    title: "保存",
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
        ModuleSettingsCard(
            title: "Bark",
            subtitle: "iOS 推送通知",
            systemImage: "bell.badge",
            accent: Color(hex: "f0881a"),
            enabled: $model.bark.enabled,
            minHeight: channelMinHeight
        ) {
            FormFieldRow(label: "服务 URL") {
                AppTextField(text: $model.bark.url, placeholder: "https://api.day.app")
            }
            FormFieldRow(label: "Device Key") {
                AppTextField(text: $model.bark.deviceKey, placeholder: "设备密钥", leadingSystemImage: "key")
            }
            Text("用于 iOS Bark App 接收推送；服务 URL 可自建。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: "测试",
                    systemImage: "paperplane",
                    kind: .secondary,
                    isLoading: model.savingKey == "barkTest"
                ) {
                    model.testBark()
                }
                AppButton(
                    title: "保存",
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
        ModuleSettingsCard(
            title: "钉钉",
            subtitle: "群机器人 Webhook",
            systemImage: "message",
            accent: Color(hex: "0089ff"),
            enabled: $model.dingTalk.enabled,
            minHeight: channelMinHeight
        ) {
            FormFieldRow(label: "Webhook") {
                AppTextField(text: $model.dingTalk.webhook, placeholder: "https://oapi.dingtalk.com/...")
            }
            FormFieldRow(label: "加签密钥") {
                AppTextField(text: $model.dingTalk.secret, placeholder: "可选 Secret", secure: true)
            }
            Text("在钉钉群「智能群助手」中添加自定义机器人获取 Webhook。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: "测试",
                    systemImage: "paperplane",
                    kind: .secondary,
                    isLoading: model.savingKey == "dingTalkTest"
                ) {
                    model.testDingTalk()
                }
                AppButton(
                    title: "保存",
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
        ModuleSettingsCard(
            title: "飞书",
            subtitle: "群机器人 Webhook",
            systemImage: "bubble.left.and.bubble.right",
            accent: Color(hex: "00d6b9"),
            enabled: $model.feishu.enabled,
            minHeight: channelMinHeight
        ) {
            // 与 Bark / 钉钉同结构：单列 Webhook + 签名密钥
            FormFieldRow(label: "Webhook") {
                AppTextField(text: $model.feishu.webhook, placeholder: "https://open.feishu.cn/...")
            }
            FormFieldRow(label: "签名密钥") {
                AppTextField(text: $model.feishu.secret, placeholder: "可选 Secret", secure: true)
            }
            Text("在飞书群「设置 → 群机器人」中添加自定义机器人。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: 8) {
                AppButton(
                    title: "测试",
                    systemImage: "paperplane",
                    kind: .secondary,
                    isLoading: model.savingKey == "feishuTest"
                ) {
                    model.testFeishu()
                }
                AppButton(
                    title: "保存",
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
