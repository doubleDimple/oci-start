import SwiftUI

enum Nav: String, Hashable {
    // 服务管理
    case dashboard      = "仪表板"
    case armRecords     = "ARM 区域"
    case tenants        = "租户管理"
    case instances      = "OCI 实例"
    case fullBootList   = "一键开机"
    case objectStorage  = "对象存储"
    case aiModels       = "AI 模型"
    case speedTest      = "延迟测试"
    case bootLog        = "开机日志"
    case otherInstances = "其他云实例"
    case ociCost        = "费用分析"
    case ociMonitor     = "流量监控"
    case addBoot        = "添加开机"
    case gcpAddBoot     = "GCP 开机"
    case fullMachineList = "全部机器"
    case speedAdd       = "测速配置"
    // VPS 管理
    case vpsMonitor     = "资源监控"
    // 域名管理
    case domainSettings = "域名配置"
    case cloudflare     = "Cloudflare"
    case edgeone        = "EdgeOne"
    case nginxConfig    = "Nginx 配置"
    // AI 工具
    case aiChat         = "AI 对话"
    // 工具
    case memo           = "便签"
    case sshTerminal    = "SSH 终端"
    case mfaBackup      = "MFA 备份"
    case email          = "邮件管理"
    // 系统管理
    case ipSettings     = "IP 设置"
    case sysLog         = "系统日志"
    case vpnProxy       = "VPN 代理"
    case notifications  = "通知设置"
    case migration      = "数据迁移"
    case apiToken       = "API Token"
    case settings       = "系统设置"
    case tenantRegionList = "租户区域"
    case regionSub      = "区域订阅"
    case networkManage  = "网络管理"
    case sysHelp        = "系统救援"
    case metrics        = "监控管理"

    var icon: String {
        switch self {
        case .dashboard:        return "chart.pie.fill"
        case .armRecords:       return "map"
        case .tenants:          return "person.2.fill"
        case .instances:        return "server.rack"
        case .fullBootList:     return "play.circle.fill"
        case .objectStorage:    return "externaldrive.fill"
        case .aiModels:         return "brain"
        case .speedTest:        return "speedometer"
        case .bootLog:          return "doc.text.magnifyingglass"
        case .otherInstances:   return "cloud"
        case .ociCost:          return "dollarsign.circle"
        case .ociMonitor:       return "chart.line.uptrend.xyaxis"
        case .addBoot:          return "plus.circle.fill"
        case .gcpAddBoot:       return "g.circle.fill"
        case .fullMachineList:  return "list.bullet.rectangle"
        case .speedAdd:         return "speedometer"
        case .vpsMonitor:       return "display.2"
        case .domainSettings:   return "globe"
        case .cloudflare:       return "shield.checkerboard"
        case .edgeone:          return "network"
        case .nginxConfig:      return "server.rack"
        case .aiChat:           return "bubble.left.and.bubble.right.fill"
        case .memo:             return "note.text"
        case .sshTerminal:      return "terminal.fill"
        case .mfaBackup:        return "lock.shield.fill"
        case .email:            return "envelope.fill"
        case .ipSettings:       return "network.badge.shield.half.filled"
        case .sysLog:           return "doc.text"
        case .vpnProxy:         return "arrow.triangle.branch"
        case .notifications:    return "bell.fill"
        case .migration:        return "arrow.left.arrow.right"
        case .apiToken:         return "key.fill"
        case .settings:         return "gear"
        case .tenantRegionList: return "mappin.and.ellipse"
        case .regionSub:        return "map.fill"
        case .networkManage:    return "point.3.connected.trianglepath.dotted"
        case .sysHelp:          return "lifepreserver.fill"
        case .metrics:          return "chart.bar.xaxis"
        }
    }
}

private struct NavSection {
    let title: String
    let items: [Nav]
}

