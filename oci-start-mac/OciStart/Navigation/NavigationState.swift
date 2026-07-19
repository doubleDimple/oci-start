import Foundation
import Combine

/// Cross-page tenant filter when jumping from 租户详情 → 实例列表 / 开机管理.
struct PendingTenantListFilter: Equatable {
    var parentTenantId: String
    var regionTenantId: String
}

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

    /// Consumed once by InstancesViewModel on appear.
    private var pendingInstancesFilter: PendingTenantListFilter?
    /// Consumed once by BootViewModel on appear.
    private var pendingBootFilter: PendingTenantListFilter?
    /// 租户列表「AI」→ AI 对话页预选租户；由 AiChatViewModel 消费一次。
    private var pendingAiChatTenantId: Int64?
    /// 递增以通知已在 AI 对话页时再次切入（同页不重建 VC）。
    @Published private(set) var aiChatOpenToken: Int = 0

    private init() {
        sidebarCollapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed")
        // Open only the section of the default page
        expandedSection = NavigationCatalog.section(for: selected) ?? .service
    }

    func select(_ nav: NavID) {
        selected = nav
    }

    /// 租户详情 → 实例列表（对齐 Web `/oci/list?tenantId=`）
    func openInstances(parentId: String, regionId: String) {
        pendingInstancesFilter = PendingTenantListFilter(
            parentTenantId: parentId,
            regionTenantId: regionId
        )
        select(.instances)
    }

    /// 租户详情 → 开机/抢机任务（对齐 Web `/boot/fullBootList?tenantId=`）
    func openBootTasks(parentId: String, regionId: String) {
        pendingBootFilter = PendingTenantListFilter(
            parentTenantId: parentId,
            regionTenantId: regionId
        )
        select(.boot)
    }

    func takePendingInstancesFilter() -> PendingTenantListFilter? {
        let f = pendingInstancesFilter
        pendingInstancesFilter = nil
        return f
    }

    func takePendingBootFilter() -> PendingTenantListFilter? {
        let f = pendingBootFilter
        pendingBootFilter = nil
        return f
    }

    /// 租户管理「AI」按钮 → 跳转 AI 对话整页并预选该租户（对齐 Web `/ai/chat?tenantId=`）
    func openAiChat(tenantId: Int64) {
        guard tenantId > 0 else {
            select(.aiChat)
            return
        }
        pendingAiChatTenantId = tenantId
        aiChatOpenToken &+= 1
        select(.aiChat)
    }

    func takePendingAiChatTenantId() -> Int64? {
        let id = pendingAiChatTenantId
        pendingAiChatTenantId = nil
        return id
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
