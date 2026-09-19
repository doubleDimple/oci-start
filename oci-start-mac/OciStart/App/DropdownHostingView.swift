import AppKit
import SwiftUI

/// NSHostingView that is fully click-through when no top-nav dropdown is open.
final class DropdownHostingView: NSHostingView<AnyView> {
    var isInteractive: () -> Bool = { false }
    var shouldPassThrough: (NSPoint) -> Bool = { _ in false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive(), !shouldPassThrough(point) else { return nil }
        return super.hitTest(point)
    }
}
