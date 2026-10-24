import AppKit
import SwiftUI
import Combine

/// Logged-in shell using pure autoresizing layout (no Auto Layout).
/// Top-nav dropdowns render in a full-window overlay so they stay inside the app.
final class MainShellViewController: NSViewController {
    private let session: AppSession
    private let navigation: NavigationState
    private let appearance: AppearanceController
    private let header = HeaderViewModel()
    private let chrome = TopNavChromeState.shared
    private var statusOverlayHost: DropdownHostingView?
    private var dropdownHost: DropdownHostingView?
    private var cancellables = Set<AnyCancellable>()
    private var searchKeyMonitor: Any?

    private var topHost: NSHostingController<AnyView>!
    private var sidebarHost: NSHostingController<AnyView>!
    private var detail: ContentHostViewController!
    private var divider: NSView!

    private let topHeight: CGFloat = AppTheme.topBarHeight
    private let sidebarWidth: CGFloat = AppTheme.sidebarWidth
    private let collapsedSidebarWidth: CGFloat = AppTheme.sidebarCollapsedWidth
    private let dividerWidth: CGFloat = 1

    init(session: AppSession, navigation: NavigationState, appearance: AppearanceController = .shared) {
        self.session = session
        self.navigation = navigation
        self.appearance = appearance
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        v.wantsLayer = true
        v.autoresizingMask = [.width, .height]
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Vue exposes OCI only; a cached hidden provider must not hide its menus.
        if session.cloudProvider != 1 { session.setCloudProvider(1) }

        let top = TopNavView()
            .environmentObject(session)
            .environmentObject(navigation)
            .environmentObject(appearance)
            .environmentObject(header)
            .environmentObject(chrome)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: topHeight, maxHeight: topHeight)
        topHost = NSHostingController(rootView: AnyView(top))

        let sidebarRoot = SidebarView()
            .environmentObject(navigation)
            .environmentObject(session)
            .environmentObject(appearance)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        sidebarHost = NSHostingController(rootView: AnyView(sidebarRoot))

        detail = ContentHostViewController(session: session, navigation: navigation)

        divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor

        addChild(topHost)
        addChild(sidebarHost)
        addChild(detail)

        topHost.view.translatesAutoresizingMaskIntoConstraints = true
        sidebarHost.view.translatesAutoresizingMaskIntoConstraints = true
        detail.view.translatesAutoresizingMaskIntoConstraints = true
        divider.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(topHost.view)
        view.addSubview(sidebarHost.view)
        view.addSubview(divider)
        view.addSubview(detail.view)

        // Full-window dropdown overlay (above content, below toast)
        let overlay = TopNavDropdownOverlay(chrome: chrome, header: header)
            .environmentObject(navigation)
            .environmentObject(session)
            .environmentObject(appearance)
        let drop = DropdownHostingView(rootView: AnyView(overlay))
        drop.isInteractive = { [weak self] in
            guard let self = self else { return false }
            // 语言/用户下拉 或 右侧消息抽屉打开时接收点击
            return self.chrome.open != .none || self.header.showMessages
        }
        drop.shouldPassThrough = { [weak self] point in
            guard let self = self, !self.header.showMessages else { return false }
            // hitTest receives a point in this overlay's superview coordinates.
            // Keep the actual top bar editable/clickable while a dropdown is open.
            return self.topHost.view.frame.contains(point)
        }
        drop.translatesAutoresizingMaskIntoConstraints = true
        drop.autoresizingMask = [.width, .height]
        view.addSubview(drop)
        dropdownHost = drop

        // Loading HUD + error toast (blocks hits only while spinner is visible)
        let status = DropdownHostingView(rootView: AnyView(
            StatusOverlayHost().environmentObject(appearance)
        ))
        status.isInteractive = {
            LoadingHUD.shared.isVisible
        }
        status.translatesAutoresizingMaskIntoConstraints = true
        status.autoresizingMask = [.width, .height]
        status.frame = view.bounds
        view.addSubview(status)
        statusOverlayHost = status

        layoutChildren()
        installSearchShortcut()

        navigation.$sidebarCollapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.layoutChildren()
            }
            .store(in: &cancellables)

        // Close dropdowns / message drawer / 业务窗内菜单 when navigating
        navigation.selectionDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.chrome.close()
                self?.header.closeMessages()
                // 清掉租户/实例/开机操作浮层，避免 catcher 残留挡死下一页
                FloatingMenuDismiss.all()
            }
            .store(in: &cancellables)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutChildren()
    }

    deinit {
        if let searchKeyMonitor = searchKeyMonitor { NSEvent.removeMonitor(searchKeyMonitor) }
    }

    private func installSearchShortcut() {
        guard searchKeyMonitor == nil else { return }
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.view.window, event.window === window,
                  window.isKeyWindow, self.session.isLoggedIn, window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !self.header.showMessages, !LoadingHUD.shared.isVisible else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard (modifiers.contains(.command) || modifiers.contains(.control)), !modifiers.contains(.option),
                  event.charactersIgnoringModifiers?.lowercased() == "k" else { return event }
            if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            self.chrome.focusSearch()
            return nil
        }
    }

    private func layoutChildren() {
        let b = view.bounds
        guard b.width > 1, b.height > 1 else { return }

        let collapsed = navigation.sidebarCollapsed
        let sideW: CGFloat = collapsed ? collapsedSidebarWidth : sidebarWidth
        let bodyH = max(0, b.height - topHeight)
        let bodyY: CGFloat = 0
        let topY = b.height - topHeight

        let detailX = sideW + dividerWidth
        topHost.view.frame = NSRect(x: detailX, y: topY, width: max(0, b.width - detailX), height: topHeight)
        sidebarHost.view.frame = NSRect(x: 0, y: bodyY, width: sideW, height: b.height)

        let divX = sideW
        divider.frame = NSRect(x: divX, y: bodyY, width: dividerWidth, height: b.height)

        detail.view.frame = NSRect(x: detailX, y: bodyY, width: max(0, b.width - detailX), height: bodyH)

        dropdownHost?.frame = b
        statusOverlayHost?.frame = b
    }
}
