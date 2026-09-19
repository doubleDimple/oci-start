import AppKit
import Foundation

/// Called by the isolated QA executable while the populated tenants page is visible.
/// Checks geometry and event delivery without opening a menu or invoking a row action.
@MainActor
func verifyTenantFixedActions(in container: NSView) async throws {
    container.layoutSubtreeIfNeeded()
    guard let window = container.window, let hitRoot = window.contentView else {
        throw TableFixtureFailure("The tenant table is not attached to a window.")
    }
    let buttons = tableFixtureDescendants(of: container).compactMap { $0 as? NSButton }.filter {
        $0.title == "···" && $0.action == NSSelectorFromString("toggleMenu:")
            && !$0.isHiddenOrHasHiddenAncestor
    }
    let candidates = buttons.compactMap { button -> (NSButton, NSScrollView)? in
        guard let scroll = tableFixtureHorizontalScroll(containing: button),
              let document = scroll.documentView,
              document.bounds.width > scroll.contentView.bounds.width + 1 else { return nil }
        let frame = button.convert(button.bounds, to: container)
        let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: container)
        // Pick a mounted row that intersects the table vertically. Horizontal
        // visibility is asserted below, so an offscreen action cannot be skipped.
        guard frame.height > 0, frame.maxY > viewport.minY, frame.minY < viewport.maxY else { return nil }
        return (button, scroll)
    }
    guard let (button, scroll) = candidates.first, let document = scroll.documentView else {
        throw TableFixtureFailure("No populated tenant row with a horizontally overflowing table was found.")
    }

    let clip = scroll.contentView
    let originalOrigin = clip.bounds.origin
    let firstX = document.bounds.minX
    let lastX = max(firstX, document.bounds.maxX - clip.bounds.width)
    let tolerance: CGFloat = 1
    var referenceX: CGFloat?
    var samples: [String] = []

    do {
        let fractions: [CGFloat] = [0, 0.5, 1]
        for fraction in fractions {
            let x = firstX + (lastX - firstX) * fraction
            clip.scroll(to: NSPoint(x: x, y: originalOrigin.y))
            scroll.reflectScrolledClipView(clip)
            try await tableFixtureSettle(container)

            guard abs(clip.bounds.origin.x - x) <= tolerance else {
                throw TableFixtureFailure("The horizontal table did not reach \(Int(fraction * 100))%: expected \(x), got \(clip.bounds.origin.x).")
            }
            guard button.window === window, button.isDescendant(of: container), !button.isHiddenOrHasHiddenAncestor else {
                throw TableFixtureFailure("The same tenant action button was removed or hidden while scrolling.")
            }
            let headerHeight = try tableFixtureHeaderHeight(rowButton: button, tableScroll: scroll, in: container)
            let frame = button.convert(button.bounds, to: container)
            let viewport = clip.convert(clip.bounds, to: container).intersection(container.bounds)
            guard frame.width > 0, frame.height > 0,
                  frame.minX >= viewport.minX - tolerance, frame.maxX <= viewport.maxX + tolerance,
                  frame.midY >= viewport.minY, frame.midY <= viewport.maxY else {
                throw TableFixtureFailure("Tenant actions are outside the table viewport at \(Int(fraction * 100))%: button \(frame), viewport \(viewport).")
            }
            if let initialX = referenceX {
                guard abs(frame.midX - initialX) <= tolerance else {
                    throw TableFixtureFailure("Tenant actions moved horizontally at \(Int(fraction * 100))%: expected x \(initialX), got \(frame.midX).")
                }
            } else { referenceX = frame.midX }

            // NSView.hitTest takes its point in the receiver's superview coordinates.
            // Start at the real window content so an overlaid catcher cannot pass.
            let localCenter = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
            let hitPoint = button.convert(localCenter, to: hitRoot.superview)
            guard let hit = hitRoot.hitTest(hitPoint), hit === button || hit.isDescendant(of: button) else {
                throw TableFixtureFailure("Tenant action hit testing is blocked at \(Int(fraction * 100))% horizontal scroll.")
            }
            samples.append("\(Int(fraction * 100))%: x=\(String(format: "%.2f", Double(frame.midX))), header=\(String(format: "%.2f", Double(headerHeight)))")
        }
    } catch {
        clip.scroll(to: originalOrigin)
        scroll.reflectScrolledClipView(clip)
        try? await tableFixtureSettle(container)
        throw error
    }

    clip.scroll(to: originalOrigin)
    scroll.reflectScrolledClipView(clip)
    try await tableFixtureSettle(container)
    guard abs(clip.bounds.origin.x - originalOrigin.x) <= tolerance,
          abs(clip.bounds.origin.y - originalOrigin.y) <= tolerance else {
        throw TableFixtureFailure("The tenant table's original scroll position was not restored.")
    }
    print("PASS: tenant trailing actions stay fixed and hit-testable (\(samples.joined(separator: ", "))); scroll position restored")
}

private struct TableFixtureFailure: LocalizedError {
    let detail: String
    init(_ detail: String) { self.detail = detail }
    var errorDescription: String? { detail }
}

@MainActor
private func tableFixtureDescendants(of view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { tableFixtureDescendants(of: $0) }
}

@MainActor
private func tableFixtureHorizontalScroll(containing view: NSView) -> NSScrollView? {
    var ancestor = view.superview
    while let current = ancestor {
        if let scroll = current as? NSScrollView, let document = scroll.documentView,
           document.bounds.width > scroll.contentView.bounds.width + 1 {
            return scroll
        }
        ancestor = current.superview
    }
    return nil
}

@MainActor
private func tableFixtureHeaderHeight(rowButton: NSButton, tableScroll: NSScrollView, in container: NSView) throws -> CGFloat {
    var ancestor = rowButton.superview
    var rowsScroll: NSScrollView?
    while let current = ancestor, current !== tableScroll {
        if let scroll = current as? NSScrollView { rowsScroll = scroll; break }
        ancestor = current.superview
    }
    guard let rows = rowsScroll else {
        throw TableFixtureFailure("The tenant row's inner vertical scroll view was not found.")
    }
    let tableViewport = tableScroll.contentView.convert(tableScroll.contentView.bounds, to: container)
    let rowsViewport = rows.contentView.convert(rows.contentView.bounds, to: container)
    // Both rects use one coordinate system; account for AppKit/hosting flip rules.
    let headerHeight = container.isFlipped
        ? rowsViewport.minY - tableViewport.minY
        : tableViewport.maxY - rowsViewport.maxY
    guard rowsViewport.height > 0, headerHeight >= -1, headerHeight <= 60 else {
        throw TableFixtureFailure("The tenant header expanded or displaced its rows: table-to-row viewport gap is \(headerHeight)pt (expected 0...60pt).")
    }
    return headerHeight
}

@MainActor
private func tableFixtureSettle(_ container: NSView) async throws {
    // Let NSClipView notifications, SwiftUI preferences and the row overlays settle.
    try await Task.sleep(nanoseconds: 200_000_000)
    container.layoutSubtreeIfNeeded()
    container.displayIfNeeded()
    try await Task.sleep(nanoseconds: 50_000_000)
    container.layoutSubtreeIfNeeded()
}
