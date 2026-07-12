import SwiftUI
import AppKit

struct InstanceDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let instance: OciInstance

    @State private var showConsole = false
    @State private var toolPath: ToolNav?
    @State private var editName = ""
    @State private var editRemark = ""
    @State private var showRename = false
    @State private var showRemark = false
    @State private var showTerminate = false

    private struct ToolNav: Identifiable {
        let id = UUID()
        let title: String
        let path: String
    }

    private var ociId: String { instance.instanceId ?? instance.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(AppTheme.border(scheme))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    infoGroup("网络信息", icon: "network") {
                        infoGrid([
                            ("公网 IP", instance.displayPublicIP),
                            ("私网 IP", instance.privateIps ?? "—"),
                            ("IPv6", (instance.ipv6Addresses?.isEmpty == false) ? instance.ipv6Addresses! : "未启用"),
                        ])
                    }
                    infoGroup("实例规格", icon: "cpu") {
                        infoGrid([
                            ("Shape", instance.shape ?? "—"),
                            ("CPU", instance.ocpus.map { "\($0) vCPU" } ?? "—"),
                            ("内存", instance.memoryInGBs.map { "\($0) GB" } ?? "—"),
                            ("系统盘", instance.bootVolumeSizeInGBs.map { "\($0) GB" } ?? "—"),
                            ("架构", instance.architecture ?? "—"),
                            ("配置", instance.displayShape),
                        ])
                    }
                    infoGroup("位置信息", icon: "mappin.circle") {
                        infoGrid([
                            ("区域", instance.regionName ?? "—"),
                            ("可用域", instance.availabilityDomain ?? "—"),
                            ("租户", instance.displayTenant),
                            ("备注", instance.remark ?? "—"),
                        ])
                    }
                    infoGroup("监控状态", icon: "chart.bar") {
                        infoGrid([
                            ("在线状态", instance.onLineEnable == 1 ? "在线" : "离线"),
                            ("Ping 监控", instance.enablePing == 1 ? "已启用" : "未启用"),
                            ("延迟", instance.connTime.map { $0 > 0 ? "\($0) ms" : "—" } ?? "—"),
                        ])
                    }
                    if let created = instance.timeCreated {
                        infoGroup("时间", icon: "clock") {
                            infoGrid([("创建时间", String(created.prefix(19)))])
                        }
                    }

                    // Power
                    actionSection("电源", icon: "bolt.fill") {
                        HStack(spacing: 10) {
                            if instance.isStopped {
                                actionBtn("启动", icon: "play.fill", color: AppTheme.success) {
                                    Task {
                                        await appState.startInstance(ociId)
                                        dismiss.wrappedValue.dismiss()
                                    }
                                }
                            } else if instance.isRunning {
                                actionBtn("停止", icon: "stop.fill", color: AppTheme.warning) {
                                    Task {
                                        await appState.stopInstance(ociId)
                                        dismiss.wrappedValue.dismiss()
                                    }
                                }
                            }
                            actionBtn("终止…", icon: "xmark.octagon", color: AppTheme.danger) {
                                showTerminate = true
                            }
                        }
                    }

                    // Network ops
                    actionSection("网络", icon: "wifi") {
                        HStack(spacing: 10) {
                            actionBtn("换 IP", icon: "arrow.2.circlepath", color: AppTheme.accent(scheme)) {
                                Task {
                                    await appState.changeIP(instance.id)
                                    dismiss.wrappedValue.dismiss()
                                }
                            }
                            actionBtn("IPv6", icon: "globe", color: AppTheme.cyan) {
                                Task { await appState.enableIpv6(instance.id) }
                            }
                            actionBtn("复制 IP", icon: "doc.on.doc", color: AppTheme.muted(scheme)) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(instance.displayPublicIP, forType: .string)
                                appState.showToast("IP 已复制")
                            }
                            actionBtn("VNIC", icon: "network", color: AppTheme.accent(scheme)) {
                                toolPath = ToolNav(title: "网络管理", path: "/oci/vnic/manage?instanceId=\(ociId)")
                            }
                        }
                    }

                    // Meta
                    actionSection("信息", icon: "pencil") {
                        HStack(spacing: 10) {
                            actionBtn("改名", icon: "pencil", color: AppTheme.accent(scheme)) {
                                editName = instance.displayName ?? ""
                                showRename = true
                            }
                            actionBtn("备注", icon: "text.bubble", color: AppTheme.accent(scheme)) {
                                editRemark = instance.remark ?? ""
                                showRemark = true
                            }
                        }
                    }

                    // Tools
                    actionSection("终端 / 救援", icon: "terminal") {
                        HStack(spacing: 10) {
                            actionBtn("VNC", icon: "display", color: .purple) { showConsole = true }
                            actionBtn("SSH", icon: "terminal.fill", color: AppTheme.text(scheme)) {
                                toolPath = ToolNav(title: "SSH 终端", path: "/oci/terminal?instanceId=\(ociId)")
                            }
                            actionBtn("系统救援", icon: "lifepreserver", color: AppTheme.warning) {
                                toolPath = ToolNav(title: "系统救援", path: "/oci/sysHelp?instanceId=\(ociId)")
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(AppTheme.pageBg(scheme))
        }
        .frame(width: 600, height: 640)
        .background(AppTheme.surface(scheme))
        .sheet(isPresented: $showConsole) {
            EmbeddedPageSheet(title: "VNC — \(instance.displayName ?? "")",
                              path: "/oci/console/terminal/\(ociId)")
                .environmentObject(appState)
        }
        .sheet(item: $toolPath) { t in
            EmbeddedPageSheet(title: t.title, path: t.path)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showTerminate) {
            TerminateInstanceSheet(instance: instance)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showRename) {
            editSheet(title: "修改实例名称", text: $editName, placeholder: "新名称") {
                let id = ociId
                let name = editName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                await appState.updateInstanceName(id, newName: name)
                showRename = false
            }
        }
        .sheet(isPresented: $showRemark) {
            editSheet(title: "修改备注", text: $editRemark, placeholder: "备注内容") {
                await appState.updateInstanceRemark(ociId, remark: editRemark)
                showRemark = false
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(instance.displayName ?? "实例详情")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppTheme.text(scheme))
                HStack(spacing: 6) {
                    Circle().fill(stateColor).frame(width: 8, height: 8)
                    Text(instance.state ?? "—")
                        .font(.caption)
                        .foregroundColor(AppTheme.muted(scheme))
                }
            }
            Spacer()
            Button(action: { dismiss.wrappedValue.dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(AppTheme.muted(scheme))
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(AppTheme.surface(scheme))
    }

    private var stateColor: Color {
        switch instance.state?.uppercased() {
        case "RUNNING": return AppTheme.success
        case "STOPPED": return AppTheme.danger
        default: return AppTheme.warning
        }
    }

    private func infoGroup<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        GroupBox {
            content().padding(4)
        } label: {
            Label(title, systemImage: icon)
                .foregroundColor(AppTheme.text(scheme))
        }
    }

    private func actionSection<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        GroupBox {
            content().padding(4)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func infoGrid(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.0) { kv in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kv.0).font(.caption).foregroundColor(AppTheme.muted(scheme))
                    Text(kv.1).font(.callout).foregroundColor(AppTheme.text(scheme))
                }
            }
        }
    }

    private func actionBtn(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .foregroundColor(color)
    }

    private func editSheet(title: String, text: Binding<String>, placeholder: String, onSave: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundColor(AppTheme.text(scheme))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") {
                    if title.contains("名称") { showRename = false } else { showRemark = false }
                }
                Button("保存") { Task { await onSave() } }
                    .buttonStyle(ProminentButton())
                    .keyboardShortcut(.return)
            }
        }
        .padding(22)
        .frame(width: 360)
    }
}
