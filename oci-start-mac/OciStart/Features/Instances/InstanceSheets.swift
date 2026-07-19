import SwiftUI
import AppKit

/// Instance modals（表单类弹层；SSH / 控制台 / 网络管理走 InstancesView 整页）。
struct InstanceSheetHost: View {
    let sheet: InstanceSheet
    @ObservedObject var model: InstancesViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    private var dark: Bool { appearance.isDarkEffective }
    private var primaryText: Color { AppSheetSurface.primaryText(dark) }
    private var mutedText: Color { AppSheetSurface.mutedText(dark) }

    var body: some View {
        switch sheet {
        case .updateName(let item):
            editTextSheet(
                title: "修改实例名称",
                systemImage: "tag",
                label: "新名称",
                item: item,
                save: { model.submitUpdateName(item) }
            )
        case .updateRemark(let item):
            editTextSheet(
                title: "修改备注",
                systemImage: "note.text",
                label: "备注",
                item: item,
                save: { model.submitUpdateRemark(item) }
            )
        case .updateConfig(let item):
            configSheet(item)
        case .updateBoot(let item):
            bootSheet(item)
        case .updateVpu(let item):
            vpuSheet(item)
        case .changeIp(let item):
            changeIpSheet(item)
        case .terminate(let item):
            terminateSheet(item)
        case .osReset(let item):
            osResetSheet(item)
        case .ddLog(let item):
            ddLogSheet(item)
        }
    }

    // MARK: - Chrome

