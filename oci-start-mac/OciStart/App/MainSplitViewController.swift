import AppKit
import SwiftUI
import Combine

final class MainSplitViewController: NSSplitViewController {
    private let session: AppSession
    private let navigation: NavigationState
    private let appearance = AppearanceController.shared
    private var cancellables = Set<AnyCancellable>()
    private var sidebarItem: NSSplitViewItem!
    private var detailItem: NSSplitViewItem!

    init(session: AppSession, navigation: NavigationState) {
        self.session = session
        self.navigation = navigation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarRoot = SidebarView()
            .environmentObject(navigation)
            .environmentObject(session)
            .environmentObject(appearance)
        let sidebarHost = NSHostingController(rootView: sidebarRoot)

        let detail = ContentHostViewController(session: session, navigation: navigation)

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 280
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = false
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)

        detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 640
        detailItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 250)

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        splitView.dividerStyle = .thin
        // Fresh name so old poisoned MainSplit frames are never applied
        splitView.autosaveName = "OciStart.MainSplit.v3"

        navigation.sidebarCollapsed = false
        sidebarItem.isCollapsed = false

        navigation.$sidebarCollapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] collapsed in
                guard let self = self else { return }
                self.sidebarItem.animator().isCollapsed = collapsed
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        resetSplitPositions()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // If something collapsed the detail to ~0, re-expand
        let total = splitView.bounds.width
        if total > 600, splitView.subviews.count >= 2 {
            let side = splitView.subviews[0].bounds.width
            if side < 160 || side > total - 400 {
                resetSplitPositions()
            }
        }
    }

    private func resetSplitPositions() {
        guard splitView.subviews.count >= 2 else { return }
        let total = splitView.bounds.width
        guard total > 400 else { return }
        let side = min(240, max(200, total * 0.18))
        splitView.setPosition(side, ofDividerAt: 0)
        sidebarItem.isCollapsed = false
        navigation.sidebarCollapsed = false
    }
}
