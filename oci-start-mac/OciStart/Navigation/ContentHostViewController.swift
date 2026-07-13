import AppKit
import Combine

/// Detail pane: swaps child VC when NavigationState.selected changes.
/// Autoresizing only — no Auto Layout (avoids constraint loops with SwiftUI).
final class ContentHostViewController: NSViewController {
    private let session: AppSession
    private let navigation: NavigationState
    private var cancellables = Set<AnyCancellable>()
    private weak var currentChild: NSViewController?
    private var currentNav: NavID?

    init(session: AppSession, navigation: NavigationState) {
        self.session = session
        self.navigation = navigation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        v.wantsLayer = true
        v.autoresizingMask = [.width, .height]
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigation.selectionDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nav in
                self?.replace(with: nav, force: false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ociReloadCurrentPage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, let nav = self.currentNav else { return }
                self.replace(with: nav, force: true)
            }
            .store(in: &cancellables)

        replace(with: navigation.selected, force: true)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let child = currentChild {
            child.view.frame = view.bounds
        }
    }

    private func replace(with nav: NavID, force: Bool) {
        if !force, nav == currentNav { return }
        currentNav = nav

        let child = FeatureRouter.makeViewController(for: nav, session: session, navigation: navigation)

        if let old = currentChild {
            old.view.removeFromSuperview()
            old.removeFromParent()
        }

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = true
        child.view.autoresizingMask = [.width, .height]
        child.view.frame = view.bounds
        view.addSubview(child.view)
        currentChild = child

        view.window?.title = "OCI Start — \(NavigationCatalog.item(for: nav)?.title ?? nav.rawValue)"
    }
}

extension Notification.Name {
    static let ociReloadCurrentPage = Notification.Name("ociReloadCurrentPage")
}
