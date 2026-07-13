import AppKit
import SwiftUI

/// NSHostingView that is fully click-through when no top-nav dropdown is open.
final class DropdownHostingView: NSHostingView<AnyView> {
    var isInteractive: () -> Bool = { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive() else { return nil }
        return super.hitTest(point)
    }
}
