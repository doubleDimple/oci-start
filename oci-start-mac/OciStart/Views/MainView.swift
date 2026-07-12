import SwiftUI

// MARK: - Navigation (must match Web sidebar.ftl structure & items)

enum Nav: String, Hashable, CaseIterable {
    // 服务管理 — order mirrors sidebar.ftl
    case dashboard      = "系统监控"
    case armRecords     = "OCI 区域"
    case tenants        = "OCI 租户"
    case instances      = "OCI 实例"
    case email          = "邮件管理"
    case objectStorage  = "对象存储"
    case fullBootList   = "一键开机"
    case aiModels       = "OCI AI管理"
    case speedTest      = "延迟测试"
    case bootLog        = "开机日志"
    case gcpAccounts    = "GCP 账号"
    case otherInstances = "GCP 实例"
    case azureVms       = "Azure 虚拟机"
    case azureResources = "Azure 资源"
    case azureStorage   = "Azure 存储"
    case azureNetworks  = "Azure 网络"
    case awsEc2         = "AWS EC2"
    case awsS3          = "AWS S3"
    case awsLambda      = "AWS Lambda"
    case awsRds         = "AWS RDS"
    // 代理管理
    case domainSettings = "密钥配置"
    case cloudflare     = "Cloudflare"
    case edgeone        = "EdgeOne"
    // VPS
    case vpsMonitor     = "实例列表"
    // 系统管理
    case ipSettings     = "质量检测"
    case sysLog         = "系统日志"
    case settings       = "安全管理"
    case vpnProxy       = "代理配置"
    // 我的工具
    case notifications  = "通知管理"
    case memo           = "笔记管理"
    case migration      = "数据迁移"
    case mfaBackup      = "MFA 备份"
    // 开发者
    case apiToken       = "Token 配置"

    var icon: String {
        switch self {
        case .dashboard:        return "chart.pie.fill"
        case .armRecords:       return "globe"
        case .tenants:          return "person.2.fill"
        case .instances:        return "server.rack"
        case .email:            return "envelope.fill"
        case .objectStorage:    return "externaldrive.fill"
        case .fullBootList:     return "play.circle.fill"
        case .aiModels:         return "cpu"
        case .speedTest:        return "gauge"
        case .bootLog:          return "doc.text.magnifyingglass"
        case .gcpAccounts:      return "person.crop.circle"
        case .otherInstances:   return "cloud"
        case .azureVms:         return "desktopcomputer"
        case .azureResources:   return "square.stack.3d.up"
        case .azureStorage:     return "externaldrive"
        case .azureNetworks:    return "network"
        case .awsEc2:           return "server.rack"
        case .awsS3:            return "icloud"
        case .awsLambda:        return "function"
        case .awsRds:           return "cylinder"
        case .domainSettings:   return "key.fill"
        case .cloudflare:       return "shield.lefthalf.fill"
        case .edgeone:          return "globe"
        case .vpsMonitor:       return "list.bullet"
        case .ipSettings:       return "checkmark.shield"
        case .sysLog:           return "doc.text"
        case .settings:         return "slider.horizontal.3"
        case .vpnProxy:         return "arrow.triangle.branch"
        case .notifications:    return "bell.fill"
        case .memo:             return "book"
        case .migration:        return "arrow.left.arrow.right"
        case .mfaBackup:        return "lock.shield.fill"
        case .apiToken:         return "key.fill"
        }
    }

    var searchKeywords: String { "\(rawValue) \(icon)" }
}

private struct NavSection: Identifiable {
    let id: String
    let title: String
    let items: [Nav]
}

/// Exactly aligned with oci-server/.../sidebar.ftl section order & entries
private let navSections: [NavSection] = [
    NavSection(id: "service", title: "服务管理", items: [
        .dashboard, .armRecords, .tenants, .instances, .email,
        .objectStorage, .fullBootList, .aiModels, .speedTest, .bootLog,
        .gcpAccounts, .otherInstances,
        .azureVms, .azureResources, .azureStorage, .azureNetworks,
        .awsEc2, .awsS3, .awsLambda, .awsRds
    ]),
    NavSection(id: "proxy", title: "代理管理", items: [
        .domainSettings, .cloudflare, .edgeone
    ]),
    NavSection(id: "vps", title: "VPS管理", items: [
        .vpsMonitor
    ]),
    NavSection(id: "system", title: "系统管理", items: [
        .ipSettings, .sysLog, .settings, .vpnProxy
    ]),
    NavSection(id: "tools", title: "我的工具", items: [
        .notifications, .memo, .migration, .mfaBackup
    ]),
    NavSection(id: "dev", title: "开发者配置", items: [
        .apiToken
    ]),
]

