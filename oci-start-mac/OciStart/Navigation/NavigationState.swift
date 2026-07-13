import Foundation
import Combine

/// Touched from AppKit + SwiftUI; create/use on main thread only (not type-isolated,
/// avoids AppDelegate property-init MainActor deadlock on Big Sur).
final class NavigationState: ObservableObject {
    static let shared = NavigationState()

    /// Fires after `selected` changes (for AppKit hosts).
    let selectionDidChange = PassthroughSubject<NavID, Never>()

    @Published var selected: NavID = .dashboard {
        didSet {
            guard selected != oldValue else { return }
            selectionDidChange.send(selected)
            // Keep the parent section open for the selected page
            if let section = NavigationCatalog.section(for: selected) {
                expandedSection = section
            }
        }
    }
    @Published var searchText: String = ""
    /// Accordion: at most one first-level section expanded (nil = all collapsed).
    @Published var expandedSection: NavSection? = .service
    @Published var sidebarCollapsed: Bool {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebarCollapsed") }
    }

    private init() {
        sidebarCollapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed")
        // Open only the section of the default page
        expandedSection = NavigationCatalog.section(for: selected) ?? .service
    }

    func select(_ nav: NavID) {
        selected = nav
    }

    /// Click first-level header: open this one and close others; click again to collapse.
    func toggleSection(_ section: NavSection) {
        if expandedSection == section {
            expandedSection = nil
        } else {
            expandedSection = section
        }
    }

    func isSectionExpanded(_ section: NavSection) -> Bool {
        expandedSection == section
    }
}
