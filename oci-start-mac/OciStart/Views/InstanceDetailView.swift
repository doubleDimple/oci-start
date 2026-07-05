import SwiftUI
import AppKit

struct InstanceDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var dismiss
    let instance: OciInstance
    @State private var showConsole = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.displayName ?? "实例详情")
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 6) {
                        Circle().fill(stateColor).frame(width: 8, height: 8)
                        Text(instance.state ?? "—").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { dismiss.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary).font(.title3)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Network
                    infoGroup("网络信息", icon: "network") {
                        infoGrid([
                            ("公网 IP",  instance.displayPublicIP),
                            ("私网 IP",  instance.privateIps ?? "—"),
                            ("IPv6",     (instance.ipv6Addresses?.isEmpty == false) ? instance.ipv6Addresses! : "未启用"),
                        ])
                    }

                    // Compute
                    infoGroup("实例规格", icon: "cpu") {
                        infoGrid([
                            ("Shape",       instance.shape ?? "—"),
                            ("CPU",         instance.ocpus.map { "\($0) vCPU" } ?? "—"),
                            ("内存",        instance.memoryInGBs.map { "\($0) GB" } ?? "—"),
                            ("系统盘",      instance.bootVolumeSizeInGBs.map { "\($0) GB" } ?? "—"),
                            ("架构",        instance.architecture ?? "—"),
                            ("CPU/内存",    instance.displayShape),
                        ])
                    }

                    // Location
                    infoGroup("位置信息", icon: "mappin.circle") {
                        infoGrid([
                            ("区域",        instance.regionName ?? "—"),
                            ("可用域",      instance.availabilityDomain ?? "—"),
                            ("租户",        instance.displayTenant),
                            ("备注",        instance.remark ?? "—"),
                        ])
                    }

                    // Monitoring
                    infoGroup("监控状态", icon: "chart.bar") {
                        infoGrid([
                            ("在线状态",    instance.onLineEnable == 1 ? "在线" : "离线"),
                            ("Ping 监控",   instance.enablePing == 1 ? "已启用" : "未启用"),
                            ("延迟",        instance.connTime.map { $0 > 0 ? "\($0) ms" : "—" } ?? "—"),
                        ])
                    }

                    // Time
                    if let created = instance.timeCreated {
                        infoGroup("时间", icon: "clock") {
                            infoGrid([("创建时间", String(created.prefix(19)))])
                        }
                    }

                    // Actions
                    GroupBox {
                        HStack(spacing: 12) {
                            if instance.isStopped {
                                actionBtn("启动", icon: "play.fill", color: .green) {
                                    Task {
                                        await appState.startInstance(instance.instanceId ?? instance.id)
                                        dismiss.wrappedValue.dismiss()
                                    }
                                }
                            } else if instance.isRunning {
                                actionBtn("停止", icon: "stop.fill", color: .orange) {
                                    Task {
                                        await appState.stopInstance(instance.instanceId ?? instance.id)
                                        dismiss.wrappedValue.dismiss()
                                    }
                                }
                            }
                            actionBtn("换 IP", icon: "arrow.2.circlepath", color: .blue) {
                                Task {
                                    await appState.changeIP(instance.id)
                                    dismiss.wrappedValue.dismiss()
                                }
                            }
                            actionBtn("复制 IP", icon: "doc.on.doc", color: .secondary) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(instance.displayPublicIP, forType: .string)
                                appState.showToast("IP 已复制")
                            }
                            actionBtn("VNC 控制台", icon: "display", color: .purple) {
                                showConsole = true
                            }
                        }
                    } label: {
                        Label("操作", systemImage: "gearshape.2")
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 560, height: 580)
        .sheet(isPresented: $showConsole) {
            let path = "/oci/console/terminal/\(instance.instanceId ?? instance.id)"
            EmbeddedPageSheet(title: "VNC 控制台 — \(instance.displayName ?? "")", path: path)
                .environmentObject(appState)
        }
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch instance.state?.uppercased() {
        case "RUNNING":  return .green
        case "STOPPED":  return .red
        default:         return .orange
        }
    }

    private func infoGroup<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
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
                    Text(kv.0).font(.caption).foregroundColor(.secondary)
                    Text(kv.1).font(.callout)
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
}
