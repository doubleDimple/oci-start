import AppKit
import SwiftUI
import Combine

/// Never allow layout passes to collapse the window into a thin strip.
final class ClampedWindow: NSWindow {
    var clampMinSize = NSSize(width: 960, height: 640)
    /// When true, ignore size reductions from content (still allow user resize above min).
    private var isApplyingProgrammaticFrame = false

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if isApplyingProgrammaticFrame {
            super.setFrame(frameRect, display: flag)
            return
        }
        super.setFrame(Self.clamped(frameRect, min: clampMinSize), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        if isApplyingProgrammaticFrame {
            super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
            return
        }
        super.setFrame(Self.clamped(frameRect, min: clampMinSize), display: displayFlag, animate: animateFlag)
    }

    func setFrameProgrammatic(_ frameRect: NSRect, display: Bool) {
        isApplyingProgrammaticFrame = true
        setFrame(Self.clamped(frameRect, min: clampMinSize), display: display, animate: false)
        isApplyingProgrammaticFrame = false
    }

    static func clamped(_ rect: NSRect, min minSize: NSSize) -> NSRect {
        var r = rect
        r.size.width = max(r.size.width, minSize.width)
        r.size.height = max(r.size.height, minSize.height)
        return r
    }
}

final class MainWindowController: NSWindowController {
    private let session: AppSession
    private let navigation: NavigationState
    private let backend: BackendController
    private let appearance: AppearanceController
    private var cancellables = Set<AnyCancellable>()
    private let root = RootContainerViewController()

    static let defaultSize = NSSize(width: 1280, height: 800)
    static let minSize = NSSize(width: 960, height: 640)

    init(
        session: AppSession,
        navigation: NavigationState,
        backend: BackendController,
        appearance: AppearanceController = .shared
    ) {
        self.session = session
        self.navigation = navigation
        self.backend = backend
        self.appearance = appearance

        Self.clearPoisonedFrameDefaults()

        let window = ClampedWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.clampMinSize = Self.minSize
        window.title = "OCI Start"
        window.minSize = Self.minSize
        window.contentMinSize = Self.minSize
        window.maxSize = NSSize(width: 50_000, height: 50_000)
        window.contentMaxSize = NSSize(width: 50_000, height: 50_000)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbar = nil
        window.setFrameAutosaveName("")

        super.init(window: window)

        // Plain contentView + root.view (autoresizing). Avoid contentViewController + AL thrash.
        let container = NSView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]
        window.contentView = container

        root.view.frame = container.bounds
        root.view.autoresizingMask = [.width, .height]
        container.addSubview(root.view)

        window.delegate = self
        forceDefaultFrame()
        rebuildContent()
        bindSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        forceDefaultFrame()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func forceDefaultFrame() {
        guard let window = window as? ClampedWindow else {
            guard let window = window else { return }
            window.minSize = Self.minSize
            window.contentMinSize = Self.minSize
            let screen = window.screen ?? NSScreen.main
            let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let w = min(Self.defaultSize.width, max(Self.minSize.width, vis.width - 60))
            let h = min(Self.defaultSize.height, max(Self.minSize.height, vis.height - 60))
            let x = vis.midX - w / 2
            let y = vis.midY - h / 2
            window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: false)
            return
        }
        window.minSize = Self.minSize
        window.contentMinSize = Self.minSize

        let screen = window.screen ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = min(Self.defaultSize.width, max(Self.minSize.width, vis.width - 60))
        let h = min(Self.defaultSize.height, max(Self.minSize.height, vis.height - 60))
        let x = vis.midX - w / 2
        let y = vis.midY - h / 2
        window.setFrameProgrammatic(NSRect(x: x, y: y, width: w, height: h), display: true)
        AppDelegate.log("forceDefaultFrame → \(NSStringFromRect(window.frame))")
    }

    func applyStandardFrame(force: Bool) {
        guard let window = window else { return }
        if force {
            forceDefaultFrame()
            return
        }
        let f = window.frame
        if f.width < Self.minSize.width || f.height < Self.minSize.height {
            forceDefaultFrame()
        }
    }

    private func bindSession() {
        session.$isLoggedIn
            .dropFirst() // init already rebuildContent()'d once
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Defer off the current runloop / constraint pass to avoid AL thrash crash.
                DispatchQueue.main.async {
                    self?.rebuildContent()
                    self?.forceDefaultFrame()
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildContent() {
        if session.isLoggedIn {
            let shell = MainShellViewController(
                session: session,
                navigation: navigation,
                appearance: appearance
            )
            root.setContent(shell)
            window?.title = "OCI Start"
        } else {
            let login = LoginView()
                .environmentObject(session)
                .environmentObject(backend)
                .environmentObject(appearance)
            root.setSwiftUI(login)
            window?.title = "OCI Start — 登录"
        }
        // Single delayed pin after content swap — do NOT spam forceDefaultFrame (causes constraint storms).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.applyStandardFrame(force: false)
        }
    }

    static func clearPoisonedFrameDefaults() {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix("NSWindow Frame")
                || key.hasPrefix("NSSplitView Subview Frames")
                || key.contains("OciStartMainWindow")
                || key.contains("MainSplit")
                || key.contains("SidebarNavigationView")
                || key.contains("AppWindow") {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.synchronize()
        AppDelegate.log("cleared poisoned window/split frame defaults")
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, Self.minSize.width),
            height: max(frameSize.height, Self.minSize.height)
        )
    }
}