private let navSections: [NavSection] = [
    NavSection(title: "服务管理", items: [
        .dashboard, .armRecords, .tenants, .instances,
        .fullBootList, .addBoot, .gcpAddBoot, .fullMachineList, .speedAdd,
        .objectStorage, .aiModels, .speedTest, .bootLog,
        .otherInstances, .ociCost, .ociMonitor
    ]),
    NavSection(title: "VPS 管理", items: [.vpsMonitor]),
    NavSection(title: "域名管理", items: [.domainSettings, .cloudflare, .edgeone, .nginxConfig]),
    NavSection(title: "AI 工具", items: [.aiChat]),
    NavSection(title: "工具", items: [.memo, .sshTerminal, .mfaBackup, .email]),
    NavSection(title: "系统管理", items: [
        .ipSettings, .sysLog, .vpnProxy, .notifications,
        .migration, .apiToken, .settings,
        .tenantRegionList, .regionSub, .networkManage,
        .sysHelp, .metrics
    ]),
]

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: Nav? = .dashboard

    var body: some View {
        NavigationView {
            sidebar
            detailView(for: selection ?? .dashboard)
        }
        .frame(minWidth: 1020, minHeight: 620)
        .overlay(
            Group {
                if let msg = appState.toastMessage {
                    ToastView(message: msg)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(), value: appState.toastMessage)
                }
            },
            alignment: .bottom
        )
        .alert(isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Alert(
                title: Text("错误"),
                message: Text(appState.errorMessage ?? ""),
                dismissButton: .default(Text("确定")) { appState.errorMessage = nil }
            )
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(navSections, id: \.title) { section in
                Section(header: Text(section.title)) {
                    ForEach(section.items, id: \.self) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 170, maxWidth: 200)
    }

    // MARK: - Detail routing

    @ViewBuilder
    private func detailView(for nav: Nav) -> some View {
        switch nav {
        // Native views
        case .dashboard:        DashboardView()
        case .armRecords:       ArmRecordsView()
        case .tenants:          TenantListView()
        case .instances:        InstancesView()
        case .objectStorage:    ObjectStorageView()
        case .vpsMonitor:       VpsMonitorView()
        case .memo:             MemoView()
        case .notifications:    NotificationSettingsView()
        case .apiToken:         ApiTokenView()
        case .settings:         SettingsView()
        case .mfaBackup:        MfaBackupView()
        // Embedded web pages — 服务管理
        case .fullBootList:     EmbeddedPage(title: "一键开机", path: "/boot/fullBootList")
        case .addBoot:          EmbeddedPage(title: "添加开机", path: "/tenants/bootPage")
        case .gcpAddBoot:       EmbeddedPage(title: "GCP 开机", path: "/tenants/gcpBootPage")
        case .fullMachineList:  EmbeddedPage(title: "全部机器", path: "/tenants/bootList")
        case .speedAdd:         EmbeddedPage(title: "测速配置", path: "/tenants/addSpeed")
        case .aiModels:         EmbeddedPage(title: "AI 模型配置", path: "/system/ai/models")
        case .speedTest:        EmbeddedPage(title: "延迟测试", path: "/delayTest")
        case .bootLog:          EmbeddedPage(title: "开机日志", path: "/system/openLogs")
        case .otherInstances:   EmbeddedPage(title: "其他云实例", path: "/other/instances/list")
        case .ociCost:          EmbeddedPage(title: "费用分析", path: "/cost/costPage")
        case .ociMonitor:       EmbeddedPage(title: "流量监控", path: "/monitor/homePage")
        // Embedded web pages — 域名管理
        case .domainSettings:   EmbeddedPage(title: "域名配置", path: "/system/domainSettings")
        case .cloudflare:       EmbeddedPage(title: "Cloudflare DNS", path: "/dns/cloudflare")
        case .edgeone:          EmbeddedPage(title: "EdgeOne DNS", path: "/dns/edgeone")
        case .nginxConfig:      EmbeddedPage(title: "Nginx 配置", path: "/nginx/management")
        // Embedded web pages — AI / 工具
        case .aiChat:           EmbeddedPage(title: "AI 对话", path: "/ai/chat")
        case .sshTerminal:      EmbeddedPage(title: "SSH 终端", path: "/ssh/terminal")
        case .email:            EmbeddedPage(title: "邮件管理", path: "/email/management")
        // Embedded web pages — 系统管理
        case .ipSettings:       EmbeddedPage(title: "IP 设置", path: "/system/ipSettings")
        case .sysLog:           EmbeddedPage(title: "系统日志", path: "/main?path=/system/logs&active=api-logs")
        case .vpnProxy:         EmbeddedPage(title: "VPN 代理", path: "/vpnProxy/page")
        case .migration:        EmbeddedPage(title: "数据迁移", path: "/migration/migPage")
        case .tenantRegionList: EmbeddedPage(title: "租户区域", path: "/tenants/regionList")
        case .regionSub:        EmbeddedPage(title: "区域订阅", path: "/tenants/regionSubList")
        case .networkManage:    EmbeddedPage(title: "网络管理", path: "/oci/vnic/manage")
        case .sysHelp:          EmbeddedPage(title: "系统救援", path: "/oci/sysHelp")
        case .metrics:          EmbeddedPage(title: "监控管理", path: "/oci/metricsPage")
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
