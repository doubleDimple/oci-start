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

    // Tokens
    private var accent: Color { AppTheme.sidebarActive }
    private var primaryText: Color { dark ? Color(hex: "e8eef4") : Color(hex: "1a202c") }
    private var mutedText: Color { dark ? Color(hex: "8892a4") : Color(hex: "64748b") }
    private var surface: Color { dark ? Color(hex: "22262b") : Color.white }
    private var surface2: Color { dark ? Color(hex: "292d32") : Color(hex: "f8fafc") }
    private var border: Color { dark ? Color(hex: "31363d") : Color(hex: "dde3ec") }
    private var freeTag: Color { Color(hex: "3fb950") }
    private var paidTag: Color { Color(hex: "f78166") }

    @State private var selectedTemplateId: String = "arm-base"

    private var visibleTemplates: [BootTemplate] {
        bootTemplates.filter { $0.arch == model.bootArchitecture }
    }

    private let templateColumns = [
        GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 12)
    ]

    var body: some View {
        PageScaffold(
            title: "创建开机任务",
            subtitle: tenant.map { "\($0.displayName) · \($0.region.isEmpty ? "—" : $0.region)" },
            systemImage: "play.circle.fill",
            toolbar: { toolbar },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        archSection
                            .zIndex(3)
                        templateSection
                            .zIndex(2)
                        HStack(alignment: .top, spacing: 16) {
                            configSection
                            imageSection
                        }
                        .zIndex(1)
                    }
                    .padding(20)
                    .frame(maxWidth: 1080, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
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

    // MARK: - 1. Architecture + Region

    private var archSection: some View {
        formSection(title: "架构与区域", icon: "cpu") {
            VStack(alignment: .leading, spacing: 16) {
                // Architecture segmented control
                HStack(spacing: 0) {
                    ForEach(["ARM", "AMD", "X86"], id: \.self) { arch in
                        archSegment(arch)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(surface2)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1))
                )
                .frame(maxWidth: 360)

                if !model.bootRegionOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("部署区域")
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
                            placeholder: "选择区域租户",
                            width: 320,
                            allowClear: false
                        )
                    }
                }
            }
        }
    }

    private func archSegment(_ arch: String) -> some View {
        let active = model.bootArchitecture == arch
        let subtitle: String = {
            switch arch {
            case "ARM": return "AArch64"
            case "AMD": return "x86-64"
            default: return "x86-64"
            }
        }()
        return Button(action: {
            guard model.bootArchitecture != arch else { return }
            model.bootArchitecture = arch
            if let first = bootTemplates.first(where: { $0.arch == arch }) {
                applyTemplate(first)
            }
            Task {
                let tid = Int64(model.bootSelectedRegionTenantId) ?? (tenant?.id ?? 0)
                await model.loadBootImages(tenantId: tid)
            }
        }) {
            VStack(spacing: 2) {
                Text(arch)
                    .font(.system(size: 13, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.75)
            }
            .foregroundColor(active ? .white : mutedText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeOut(duration: 0.15), value: active)
    }

    // MARK: - 2. Templates

    private var templateSection: some View {
        formSection(title: "规格模板", icon: "square.grid.2x2", trailing: {
            Text("点击卡片快速填充规格")
                .font(.system(size: 11))
                .foregroundColor(mutedText)
        }) {
            LazyVGrid(columns: templateColumns, spacing: 12) {
                ForEach(visibleTemplates) { tpl in
                    templateCard(tpl)
                }
            }
        }
    }

    private func templateCard(_ tpl: BootTemplate) -> some View {
        let active = selectedTemplateId == tpl.id
        let tagColor = tpl.tagDanger ? paidTag : freeTag
        return Button(action: { applyTemplate(tpl) }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(tpl.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(active ? accent : primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(accent)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    specRow(icon: "cpu", text: "\(tpl.ocpu) OCPU")
                    specRow(icon: "rectangle.stack", text: "\(tpl.memory) GB 内存")
                    specRow(icon: "externaldrive", text: "\(tpl.disk) GB 磁盘")
                }

                Text(tpl.tag)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tagColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tagColor.opacity(0.14))
                    .cornerRadius(4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? accent.opacity(dark ? 0.10 : 0.06) : surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? accent : border, lineWidth: active ? 1.5 : 1)
            )
            .shadow(color: active ? accent.opacity(0.18) : Color.black.opacity(dark ? 0.2 : 0.04),
                    radius: active ? 8 : 2, y: active ? 2 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeOut(duration: 0.15), value: active)
    }

    private func specRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(accent.opacity(0.85))
                .frame(width: 12)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(mutedText)
        }
    }

    // MARK: - 3. Deploy config

    private var configSection: some View {
        formSection(title: "部署配置", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 18) {
                // Specs row
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("计算规格")
                    HStack(spacing: 10) {
                        numField("OCPU", text: $model.bootOcpu)
                        numField("内存 (GB)", text: $model.bootMemory)
                        numField("磁盘 (GB)", text: $model.bootDisk)
                    }
                }

                Divider().background(border.opacity(0.6))

                // Interval
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("循环间隔")
                    HStack(spacing: 6) {
                        ForEach(intervalPresets, id: \.0) { label, val in
                            presetChip(label: label, value: val, binding: $model.bootLoopTime)
                        }
                    }
                    HStack(spacing: 8) {
                        AppTextField(text: $model.bootLoopTime, placeholder: "自定义秒数")
                            .frame(width: 140)
                        Text("秒")
                            .font(.system(size: 12))
                            .foregroundColor(mutedText)
                    }
                }

                Divider().background(border.opacity(0.6))

                // Count + dayGap
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("实例数量")
                        AppTextField(text: $model.bootCount, placeholder: "1")
                            .frame(width: 100)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("时段限制 (可选)")
                        AppTextField(text: $model.bootDayGap, placeholder: "如 0-8")
                            .frame(maxWidth: .infinity)
                        Text("起始小时-结束小时，仅在该时段内抢机")
                            .font(.system(size: 10))
                            .foregroundColor(mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 4. Image & access

    private var imageSection: some View {
        formSection(title: "镜像与访问", icon: "desktopcomputer") {
            VStack(alignment: .leading, spacing: 18) {
                // Root password
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Root 密码")
                    HStack(spacing: 8) {
                        AppTextField(text: $model.bootRootPassword, placeholder: "root 登录密码")
                            .frame(maxWidth: .infinity)
                        Button(action: { model.bootRootPassword = randomPassword() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(mutedText)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(surface2)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("重新生成随机密码")
                    }
                }

                Divider().background(border.opacity(0.6))

                // OS
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("操作系统")
                    if model.bootOSList.isEmpty {
                        HStack(spacing: 8) {
                            if model.bootImages.isEmpty {
                                ProgressView().scaleEffect(0.65)
                            } else {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(mutedText)
                            }
                            Text(model.bootImages.isEmpty ? "加载镜像中…" : "暂无可用镜像")
                                .font(.system(size: 12))
                                .foregroundColor(mutedText)
                        }
                        .frame(height: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(surface2)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1))
                        )
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
                }

                // Version
                if !model.bootVersions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("系统版本")
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

                Divider().background(border.opacity(0.6))

                // Image ID
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Image ID")
                    Text(model.bootImageId.isEmpty ? "请先选择操作系统和版本" : model.bootImageId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(model.bootImageId.isEmpty ? mutedText : primaryText)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(surface2)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1))
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared chrome

    private func formSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        formSection(title: title, icon: icon, trailing: { EmptyView() }, content: content)
    }

    private func formSection<Content: View, Trailing: View>(
        title: String,
        icon: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 22, height: 22)
                    .background(accent.opacity(0.12))
                    .cornerRadius(6)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryText)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
                .shadow(color: Color.black.opacity(dark ? 0.25 : 0.05), radius: 6, y: 2)
        )
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(mutedText)
    }

    private func numField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(mutedText)
            AppTextField(text: text, placeholder: "0")
        }
        .frame(maxWidth: .infinity)
    }

    private func presetChip(label: String, value: String, binding: Binding<String>) -> some View {
        let active = binding.wrappedValue == value
        return Button(action: { binding.wrappedValue = value }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(active ? .white : mutedText)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(active ? accent : surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(active ? accent : border, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
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
}