// MARK: - Main shell

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var sidebarCollapsed = false
    @State private var expandedSections: Set<String> = Set(navSections.map(\.id))

    private var selectionBinding: Binding<Nav?> {
        Binding(
            get: { appState.selectedNav },
            set: { appState.selectedNav = $0 }
        )
    }

    private var filteredSections: [NavSection] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return navSections }
        return navSections.compactMap { section in
            let items = section.items.filter {
                $0.rawValue.lowercased().contains(q) || $0.searchKeywords.lowercased().contains(q)
            }
            return items.isEmpty ? nil : NavSection(id: section.id, title: section.title, items: items)
        }
    }

    var body: some View {
        NavigationView {
            sidebar
            detailView(for: appState.selectedNav ?? .dashboard)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.pageBg(scheme).ignoresSafeArea())
                .id(appState.selectedNav)
        }
        .frame(minWidth: 1020, minHeight: 640)
        .overlay(toastOverlay, alignment: .bottom)
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
        .onAppear {
            // Map legacy nav raw values if needed
            if appState.selectedNav == nil { appState.selectedNav = .dashboard }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            if !sidebarCollapsed {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.muted(scheme))
                        .font(.system(size: 12))
                    TextField("搜索菜单…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppTheme.muted(scheme))
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.elevated(scheme)))
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            List(selection: selectionBinding) {
                ForEach(filteredSections) { section in
                    Section(header: sectionHeader(section)) {
                        if searchText.isEmpty ? expandedSections.contains(section.id) : true {
                            ForEach(section.items, id: \.self) { item in
                                Label {
                                    if !sidebarCollapsed {
                                        Text(item.rawValue).font(.system(size: 13))
                                    }
                                } icon: {
                                    Image(systemName: item.icon).font(.system(size: 12))
                                }
                                .tag(item)
                                .help(item.rawValue)
                            }
                        }
                    }
                }
                if filteredSections.isEmpty {
                    Text("无匹配菜单")
                        .font(.caption)
                        .foregroundColor(AppTheme.muted(scheme))
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                if !sidebarCollapsed {
                    Text("OCI-START")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.muted(scheme))
                    Spacer()
                }
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { sidebarCollapsed.toggle() }
                }) {
                    Image(systemName: sidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.muted(scheme))
                }
                .buttonStyle(.plain)
                if sidebarCollapsed { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minWidth: sidebarCollapsed ? 56 : 180,
               idealWidth: sidebarCollapsed ? 56 : 200,
               maxWidth: sidebarCollapsed ? 64 : 240)
        .background(AppTheme.surface(scheme))
    }

    private func sectionHeader(_ section: NavSection) -> some View {
        Button(action: {
            if searchText.isEmpty {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedSections.contains(section.id) {
                        expandedSections.remove(section.id)
                    } else {
                        expandedSections.insert(section.id)
                    }
                }
            }
        }) {
            HStack(spacing: 4) {
                if !sidebarCollapsed {
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.muted(scheme))
                    Spacer()
                    if searchText.isEmpty {
                        Image(systemName: expandedSections.contains(section.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let msg = appState.toastMessage {
            AppToastView(message: msg)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(), value: appState.toastMessage)
        }
    }

    // MARK: Detail routing — paths match web sidebar hrefs

    @ViewBuilder
    private func detailView(for nav: Nav) -> some View {
        switch nav {
        // Native
        case .dashboard:        DashboardView()
        case .armRecords:       ArmRecordsView()
        case .tenants:          TenantListView()
        case .gcpAccounts:      TenantListView() // web: same /tenants/list
        case .instances:        InstancesView()
        case .objectStorage:    ObjectStorageView()
        case .fullBootList:     BootTasksView()
        case .vpsMonitor:       VpsMonitorView()
        case .memo:             MemoView()
        case .notifications:    NotificationSettingsView()
        case .apiToken:         ApiTokenView()
        case .settings:         SettingsView()
        case .mfaBackup:        MfaBackupView()
        // Web content pages (sidebar targets)
        case .email:            EmailManageView()
        case .aiModels:         AiModelsHubView()
        case .speedTest:        SpeedTestView()
        case .bootLog:          SystemLogView(isBootLog: true)
        case .otherInstances:   EmbeddedPage(title: "GCP 实例", path: "/other/instances/list")
        case .azureVms:         EmbeddedPage(title: "Azure 虚拟机", path: "/azure/vms")
        case .azureResources:   EmbeddedPage(title: "Azure 资源", path: "/azure/resources")
        case .azureStorage:     EmbeddedPage(title: "Azure 存储", path: "/azure/storage")
        case .azureNetworks:    EmbeddedPage(title: "Azure 网络", path: "/azure/networks")
        case .awsEc2:           EmbeddedPage(title: "AWS EC2", path: "/aws/ec2")
        case .awsS3:            EmbeddedPage(title: "AWS S3", path: "/aws/s3")
        case .awsLambda:        EmbeddedPage(title: "AWS Lambda", path: "/aws/lambda")
        case .awsRds:           EmbeddedPage(title: "AWS RDS", path: "/aws/rds")
        case .domainSettings:   DomainSettingsView()
        case .cloudflare:       CloudflareDnsView()
        case .edgeone:          EdgeOneDnsView()
        case .ipSettings:       IpSettingsView()
        case .sysLog:           SystemLogView(isBootLog: false)
        case .vpnProxy:         VpnProxyView()
        case .migration:        MigrationView()
        }
    }
}

struct ToastView: View {
    let message: String
    var body: some View { AppToastView(message: message) }
}
