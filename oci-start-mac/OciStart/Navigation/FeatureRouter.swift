import AppKit
import SwiftUI

enum FeatureRouter {

    static func makeViewController(
        for nav: NavID,
        session: AppSession,
        navigation: NavigationState
    ) -> NSViewController {
        let item = NavigationCatalog.item(for: nav)

        let root: AnyView
        switch nav {
        case .dashboard:
            root = AnyView(
                DashboardView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .regions:
            root = AnyView(
                RegionsView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .speedTest:
            root = AnyView(
                SpeedTestView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .tenants:
            root = AnyView(
                TenantsView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .ai:
            root = AnyView(
                AiModelsView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .vpsList:
            root = AnyView(
                VpsListView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .aiChat:
            root = AnyView(
                AiChatView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .instances:
            root = AnyView(
                InstancesView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .email:
            root = AnyView(
                EmailView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .storage:
            root = AnyView(
                StorageView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .boot:
            root = AnyView(
                BootView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .openLogs:
            root = AnyView(
                OpenLogsView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .ipQuality:
            root = AnyView(
                IpQualityView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .systemLogs:
            root = AnyView(
                SystemLogsView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .settings:
            root = AnyView(
                SecuritySettingsView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .proxyConfig:
            root = AnyView(
                ProxyConfigView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .notify:
            root = AnyView(
                NotifyView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .memo:
            root = AnyView(
                MemoView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .migration:
            root = AnyView(
                MigrationView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .mfa:
            root = AnyView(
                MfaBackupView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .apiTokens:
            root = AnyView(
                ApiTokensView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .keyConfig:
            root = AnyView(
                KeyConfigView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .cloudflare:
            root = AnyView(
                CloudflareView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        case .edgeOne:
            root = AnyView(
                EdgeOneView()
                    .environmentObject(session)
                    .environmentObject(navigation)
                    .environmentObject(AppearanceController.shared)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        default:
            root = AnyView(
                PlaceholderView(
                    nav: nav,
                    title: item?.title ?? nav.rawValue,
                    webPath: item?.webPath ?? ""
                )
                .environmentObject(session)
                .environmentObject(navigation)
                .environmentObject(AppearanceController.shared)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            )
        }

        let host = NSHostingController(rootView: root)
        host.title = item?.title ?? nav.rawValue
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = [.width, .height]
        return host
    }
}
