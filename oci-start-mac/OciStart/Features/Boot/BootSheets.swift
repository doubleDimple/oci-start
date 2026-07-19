import SwiftUI
import AppKit

/// Boot modals: edit config / 原生添加抢机配置（禁止 WebEmbed）。
/// 开机详情与开机日志已改为 `BootDetailView` 整页，不在此弹框。
struct BootSheetHost: View {
    let sheet: BootSheet
    @ObservedObject var model: BootViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    private var dark: Bool { appearance.isDarkEffective }
    private var primaryText: Color { AppSheetSurface.primaryText(dark) }
    private var mutedText: Color { AppSheetSurface.mutedText(dark) }

    var body: some View {
        switch sheet {
        case .editDetail:
            editSheet
        case .createConfig(let item):
            createConfigSheet(item)
        }
    }

    private func chrome<Content: View, Footer: View>(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = 720,
        height: CGFloat = 520,
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

    // MARK: - Edit

    private var editSheet: some View {
        chrome(title: "修改开机配置", systemImage: "slider.horizontal.3", width: 440, height: 420, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) {
                    presentationMode.wrappedValue.dismiss()
                }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy) {
                    model.submitEditDetail()
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                FormFieldRow(label: "OCPU", required: true) {
                    AppTextField(text: $model.editOcpu, placeholder: "1")
                }
                FormFieldRow(label: "内存 (GB)", required: true) {
                    AppTextField(text: $model.editMemory, placeholder: "6")
                }
                FormFieldRow(label: "磁盘 (GB)", required: true) {
                    AppTextField(text: $model.editDisk, placeholder: "50")
                }
                FormFieldRow(label: "循环间隔 (秒)", required: true) {
                    AppTextField(text: $model.editLoopTime, placeholder: "60")
                }
                FormFieldRow(label: "时段范围") {
                    AppTextField(text: $model.editDayGap, placeholder: "如 08:00-22:00")
                }
                FormFieldRow(label: "Root 密码", required: true) {
                    AppTextField(text: $model.editPassword, placeholder: "root 密码")
                }
                if let err = model.formError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(AppSheetSurface.accentRed(dark))
                }
            }
        }
    }

    // MARK: - Create config

    private func createConfigSheet(_ item: BootTaskItem) -> some View {
        chrome(
            title: "添加抢机配置",
            systemImage: "plus.circle",
            width: 520,
            height: 580,
            footer: {
                HStack {
                    AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                    Spacer()
                    AppButton(
                        title: "保存任务",
                        systemImage: "checkmark",
                        kind: .primary,
                        isLoading: model.formBusy
                    ) {
                        model.submitCreateConfig()
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .foregroundColor(AppTheme.sidebarActive)
                    Text(item.displayTenant)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(primaryText)
                    if !item.regionName.isEmpty {
                        Text("· \(item.regionName)")
                            .font(.system(size: 12))
                            .foregroundColor(mutedText)
                    }
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppSheetSurface.panelBg(dark)))

                FormFieldRow(label: "架构") {
                    HStack(spacing: 8) {
                        ForEach(["ARM", "AMD", "X86"], id: \.self) { arch in
                            Button(action: { model.onCreateArchitectureChanged(arch) }) {
                                Text(arch)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(model.createArchitecture == arch ? .white : primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(model.createArchitecture == arch
                                                  ? AppTheme.sidebarActive
                                                  : AppSheetSurface.panelBg(dark))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        Spacer()
                        if model.createLoadingImages {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                }

                HStack(spacing: 10) {
                    FormFieldRow(label: "OCPU", required: true) {
                        AppTextField(text: $model.createOcpu, placeholder: "1")
                    }
                    FormFieldRow(label: "内存 GB", required: true) {
                        AppTextField(text: $model.createMemory, placeholder: "6")
                    }
                    FormFieldRow(label: "磁盘 GB", required: true) {
                        AppTextField(text: $model.createDisk, placeholder: "50")
                    }
                }

                HStack(spacing: 10) {
                    FormFieldRow(label: "循环间隔(秒)", required: true) {
                        AppTextField(text: $model.createLoopTime, placeholder: "60")
                    }
                    FormFieldRow(label: "实例数量", required: true) {
                        AppTextField(text: $model.createCount, placeholder: "1")
                    }
                }

                FormFieldRow(label: "时段范围") {
                    AppTextField(text: $model.createDayGap, placeholder: "如 08:00-22:00，可空")
                }
                FormFieldRow(label: "Root 密码", required: true) {
                    AppTextField(text: $model.createPassword, placeholder: "root 密码", secure: true)
                }

                FormFieldRow(label: "操作系统", required: true) {
                    SelectMenu(
                        options: model.createOSList.map { SelectOption(id: $0, title: $0) },
                        selection: Binding(
                            get: { model.createSelectedOS.isEmpty ? nil : model.createSelectedOS },
                            set: { if let v = $0 { model.applyCreateOS(v) } }
                        ),
                        placeholder: model.createLoadingImages ? "加载镜像…" : "选择系统…",
                        width: 460,
                        enabled: !model.createOSList.isEmpty,
                        searchable: true
                    )
                }
                FormFieldRow(label: "系统版本", required: true) {
                    SelectMenu(
                        options: model.createVersions.map {
                            SelectOption(id: $0.operatingSystemVersion, title: $0.operatingSystemVersion)
                        },
                        selection: Binding(
                            get: { model.createSelectedVersion.isEmpty ? nil : model.createSelectedVersion },
                            set: { if let v = $0 { model.applyCreateVersion(v) } }
                        ),
                        placeholder: "选择版本…",
                        width: 460,
                        enabled: !model.createVersions.isEmpty
                    )
                }

                if !model.createImageId.isEmpty {
                    Text("镜像 ID：\(model.createImageId)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(mutedText)
                        .lineLimit(1)
                }

                if let err = model.formError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(AppSheetSurface.accentRed(dark))
                }
            }
        }
    }
}