    private func chrome<Content: View, Footer: View>(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = 440,
        height: CGFloat = 280,
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

    private func instanceHeader(_ item: InstanceItem) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.sidebarActive.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarActive)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName.isEmpty ? "—" : item.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryText)
                    .lineLimit(1)
                Text("\(item.regionName.isEmpty ? "—" : item.regionName) · \(item.stateLabel)")
                    .font(.system(size: 11))
                    .foregroundColor(mutedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppSheetSurface.panelBg(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppSheetSurface.border(dark), lineWidth: 1)
        )
    }

    private func formErrorLine() -> some View {
        Group {
            if let err = model.formError, !err.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(err)
                        .font(.system(size: 12))
                }
                .foregroundColor(AppSheetSurface.accentRed(dark))
            }
        }
    }

    // MARK: - Text edit

    private func editTextSheet(
        title: String,
        systemImage: String,
        label: String,
        item: InstanceItem,
        save: @escaping () -> Void
    ) -> some View {
        chrome(title: title, systemImage: systemImage, width: 440, height: 300, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy, action: save)
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                instanceHeader(item)
                FormFieldRow(label: label, required: true) {
                    AppTextField(text: $model.formText, placeholder: label, leadingSystemImage: systemImage)
                }
                formErrorLine()
            }
        }
    }

    // MARK: - Config / Boot / VPU

    private func configSheet(_ item: InstanceItem) -> some View {
        chrome(title: "修改配置", systemImage: "cpu", width: 440, height: 360, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy) {
                    model.submitUpdateConfig(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                instanceHeader(item)
                Text("当前 \(item.cpuAndMem)")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                FormFieldRow(label: "CPU 核心数 (1–24)", required: true) {
                    AppTextField(text: $model.formCpu, placeholder: "CPU", leadingSystemImage: "cpu")
                }
                FormFieldRow(label: "内存 GB (1–256)", required: true) {
                    AppTextField(text: $model.formMemory, placeholder: "内存", leadingSystemImage: "rectangle.compress.vertical")
                }
                formErrorLine()
            }
        }
    }

    private func bootSheet(_ item: InstanceItem) -> some View {
        chrome(title: "扩容引导卷", systemImage: "externaldrive", width: 440, height: 320, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "扩容", kind: .primary, isLoading: model.formBusy) {
                    model.submitUpdateBoot(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                instanceHeader(item)
                Text("当前：\(item.bootVolumeSizeInGBs) GB · 仅支持扩容")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                FormFieldRow(label: "目标大小 GB（≥47）", required: true) {
                    AppTextField(text: $model.formBootSize, placeholder: "大小", leadingSystemImage: "externaldrive")
                }
                formErrorLine()
            }
        }
    }

    private func vpuSheet(_ item: InstanceItem) -> some View {
        chrome(title: "修改 VPU", systemImage: "slider.horizontal.3", width: 460, height: 340, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy) {
                    model.submitUpdateVpu(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                instanceHeader(item)
                Text("当前 VPU：\(item.vpusPerGB) · 范围 0–120，步长 10")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                // 对齐 Web range 滑块
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("VPUs / GB")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(primaryText)
                        Spacer()
                        Text(model.formVpu)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.sidebarActive)
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(Int(model.formVpu) ?? 0) },
                            set: { model.formVpu = "\(Int(($0 / 10).rounded() * 10))" }
                        ),
                        in: 0...120,
                        step: 10
                    )
                    .accentColor(AppTheme.sidebarActive)
                    HStack {
                        ForEach([0, 30, 60, 90, 120], id: \.self) { v in
                            Text("\(v)")
                                .font(.system(size: 10))
                                .foregroundColor(mutedText)
                            if v < 120 { Spacer(minLength: 0) }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppSheetSurface.panelBg(dark))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppSheetSurface.border(dark), lineWidth: 1)
                )
                formErrorLine()
            }
        }
    }

    // MARK: - Change IP

    private func changeIpSheet(_ item: InstanceItem) -> some View {
        chrome(title: "更换公网 IP", systemImage: "arrow.triangle.2.circlepath", width: 480, height: 420, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary, enabled: !model.formBusy) {
                    presentationMode.wrappedValue.dismiss()
                }
                AppButton(title: "更换", kind: .primary, isLoading: model.formBusy) {
                    model.submitChangeIp(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                instanceHeader(item)
                Text("当前 IPv4：\(item.publicIps.isEmpty ? "—" : item.publicIps)")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("目标 CIDR（可选，留空随机）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(primaryText)
                        Spacer()
                        AppButton(title: "添加", systemImage: "plus", kind: .secondary) {
                            model.addCidrLine()
                        }
                    }
                    ForEach(Array(model.formCidrLines.enumerated()), id: \.offset) { idx, _ in
                        HStack(spacing: 8) {
                            AppTextField(
                                text: Binding(
                                    get: {
                                        guard model.formCidrLines.indices.contains(idx) else { return "" }
                                        return model.formCidrLines[idx]
                                    },
                                    set: { newVal in
                                        guard model.formCidrLines.indices.contains(idx) else { return }
                                        model.formCidrLines[idx] = newVal
                                    }
                                ),
                                placeholder: "例如 10.0.0.0/24",
                                leadingSystemImage: "network"
                            )
                            if model.formCidrLines.count > 1 {
                                Button(action: { model.removeCidrLine(at: idx) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppSheetSurface.accentRed(dark))
                                        .frame(width: 32, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(AppSheetSurface.accentRed(dark).opacity(0.12))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("删除此行")
                            }
                        }
                    }
                }

                if let result = model.changeIpResult {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "3fb950"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("IP 切换成功")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(primaryText)
                            Text("\(result.oldIp.isEmpty ? "—" : result.oldIp) → \(result.newIp)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.sidebarActive)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color(hex: "3fb950").opacity(0.12))
                    .cornerRadius(10)
                }

                formErrorLine()
            }
        }
    }

    // MARK: - Terminate

    private func terminateSheet(_ item: InstanceItem) -> some View {
        chrome(title: "终止实例", systemImage: "xmark.octagon", width: 460, height: 360, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(
                    title: "确认终止",
                    kind: .danger,
                    isLoading: model.formBusy,
                    enabled: model.terminateCodeSent
                ) {
                    model.submitTerminate(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                instanceHeader(item)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppSheetSurface.accentRed(dark))
                    Text("将永久终止云端实例，此操作不可恢复。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppSheetSurface.accentRed(dark))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppSheetSurface.accentRed(dark).opacity(0.1))
                .cornerRadius(10)

                AppButton(
                    title: model.terminateCodeSent ? "重新发送验证码" : "发送验证码",
                    systemImage: "envelope",
                    kind: .secondary,
                    isLoading: model.formBusy
                ) {
                    model.sendTerminateCode(item)
                }
                FormFieldRow(label: "验证码", required: true) {
                    AppTextField(text: $model.formVerifyCode, placeholder: "输入验证码", leadingSystemImage: "lock")
                }
                formErrorLine()
            }
        }
    }

    // MARK: - OS Reset

    private func osResetSheet(_ item: InstanceItem) -> some View {
        chrome(title: "系统重装", systemImage: "arrow.counterclockwise", width: 480, height: 460, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "开始重装", kind: .danger, isLoading: model.formBusy) {
                    model.submitOsReset(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                instanceHeader(item)
                FormFieldRow(label: "目标系统", required: true) {
                    SelectMenu(
                        options: InstanceDDOsOptions.all,
                        selection: Binding(
                            get: { model.ddOsId.isEmpty ? nil : model.ddOsId },
                            set: { model.ddOsId = $0 ?? "" }
                        ),
                        placeholder: "选择操作系统…",
                        width: 400
                    )
                }
                FormFieldRow(label: "新 root 密码", required: true) {
                    AppTextField(
                        text: $model.ddPassword,
                        placeholder: "新密码",
                        secure: true,
                        leadingSystemImage: "key"
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("注意")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppSheetSurface.accentRed(dark))
                    Text("重装将覆盖磁盘数据；依赖 reinstall 脚本，请确保实例已配置 SSH 密码且网络可达。")
                        .font(.system(size: 11))
                        .foregroundColor(mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppSheetSurface.accentRed(dark).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppSheetSurface.accentRed(dark).opacity(0.35), lineWidth: 1)
                )
                .cornerRadius(10)
                formErrorLine()
            }
        }
    }

    private func ddLogSheet(_ item: InstanceItem) -> some View {
        chrome(title: "重装日志 — \(item.displayName)", systemImage: "terminal", width: 640, height: 480, footer: {
            HStack(spacing: 10) {
                if model.ddRunning {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("执行中…")
                            .font(.system(size: 12))
                            .foregroundColor(mutedText)
                    }
                    Spacer()
                } else {
                    Spacer()
                    AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                }
            }
        }) {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.ddLogLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(primaryText.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(12)
                    .onChange(of: model.ddLogLines.count) { _ in
                        if let last = model.ddLogLines.indices.last {
                            withAnimation {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(dark ? Color(hex: "161820") : Color(hex: "0f172a").opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppSheetSurface.border(dark), lineWidth: 1)
            )
        }
    }

}
