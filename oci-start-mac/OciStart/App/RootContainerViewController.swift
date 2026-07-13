import AppKit
import SwiftUI

/// Fills the window. Children fill via autoresizing only — no Auto Layout.
/// Mixing AL + NSHostingView.updateConstraints caused infinite constraint loops
/// on macOS 11 ("more Update Constraints in Window passes than views").
final class RootContainerViewController: NSViewController {
    private var current: NSViewController?

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        v.wantsLayer = true
        v.autoresizingMask = [.width, .height]
        view = v
    }

    func setContent(_ child: NSViewController) {
        if let old = current {
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        addChild(child)
        // Autoresizing fill only — never AL on hosting views here.
        child.view.translatesAutoresizingMaskIntoConstraints = true
        child.view.autoresizingMask = [.width, .height]
        child.view.frame = view.bounds
        view.addSubview(child.view)
        current = child
    }

    func setSwiftUI<Content: View>(_ root: Content) {
        let filled = root
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        let host = NSHostingController(rootView: filled)
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = [.width, .height]
        setContent(host)
    }
}

/// Always click-through — legacy helper (status overlay now uses DropdownHostingView).
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}
