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
            // Native SwiftUI content in AppKit shell (same path as Dashboard/Regions).
            // WebEmbed only for heavy secondary full pages (boot/region/cost/AI).
            root = AnyView(
                TenantsView()
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
