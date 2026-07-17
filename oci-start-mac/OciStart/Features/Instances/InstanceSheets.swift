import SwiftUI
import AppKit

/// Instance modals + WebEmbed secondary pages (SSH / console / VNIC).
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
        case .embed(let title, let path, let query):
            embedSheet(title: title, path: path, query: query)
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(mutedText)
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

    // MARK: - Text edit

    private func editTextSheet(
        title: String,
        systemImage: String,
        label: String,
        item: InstanceItem,
        save: @escaping () -> Void
    ) -> some View {
        chrome(title: title, systemImage: systemImage, width: 420, height: 240, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy, action: save)
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(label)
                AppTextField(text: $model.formText, placeholder: label)
                Text(item.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                formErrorLine()
            }
        }
    }

    // MARK: - Config / Boot / VPU

    private func configSheet(_ item: InstanceItem) -> some View {
        chrome(title: "修改配置", systemImage: "cpu", width: 420, height: 300, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy) {
                    model.submitUpdateConfig(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.displayName).font(.system(size: 13, weight: .semibold)).foregroundColor(primaryText)
                sectionLabel("CPU 核心数 (1–24)")
                AppTextField(text: $model.formCpu, placeholder: "CPU")
                sectionLabel("内存 GB (1–256)")
                AppTextField(text: $model.formMemory, placeholder: "内存")
                formErrorLine()
            }
        }
    }

    private func bootSheet(_ item: InstanceItem) -> some View {
        chrome(title: "扩容引导卷", systemImage: "externaldrive", width: 420, height: 280, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "扩容", kind: .primary, isLoading: model.formBusy) {
                    model.submitUpdateBoot(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("当前：\(item.bootVolumeSizeInGBs) GB")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                sectionLabel("目标大小 GB（≥47，仅支持扩容）")
                AppTextField(text: $model.formBootSize, placeholder: "大小")
                formErrorLine()
            }
        }
    }

    private func vpuSheet(_ item: InstanceItem) -> some View {
        chrome(title: "修改 VPU", systemImage: "slider.horizontal.3", width: 420, height: 280, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy) {
                    model.submitUpdateVpu(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("当前 VPU：\(item.vpusPerGB)")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                sectionLabel("VPU (0–120，步长 10)")
                AppTextField(text: $model.formVpu, placeholder: "VPU")
                formErrorLine()
            }
        }
    }

    // MARK: - Change IP

    private func changeIpSheet(_ item: InstanceItem) -> some View {
        chrome(title: "更换公网 IP", systemImage: "arrow.triangle.2.circlepath", width: 460, height: 300, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "更换", kind: .primary, isLoading: model.formBusy) {
                    model.submitChangeIp(item)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.displayName).font(.system(size: 13, weight: .semibold)).foregroundColor(primaryText)
                Text("当前 IPv4：\(item.publicIps.isEmpty ? "—" : item.publicIps)")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                sectionLabel("CIDR 段（可选，逗号/换行分隔；留空随机）")
                AppTextField(text: $model.formCidr, placeholder: "例如 10.0.0.0/24")
                formErrorLine()
            }
        }
    }

    // MARK: - Terminate

    private func terminateSheet(_ item: InstanceItem) -> some View {
        chrome(title: "终止实例", systemImage: "xmark.octagon", width: 460, height: 320, footer: {
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
            VStack(alignment: .leading, spacing: 12) {
                Text("将永久终止 \(item.displayName)，此操作不可恢复。")
                    .font(.system(size: 13))
                    .foregroundColor(AppSheetSurface.accentRed(dark))
                    .fixedSize(horizontal: false, vertical: true)
                AppButton(
                    title: model.terminateCodeSent ? "重新发送验证码" : "发送验证码",
                    systemImage: "envelope",
                    kind: .secondary,
                    isLoading: model.formBusy
                ) {
                    model.sendTerminateCode(item)
                }
                sectionLabel("验证码")
                AppTextField(text: $model.formVerifyCode, placeholder: "输入验证码")
                formErrorLine()
            }
        }
    }

    // MARK: - Embed

    private func embedSheet(title: String, path: String, query: [String: String]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(primaryText)
                Spacer()
                AppButton(title: "关闭", kind: .secondary) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppSheetSurface.surface(dark))
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(AppSheetSurface.border(dark)),
                alignment: .bottom
            )

            InstanceWebEmbedRepresentable(
                session: session,
                path: path,
                query: query,
                title: title
            )
            .frame(minWidth: 880, minHeight: 560)
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(AppSheetSurface.surface(dark))
    }
}

// MARK: - WebEmbed bridge

private struct InstanceWebEmbedRepresentable: NSViewControllerRepresentable {
    let session: AppSession
    let path: String
    let query: [String: String]
    let title: String

    func makeNSViewController(context: Context) -> WebEmbedViewController {
        WebEmbedViewController(session: session, path: path, query: query, title: title)
    }

    func updateNSViewController(_ nsViewController: WebEmbedViewController, context: Context) {
        // path fixed for sheet lifetime
    }
}
