import SwiftUI
import AppKit

// MARK: - Boot template model

private struct BootTemplate: Identifiable {
    let id: String
    let arch: String
    let label: String
    let ocpu: String
    let memory: String
    let disk: String
    let tag: String       // "免费" / "付费"
    let tagDanger: Bool
}

private let bootTemplates: [BootTemplate] = [
    BootTemplate(id: "arm-base",     arch: "ARM", label: "ARM Base",     ocpu: "1", memory: "6",  disk: "50",  tag: "免费", tagDanger: false),
    BootTemplate(id: "arm-std",      arch: "ARM", label: "ARM Standard", ocpu: "2", memory: "12", disk: "50",  tag: "免费", tagDanger: false),
    BootTemplate(id: "arm-high",     arch: "ARM", label: "ARM High",     ocpu: "4", memory: "24", disk: "50",  tag: "免费", tagDanger: false),
    BootTemplate(id: "arm-a2",       arch: "ARM", label: "ARM A2",       ocpu: "4", memory: "24", disk: "200", tag: "付费", tagDanger: true),
    BootTemplate(id: "amd-base",     arch: "AMD", label: "AMD Base",     ocpu: "1", memory: "1",  disk: "50",  tag: "免费", tagDanger: false),
    BootTemplate(id: "amd-e3",       arch: "AMD", label: "AMD E3",       ocpu: "4", memory: "24", disk: "50",  tag: "付费", tagDanger: true),
    BootTemplate(id: "amd-e4",       arch: "AMD", label: "AMD E4",       ocpu: "4", memory: "24", disk: "50",  tag: "付费", tagDanger: true),
    BootTemplate(id: "amd-e5",       arch: "AMD", label: "AMD E5",       ocpu: "4", memory: "24", disk: "50",  tag: "付费", tagDanger: true),
    BootTemplate(id: "x86-base",     arch: "X86", label: "X86 Base",     ocpu: "1", memory: "1",  disk: "50",  tag: "免费", tagDanger: false),
]

private let intervalPresets: [(String, String)] = [
    ("10s", "10"), ("30s", "30"), ("60s", "60"), ("200s", "200"), ("500s", "500")
]

/// 创建开机任务整页 — 对应 Web `add_boot.ftl`，从租户列表进入，非弹框。
struct TenantBootCreateView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var tenant: TenantItem? { model.bootPageParent }

    private var primaryText: Color { dark ? Color.white.opacity(0.9) : Color.primary }
    private var mutedText: Color { AppTheme.sidebarText(dark) }
    private var panelBg: Color { dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03) }
    private var border: Color { AppTheme.border(dark) }

    @State private var selectedTemplateId: String = "arm-base"

    private var visibleTemplates: [BootTemplate] {
        bootTemplates.filter { $0.arch == model.bootArchitecture }
    }

    var body: some View {
        PageScaffold(
            title: "创建开机任务",
            subtitle: tenant.map { "\($0.displayName) · \($0.region.isEmpty ? "—" : $0.region)" },
            systemImage: "plus.circle",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        archSection
                            .zIndex(2)
                        templateSection
                            .zIndex(1)
                        HStack(alignment: .top, spacing: 20) {
                            configSection
                            imageSection
                        }
                    }
                    .padding(20)
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
                model.closeBootCreate()
            }
            AppButton(title: "保存任务", systemImage: "checkmark", kind: .primary) {
                guard let t = tenant else { return }
                model.submitBoot(t)
            }
        }
    }

    // MARK: - Architecture section

    private var archSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("架构选择")
            HStack(spacing: 10) {
                ForEach(["ARM", "AMD", "X86"], id: \.self) { arch in
                    archCard(arch)
                }
                if !model.bootRegionOptions.isEmpty {
                    Divider().frame(height: 44)
                    regionPicker
                }
            }
        }
    }

    private func archCard(_ arch: String) -> some View {
        let active = model.bootArchitecture == arch
        return Button(action: {
            guard model.bootArchitecture != arch else { return }
            model.bootArchitecture = arch
            let first = bootTemplates.first(where: { $0.arch == arch })
            if let t = first { applyTemplate(t) }
            Task {
                let tid = Int64(model.bootSelectedRegionTenantId) ?? (tenant?.id ?? 0)
                await model.loadBootImages(tenantId: tid)
            }
        }) {
            VStack(spacing: 4) {
                Text(arch)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(active ? .white : primaryText)
                Text(arch == "ARM" ? "AArch64" : (arch == "X86" ? "x86-64" : "x86-64"))
                    .font(.system(size: 10))
                    .foregroundColor(active ? .white.opacity(0.8) : mutedText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(active ? AppTheme.sidebarActive : (dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? AppTheme.sidebarActive : border.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("区域租户").font(.system(size: 11, weight: .semibold)).foregroundColor(mutedText)
            SelectMenu(
                options: model.bootRegionOptions.map { SelectOption(id: $0.id, title: $0.label) },
                selection: Binding(
                    get: { model.bootSelectedRegionTenantId },
                    set: {
                        model.bootSelectedRegionTenantId = $0 ?? "\(tenant?.id ?? 0)"
                        Task {
                            let tid = Int64(model.bootSelectedRegionTenantId) ?? (tenant?.id ?? 0)
                            await model.loadBootImages(tenantId: tid)
                        }
                    }
                ),
                placeholder: "区域",
                width: 260,
                allowClear: false
            )
        }
    }

    // MARK: - Template cards

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("规格模板")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visibleTemplates) { tpl in
                        templateCard(tpl)
                    }
                }
            }
        }
    }

    private func templateCard(_ tpl: BootTemplate) -> some View {
        let active = selectedTemplateId == tpl.id
        return Button(action: { applyTemplate(tpl) }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tpl.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(active ? AppTheme.sidebarActive : primaryText)
                    Spacer()
                    Text(tpl.tag)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(tpl.tagDanger ? Color(hex: "f85149") : Color(hex: "3fb950"))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((tpl.tagDanger ? Color(hex: "f85149") : Color(hex: "3fb950")).opacity(0.12))
                        .cornerRadius(4)
                }
                specLine("OCPU", tpl.ocpu)
                specLine("内存", "\(tpl.memory) GB")
                specLine("磁盘", "\(tpl.disk) GB")
            }
            .padding(12)
            .frame(width: 148)
            .background(active
                ? AppTheme.sidebarActive.opacity(0.08)
                : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                active ? AppTheme.sidebarActive.opacity(0.6) : border.opacity(0.4), lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func specLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(mutedText)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).foregroundColor(primaryText)
        }
    }

    // MARK: - Config section

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("部署配置")

            // Specs
            card {
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel("规格")
                    HStack(spacing: 12) {
                        numField("OCPU", text: $model.bootOcpu, width: 80)
                        numField("内存 (GB)", text: $model.bootMemory, width: 80)
                        numField("磁盘 (GB)", text: $model.bootDisk, width: 80)
                    }
                }
            }

            // Loop interval
            card {
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel("循环间隔 (秒)")
                    HStack(spacing: 6) {
                        ForEach(intervalPresets, id: \.0) { label, val in
                            presetButton(label: label, value: val, binding: $model.bootLoopTime)
                        }
                    }
                    AppTextField(text: $model.bootLoopTime, placeholder: "自定义秒数")
                        .frame(width: 160)
                }
            }

            // Instance count + dayGap
            card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 20) {
                        numField("实例数量", text: $model.bootCount, width: 100)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("时段限制 dayGap").font(.system(size: 11, weight: .semibold)).foregroundColor(mutedText)
                            AppTextField(text: $model.bootDayGap, placeholder: "如 0-8（可选）")
                                .frame(width: 160)
                            Text("格式：起始小时-结束小时，如 0-8 表示凌晨 0 点到 8 点运行")
                                .font(.system(size: 10))
                                .foregroundColor(mutedText)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Image section

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("镜像与访问")

            card {
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel("Root 密码")
                    HStack(spacing: 8) {
                        AppTextField(text: $model.bootRootPassword, placeholder: "root 密码")
                            .frame(maxWidth: .infinity)
                        Button(action: { model.bootRootPassword = randomPassword() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundColor(mutedText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("重新生成随机密码")
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel("操作系统")
                    if model.bootOSList.isEmpty {
                        HStack(spacing: 6) {
                            if model.bootImages.isEmpty {
                                ProgressView().scaleEffect(0.65)
                            }
                            Text(model.bootImages.isEmpty ? "加载镜像中…" : "暂无可用镜像")
                                .font(.system(size: 12))
                                .foregroundColor(mutedText)
                        }
                        .frame(height: 32)
                    } else {
                        SelectMenu(
                            options: model.bootOSList.map { SelectOption(id: $0, title: $0) },
                            selection: Binding(
                                get: { model.bootSelectedOS.isEmpty ? nil : model.bootSelectedOS },
                                set: { if let v = $0 { model.applyBootOS(v) } }
                            ),
                            placeholder: "选择操作系统",
                            width: 280,
                            allowClear: false
                        )
                    }
                    if !model.bootVersions.isEmpty {
                        rowLabel("系统版本")
                        SelectMenu(
                            options: model.bootVersions.map {
                                SelectOption(id: $0.operatingSystemVersion, title: $0.operatingSystemVersion)
                            },
                            selection: Binding(
                                get: { model.bootSelectedVersion.isEmpty ? nil : model.bootSelectedVersion },
                                set: { if let v = $0 { model.applyBootVersion(v) } }
                            ),
                            placeholder: "选择版本",
                            width: 280,
                            allowClear: false
                        )
                    }
                }
            }
            .zIndex(1)

            // Image ID display
            card {
                VStack(alignment: .leading, spacing: 6) {
                    rowLabel("Image ID")
                    Text(model.bootImageId.isEmpty ? "— 请先选择操作系统和版本" : model.bootImageId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(model.bootImageId.isEmpty ? mutedText : primaryText)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func applyTemplate(_ tpl: BootTemplate) {
        selectedTemplateId = tpl.id
        model.bootOcpu = tpl.ocpu
        model.bootMemory = tpl.memory
        model.bootDisk = tpl.disk
    }

    private func randomPassword() -> String {
        let chars = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#")
        return String((0..<16).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(primaryText)
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(mutedText)
    }

    private func numField(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(mutedText)
            AppTextField(text: text, placeholder: label).frame(width: width)
        }
    }

    private func presetButton(label: String, value: String, binding: Binding<String>) -> some View {
        let active = binding.wrappedValue == value
        return Button(action: { binding.wrappedValue = value }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(active ? AppTheme.sidebarActive : mutedText)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? AppTheme.sidebarActive.opacity(0.12) : panelBg)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                    active ? AppTheme.sidebarActive.opacity(0.5) : border.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(panelBg)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(border.opacity(0.4), lineWidth: 1))
            )
    }
}
