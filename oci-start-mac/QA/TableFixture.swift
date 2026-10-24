import AppKit
import Foundation
import SwiftUI
@testable import OciStart

/// Called by the isolated QA executable while the populated tenants page is visible.
/// Checks geometry and event delivery without opening a menu or invoking a row action.
@MainActor
func verifyTenantFixedActions(in container: NSView) async throws {
    container.layoutSubtreeIfNeeded()
    guard let window = container.window, let hitRoot = window.contentView else {
        throw TableFixtureFailure("The tenant table is not attached to a window.")
    }
    let buttons = tableFixtureDescendants(of: container).compactMap { $0 as? NSButton }.filter {
        ($0.accessibilityIdentifier() == "table.row.more" || $0.title == "···")
            && $0.action == NSSelectorFromString("toggleMenu:")
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
        try await tableFixtureWheelToEnd(scroll, in: container, shift: false)
        try await tableFixtureWheelToEnd(scroll, in: container, shift: true)
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

/// Leave a timestamped boundary before/after awaited UI work so a crash can be
/// distinguished from a failed assertion without changing production behavior.
func tableFixtureTrace(_ message: String) {
    fputs("QA STAGE t=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime)) main=\(Thread.isMainThread): \(message)\n", stderr)
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

/// Exercises AppKit event dispatch at a hit-tested row, including scoped native
/// event monitors and its nested scroll views. Only reset uses scroll(to:).
@MainActor
private func tableFixtureWheelToEnd(_ scroll: NSScrollView, in container: NSView, shift: Bool) async throws {
    guard let document = scroll.documentView, let window = container.window, let root = window.contentView else {
        throw TableFixtureFailure("A wheel test requires an attached table document.")
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    try await tableFixtureSettle(container)
    let clip = scroll.contentView
    let first = document.bounds.minX
    let last = document.bounds.maxX - clip.bounds.width
    guard last > first + 1 else { throw TableFixtureFailure("The fixture table has no horizontal overflow.") }
    clip.scroll(to: NSPoint(x: first, y: clip.bounds.minY))
    scroll.reflectScrolledClipView(clip)
    try await tableFixtureSettle(container)
    let inner = tableFixtureDescendants(of: document).compactMap { $0 as? NSScrollView }.first {
        $0 !== scroll && $0.hasVerticalScroller
    }
    guard let rows = inner else { throw TableFixtureFailure("The table has no nested vertical row scroll view.") }
    var delivered = 0
    var lastEvent: NSEvent?
    for _ in 0..<40 {
        let viewport = rows.contentView.convert(rows.contentView.bounds, to: root)
            .intersection(clip.convert(clip.bounds, to: root)).intersection(root.bounds)
        guard viewport.width > 10, viewport.height > 10 else {
            throw TableFixtureFailure("The table row viewport is not visible: \(viewport).")
        }
        let point = NSPoint(x: viewport.midX, y: viewport.midY)
        let eventWindowPoint = root.convert(point, to: nil)
        let eventScreenPoint = window.convertPoint(toScreen: eventWindowPoint)
        let windowAtPoint = NSWindow.windowNumber(at: eventScreenPoint, belowWindowWithWindowNumber: 0)
        if windowAtPoint != window.windowNumber {
            fputs("WHEEL FOCUS RESTORE expected=\(window.windowNumber) actual=\(windowAtPoint) point=\(eventScreenPoint) frame=\(window.frame) atX=\(clip.bounds.minX)\n", stderr)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            try await tableFixtureSettle(container)
            let restoredWindow = NSWindow.windowNumber(at: eventScreenPoint, belowWindowWithWindowNumber: 0)
            guard restoredWindow == window.windowNumber else {
                throw TableFixtureFailure("The isolated wheel target is obscured: expected window \(window.windowNumber), found \(restoredWindow) at \(eventScreenPoint).")
            }
        }
        guard let hit = root.hitTest(root.convert(point, to: root.superview)),
              hit === rows || hit.isDescendant(of: rows) else {
            throw TableFixtureFailure("A view outside the row scroll view intercepts its wheel target.")
        }
        let windowPoint = root.convert(point, to: nil)
        let event = try tableFixtureWheelEvent(in: window, at: windowPoint,
                                               horizontal: shift ? 0 : -120, vertical: shift ? -120 : 0, shift: shift)
        if delivered == 0 {
            let screenPoint = window.convertPoint(toScreen: windowPoint)
            let atPoint = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
            if atPoint != window.windowNumber {
                fputs("WHEEL WINDOW DIAGNOSTIC point=\(screenPoint) frame=\(window.frame) expected=\(window.windowNumber) frontmost=\(atPoint)\n", stderr)
            }
            fputs("WHEEL EVENT TARGET expectedWindow=\(window.windowNumber) actualWindow=\(event.windowNumber) linked=\(event.window === window) windowAtPoint=\(atPoint) expectedPoint=\(windowPoint) actualPoint=\(event.locationInWindow) shift=\(shift) dispatch=NSApp.sendEvent\n", stderr)
        }
        lastEvent = event
        NSApp.sendEvent(event)
        delivered += 1
        try await Task.sleep(nanoseconds: 40_000_000)
        container.layoutSubtreeIfNeeded()
        if clip.bounds.minX >= last - 1 { break }
    }
    try await tableFixtureSettle(container)
    guard abs(clip.bounds.minX - last) <= 1 else {
        let failedOrigin = clip.bounds.origin
        if let event = lastEvent {
            fputs("WHEEL DIAGNOSTIC shift=\(shift) scrollingDelta=(\(event.scrollingDeltaX),\(event.scrollingDeltaY)) delta=(\(event.deltaX),\(event.deltaY)) precise=\(event.hasPreciseScrollingDeltas) windowNumber=\(event.windowNumber) window=\(String(describing: event.window)) sourceX=\(failedOrigin.x) targetX=\(last)\n", stderr)
            // An outer-only attempt is diagnostic, never a substitute for the
            // required row responder path. Preserve the failure and its state.
            scroll.scrollWheel(with: event)
            try await tableFixtureSettle(container)
            fputs("WHEEL DIAGNOSTIC directOuterX=\(clip.bounds.minX) advanced=\(clip.bounds.minX - failedOrigin.x)\n", stderr)
            clip.scroll(to: failedOrigin)
            scroll.reflectScrolledClipView(clip)
            try await tableFixtureSettle(container)
        }
        throw TableFixtureFailure("\(shift ? "Shift + vertical" : "Horizontal") wheel events stopped at x=\(failedOrigin.x); last column requires x=\(last). Nested row scrolling may be swallowing the gesture.")
    }
    guard let scroller = scroll.horizontalScroller, !scroller.isHidden,
          scroll.hasHorizontalScroller, scroller.frame.height > 0 else {
        throw TableFixtureFailure("The overflowing table has no visible horizontal scrollbar.")
    }
    print("PASS: \(shift ? "Shift + vertical" : "horizontal") wheel reaches final column (\(delivered) native events, x=\(Int(last)))")
}

@MainActor
private func tableFixtureWheelEvent(in window: NSWindow, at point: NSPoint,
                                    horizontal: Int32, vertical: Int32, shift: Bool = false) throws -> NSEvent {
    guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                           wheel1: vertical, wheel2: horizontal, wheel3: 0) else {
        throw TableFixtureFailure("Could not construct a native scroll wheel event.")
    }
    if shift { cg.flags = .maskShift }
    let screen = window.convertPoint(toScreen: point)
    let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
    // AppKit screen points have a lower-left origin; Quartz uses the upper left.
    // Both use logical points, so there is no Retina backing-scale conversion.
    cg.location = CGPoint(x: screen.x, y: primaryTop - screen.y)
    guard let event = NSEvent(cgEvent: cg), event.type == .scrollWheel else {
        throw TableFixtureFailure("CGEvent did not produce a native NSEvent.scrollWheel.")
    }
    // On Big Sur this public factory returns a valid native scroll event with
    // window=nil and a screen-space location. Horizontal checks use normal
    // NSApp dispatch and the production monitor's existing window hit test.
    return event
}

/// A vertical-only gesture must remain in the row scroller and must not be
/// reinterpreted as horizontal movement by the wide-table event monitor.
@MainActor
private func tableFixtureVerticalWheel(_ outer: NSScrollView, rows: NSScrollView, in container: NSView) async throws {
    guard let document = rows.documentView, let window = container.window, let root = window.contentView,
          document.bounds.height > rows.contentView.bounds.height + 10 else {
        throw TableFixtureFailure("The vertical wheel fixture requires overflowing rows in an attached window.")
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    try await tableFixtureSettle(container)
    let clip = rows.contentView
    let original = clip.bounds.origin
    let originalOuter = outer.contentView.bounds.origin
    guard let outerDocument = outer.documentView else {
        throw TableFixtureFailure("The vertical wheel fixture lost its horizontal document.")
    }
    let outerFirst = outerDocument.bounds.minX
    let outerLast = max(outerFirst, outerDocument.bounds.maxX - outer.contentView.bounds.width)
    // Use the midpoint so an incorrect horizontal route cannot hide behind
    // clamping at the first or final column. This is setup, never input proof.
    outer.contentView.scroll(to: NSPoint(x: outerFirst + (outerLast - outerFirst) / 2, y: originalOuter.y))
    outer.reflectScrolledClipView(outer.contentView)
    let outerX = outer.contentView.bounds.minX
    clip.scroll(to: NSPoint(x: original.x, y: document.bounds.minY))
    rows.reflectScrolledClipView(clip)
    try await tableFixtureSettle(container)
    let baselineY = clip.bounds.minY
    let visible = clip.convert(clip.bounds, to: root)
        .intersection(outer.contentView.convert(outer.contentView.bounds, to: root)).intersection(root.bounds)
    let point = NSPoint(x: visible.midX, y: visible.midY)
    guard let hit = root.hitTest(root.convert(point, to: root.superview)),
          hit === rows || hit.isDescendant(of: rows) else {
        throw TableFixtureFailure("The vertical wheel target is intercepted outside the row scroller.")
    }
    let event = try tableFixtureWheelEvent(in: window, at: root.convert(point, to: nil), horizontal: 0, vertical: -120)
    let screenPoint = event.window == nil ? event.locationInWindow : window.convertPoint(toScreen: event.locationInWindow)
    fputs("VERTICAL WHEEL TARGET expectedWindow=\(window.windowNumber) actualWindow=\(event.windowNumber) linked=\(event.window === window) windowAtPoint=\(NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)) point=\(event.locationInWindow)\n", stderr)
    // The CGEvent factory does not associate a window, so NSApp cannot do its
    // ordinary NSWindow routing. Check the two contracts explicitly: first the
    // monitor must ignore a vertical gesture; then the actual hit row responder
    // must scroll vertically when given that SAME unmodified native event.
    NSApp.sendEvent(event)
    try await tableFixtureSettle(container)
    let monitorOuterX = outer.contentView.bounds.minX
    let routedY = clip.bounds.minY
    hit.scrollWheel(with: event)
    try await tableFixtureSettle(container)
    let actualY = clip.bounds.minY
    let actualOuterX = outer.contentView.bounds.minX
    clip.scroll(to: original)
    rows.reflectScrolledClipView(clip)
    outer.contentView.scroll(to: originalOuter)
    outer.reflectScrolledClipView(outer.contentView)
    try await tableFixtureSettle(container)
    guard abs(monitorOuterX - outerX) <= 1,
          actualY > baselineY + 10, abs(actualOuterX - outerX) <= 1 else {
        throw TableFixtureFailure("Vertical event contracts failed: NSApp outer x \(outerX) → \(monitorOuterX); native row y \(baselineY) → \(actualY), final outer x \(actualOuterX).")
    }
    print("PASS: vertical monitor ignores gesture + native row scroller handles vertical event (NSApp row y=\(routedY), native row y=\(actualY); synthetic event has no window, so default NSWindow dispatch is not claimed)")
}

/// Read the measured backgrounds of real production header views. Debug probes
/// carry titles and geometry only; no accessibility activation or text inference
/// is needed. Convert both the headers and their viewport to screen points.
private struct TableFixtureText {
    let text: String
    let frame: NSRect
}

@MainActor
private func tableFixtureTexts(in view: NSView, diagnostic: ((String) -> Void)? = nil) -> [TableFixtureText] {
    guard let window = view.window else { return [] }
    return NativeTableDiagnostics.headers(in: view).map { header in
        let frame = window.convertToScreen(header.frameInWindow)
        diagnostic?("HEADER PROBE title=\(header.title.debugDescription) frameInWindow=\(header.frameInWindow) frameInScreen=\(frame)")
        return TableFixtureText(text: header.title, frame: frame)
    }
}

@MainActor
private func tableFixtureScreenRect(_ rect: NSRect, in view: NSView) -> NSRect {
    guard let window = view.window else { return .zero }
    return window.convertToScreen(view.convert(rect, to: nil))
}

/// Used on populated proxy and region pages, independently of the synthetic
/// stress fixture. Its largest overflowing nested table excludes toolbars/maps.
@MainActor
func verifyBusinessTable(in container: NSView, name: String, firstHeader: String, lastHeader: String,
                         headers: [String], capture: () -> Void) async throws {
    let candidates = tableFixtureDescendants(of: container).compactMap { $0 as? NSScrollView }.filter { scroll in
        guard let document = scroll.documentView,
              document.bounds.width > scroll.contentView.bounds.width + 1 else { return false }
        return tableFixtureDescendants(of: document).contains {
            guard let rows = $0 as? NSScrollView else { return false }
            return rows !== scroll && rows.hasVerticalScroller
        }
    }.sorted { $0.bounds.height > $1.bounds.height }
    guard let scroll = candidates.first, let document = scroll.documentView else {
        throw TableFixtureFailure("\(name): populated wide table has no horizontal viewport.")
    }
    let original = scroll.contentView.bounds.origin
    var observed = Set<String>()
    @MainActor func inspectHeader(_ required: String) throws {
        let tableFrame = tableFixtureScreenRect(scroll.contentView.bounds, in: scroll.contentView)
        let allTexts = tableFixtureTexts(in: container)
        let texts = allTexts.filter {
            headers.contains($0.text) && $0.frame.height > 0
                && $0.frame.maxY <= tableFrame.maxY + 1 && $0.frame.minY >= tableFrame.maxY - 60
        }
        for item in texts {
            guard item.frame.height <= 24 else {
                throw TableFixtureFailure("\(name): header ‘\(item.text)’ wraps to \(item.frame.height)pt.")
            }
            observed.insert(item.text)
        }
        guard texts.contains(where: {
            $0.text == required && $0.frame.minX >= tableFrame.minX - 1 && $0.frame.maxX <= tableFrame.maxX + 1
        }) else {
            fputs("TABLE HEADER DIAGNOSTIC \(name) required=\(required) tableScreen=\(tableFrame) window=\(String(describing: container.window?.frame)) backingScale=\(container.window?.backingScaleFactor ?? 0) clipBounds=\(scroll.contentView.bounds)\n", stderr)
            _ = tableFixtureTexts(in: container, diagnostic: { line in
                fputs(line + "\n", stderr)
            })
            throw TableFixtureFailure("\(name): header ‘\(required)’ is not fully reachable within the table viewport.")
        }
    }
    do {
        scroll.contentView.scroll(to: NSPoint(x: document.bounds.minX, y: original.y))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await tableFixtureSettle(container)
        try inspectHeader(firstHeader)
        try await tableFixtureWheelToEnd(scroll, in: container, shift: false)
        try inspectHeader(lastHeader)
        try await tableFixtureWheelToEnd(scroll, in: container, shift: true)
        try inspectHeader(lastHeader)
        capture()
        guard Set(headers).isSubset(of: observed) else {
            throw TableFixtureFailure("\(name): header geometry was missing for \(Set(headers).subtracting(observed).sorted()).")
        }
    } catch {
        scroll.contentView.scroll(to: original)
        scroll.reflectScrolledClipView(scroll.contentView)
        try? await tableFixtureSettle(container)
        throw error
    }
    scroll.contentView.scroll(to: original)
    scroll.reflectScrolledClipView(scroll.contentView)
    try await tableFixtureSettle(container)
    print("PASS: \(name): all \(headers.count) headers single-line; actual wheel reaches last column; scroll restored")
}

private struct TableFixtureMarker: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> TableFixtureMarkerView { TableFixtureMarkerView(name: name) }
    func updateNSView(_ view: TableFixtureMarkerView, context: Context) {}
}

private final class TableFixtureMarkerView: NSView {
    let name: String
    init(name: String) { self.name = name; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Uses real shared components with long English content and geometry-only
/// background probes. Controls are inert and every row is local fixture data.
private struct TableStressPreview: View {
    let width: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            AdaptiveListToolbar(availableWidth: width) {
                AppTextField(text: .constant(""), placeholder: "Search by tenancy name or resource identifier", leadingSystemImage: "magnifyingglass")
                    .frame(width: 270).background(TableFixtureMarker(name: "adaptive.search"))
                Text("All availability domains").frame(width: 180)
            } actions: {
                AppButton(title: "Refresh monitoring information", kind: .secondary) {}
                    .background(TableFixtureMarker(name: "adaptive.action"))
            }
            FilterBar {
                AppTextField(text: .constant(""), placeholder: "Search resources", leadingSystemImage: "magnifyingglass")
                    .frame(width: 270).background(TableFixtureMarker(name: "filter.search"))
                Text("All regions and architectures").frame(width: 210)
            } trailing: {
                AppButton(title: "Create new resource configuration", kind: .primary) {}
                    .background(TableFixtureMarker(name: "filter.action"))
            }
            DataList(minimumWidth: 1388) {
                ForEach(0..<8, id: \.self) { column in
                    DataListColumnHeader(title: "Very long English column title \(column + 1)", width: 170)
                        .background(TableFixtureMarker(name: "header.\(column)"))
                }
            } content: {
                ForEach(0..<20, id: \.self) { row in
                    DataListRow {
                        ForEach(0..<8, id: \.self) { column in
                            Text("Resource \(row + 1), column \(column + 1)")
                                .lineLimit(1).frame(width: 170, alignment: .leading)
                                .background(TableFixtureMarker(name: "row.\(row).\(column)"))
                        }
                    }
                }
            }
        }.environmentObject(AppearanceController.shared)
    }
}

@MainActor
func verifySharedTableLayout(captureDirectory: String) async throws {
    let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 640, height: 500),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let originalLevel = window.level
    window.level = .floating
    let host = NSHostingView(rootView: TableStressPreview(width: 640))
    window.contentView = host
    window.orderFront(nil)
    @MainActor func marker(_ name: String) throws -> NSView {
        guard let result = tableFixtureDescendants(of: host).compactMap({ $0 as? TableFixtureMarkerView }).first(where: { $0.name == name }) else {
            throw TableFixtureFailure("Shared table geometry probe ‘\(name)’ is missing.")
        }
        return result
    }
    do {
        let widths: [CGFloat] = [640, 900]
        for width in widths {
            host.rootView = TableStressPreview(width: width)
            window.setContentSize(NSSize(width: width, height: 500))
            try await tableFixtureSettle(host)
            for prefix in ["adaptive", "filter"] {
                let search = try marker(prefix + ".search")
                let action = try marker(prefix + ".action")
                let searchFrame = search.convert(search.bounds, to: host)
                let actionFrame = action.convert(action.bounds, to: host)
                guard abs(searchFrame.midY - actionFrame.midY) <= 1,
                      searchFrame.height > 0, actionFrame.height > 0 else {
                    throw TableFixtureFailure("\(prefix) search/actions wrap at \(Int(width))pt: \(searchFrame), \(actionFrame).")
                }
            }
            for column in 0..<8 {
                let header = try marker("header.\(column)")
                guard header.bounds.height > 0, header.bounds.height <= 24 else {
                    throw TableFixtureFailure("Long English header \(column) wraps at \(Int(width))pt: \(header.bounds.height)pt.")
                }
            }
            let lastCell = try marker("row.0.7")
            guard let scroll = tableFixtureHorizontalScroll(containing: lastCell) else {
                throw TableFixtureFailure("The shared eight-column DataList has no horizontal scroll view.")
            }
            try await tableFixtureWheelToEnd(scroll, in: host, shift: false)
            try await tableFixtureWheelToEnd(scroll, in: host, shift: true)
            let lastHeader = try marker("header.7")
            let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: host)
            for item in [lastHeader, lastCell] {
                let frame = item.convert(item.bounds, to: host)
                guard frame.minX >= viewport.minX - 1, frame.maxX <= viewport.maxX + 1 else {
                    throw TableFixtureFailure("The final DataList column is clipped after native wheel scrolling at \(Int(width))pt.")
                }
            }
            let rows = tableFixtureDescendants(of: scroll).compactMap { $0 as? NSScrollView }.first { $0 !== scroll && $0.hasVerticalScroller }
            guard let vertical = rows, let document = vertical.documentView else {
                throw TableFixtureFailure("The DataList lost its independent vertical scroll view.")
            }
            try await tableFixtureVerticalWheel(scroll, rows: vertical, in: host)
            let savedVerticalOrigin = vertical.contentView.bounds.origin
            let before = lastHeader.convert(lastHeader.bounds, to: host)
            vertical.contentView.scroll(to: NSPoint(x: 0, y: min(100, max(0, document.bounds.height - vertical.contentView.bounds.height))))
            vertical.reflectScrolledClipView(vertical.contentView)
            try await tableFixtureSettle(host)
            let after = lastHeader.convert(lastHeader.bounds, to: host)
            guard abs(before.midY - after.midY) <= 1 else {
                throw TableFixtureFailure("The DataList header moves with its vertical rows.")
            }
            // Reset the setup-only scroll before reusing this LazyVStack at the
            // next width; otherwise row zero is legitimately unmounted.
            vertical.contentView.scroll(to: savedVerticalOrigin)
            vertical.reflectScrolledClipView(vertical.contentView)
            try await tableFixtureSettle(host)
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw TableFixtureFailure("No table screenshot data.") }
                try png.write(to: URL(fileURLWithPath: captureDirectory).appendingPathComponent("table-stress-\(Int(width))-last-column.png"))
            }
            print("PASS: \(Int(width))pt DataList: English headers stay single-line, both toolbars stay on one row, last header/cell visible, header stays fixed vertically")
        }
    } catch { window.orderOut(nil); window.level = originalLevel; throw error }
    window.orderOut(nil)
    window.level = originalLevel
}

/// Old macOS 11 concurrency runtimes can crash while starting the nested globe
/// Task from a delayed callback. Keep this UI lifecycle check on the main run
/// loop, with the same measured animation assertions and no Swift concurrency.
@MainActor
func verifyLoginGlobeAnimation(in container: NSView, capture: @escaping (String) -> Void,
                               completion: @escaping (Result<Void, Error>) -> Void) {
    LoginGlobeFixture(container: container, capture: capture, completion: completion).start()
}

@MainActor
private final class LoginGlobeFixture {
    private let container: NSView
    private let capture: (String) -> Void
    private let completion: (Result<Void, Error>) -> Void
    private var finished = false
    private var movingBaseline: LoginGlobeAnimationSnapshot?
    private var pausedBaseline: LoginGlobeAnimationSnapshot?
    private var hiddenBaseline: LoginGlobeAnimationSnapshot?

    init(container: NSView, capture: @escaping (String) -> Void,
         completion: @escaping (Result<Void, Error>) -> Void) {
        self.container = container
        self.capture = capture
        self.completion = completion
    }

    func start() {
        tableFixtureTrace("globe callback verification entry")
        do {
            let initial = try sample("before any diagnostic override")
            if !initial.reducedMotion {
                try require(initial.timerRunning && initial.frameCount > 0,
                            "The visible globe did not start animating before the diagnostic override.")
            }
            try require(LoginGlobeDiagnostics.setReducedMotionOverride(false, in: container),
                        "The rendered login globe diagnostic view is missing.")
            after(0.25, "capture initial movement baseline") {
                self.movingBaseline = try self.sample("motion baseline")
                self.capture("login-globe-motion-start")
                self.after(0.5, "verify automatic movement") { try self.checkMovement() }
            }
            // Hold the state machine until every stage completes; finish is
            // idempotent and the watchdog never touches a completed window.
            after(15, "watchdog") {
                throw TableFixtureFailure("The globe callback verification did not complete.")
            }
        } catch { finish(.failure(error)) }
    }

    private func checkMovement() throws {
        guard let first = movingBaseline else { throw TableFixtureFailure("Missing globe motion baseline.") }
        let moving = try sample("movement wait complete")
        try require(first.timerRunning && moving.timerRunning && moving.frameCount > first.frameCount
                    && moving.elapsed > first.elapsed && abs(moving.rotationY - first.rotationY) > 0.0001,
                    "The visible globe's actual timer/frame/rotation did not advance.")
        capture("login-globe-motion-later")
        tableFixtureTrace("globe movement verified; applying reduced motion")
        LoginGlobeDiagnostics.setReducedMotionOverride(true, in: container)
        after(0.25, "record reduced-motion pause") {
            self.pausedBaseline = try self.sample("reduced-motion baseline")
            self.after(0.3, "verify reduced-motion pause") { try self.checkReducedMotion() }
        }
    }

    private func checkReducedMotion() throws {
        guard let paused = pausedBaseline else { throw TableFixtureFailure("Missing globe reduced-motion baseline.") }
        let still = try sample("reduced-motion wait complete")
        try require(paused.reducedMotion && !paused.timerRunning && !still.timerRunning
                    && still.frameCount == paused.frameCount && still.elapsed == paused.elapsed
                    && still.rotationY == paused.rotationY && still.rotationX == paused.rotationX,
                    "Reduced motion did not pause the actual globe timer and rotation.")
        LoginGlobeDiagnostics.setReducedMotionOverride(false, in: container)
        after(0.3, "verify motion resumes") {
            let resumed = try self.sample("motion resumed")
            try self.require(resumed.timerRunning && resumed.frameCount > still.frameCount
                             && resumed.elapsed > still.elapsed && resumed.rotationY != still.rotationY,
                             "The globe did not resume after reduced motion was disabled.")
            guard let window = self.container.window else { throw TableFixtureFailure("The globe window was detached.") }
            tableFixtureTrace("globe ordering window out")
            window.orderOut(nil)
            self.after(0.25, "record hidden-window pause") {
                self.hiddenBaseline = try self.sample("hidden-window baseline")
                self.after(0.3, "verify hidden-window pause") { try self.checkHiddenWindow() }
            }
        }
    }

    private func checkHiddenWindow() throws {
        guard let hidden = hiddenBaseline else { throw TableFixtureFailure("Missing globe hidden-window baseline.") }
        let still = try sample("hidden-window wait complete")
        try require(!hidden.timerRunning && !still.timerRunning && still.frameCount == hidden.frameCount
                    && still.elapsed == hidden.elapsed && still.rotationY == hidden.rotationY
                    && still.rotationX == hidden.rotationX,
                    "The globe kept animating while its window was hidden.")
        guard let window = container.window else { throw TableFixtureFailure("The globe window was detached.") }
        tableFixtureTrace("globe ordering window front")
        window.orderFront(nil)
        after(0.3, "verify visible-window recovery") {
            let visible = try self.sample("visible-window recovery")
            try self.require(visible.timerRunning && visible.frameCount > still.frameCount
                             && visible.elapsed > still.elapsed && visible.rotationY != still.rotationY,
                             "The globe did not resume when its window became visible.")
            self.capture("login-globe-motion-resumed")
            self.finish(.success(()))
        }
    }

    private func after(_ delay: TimeInterval, _ stage: String,
                       _ body: @escaping @MainActor () throws -> Void) {
        tableFixtureTrace("globe scheduling \(stage), delay=\(delay)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard !self.finished else { return }
            precondition(Thread.isMainThread)
            tableFixtureTrace("globe callback: \(stage)")
            do {
                self.container.layoutSubtreeIfNeeded()
                self.container.displayIfNeeded()
                try body()
            } catch { self.finish(.failure(error)) }
        }
    }

    private func sample(_ stage: String) throws -> LoginGlobeAnimationSnapshot {
        container.layoutSubtreeIfNeeded()
        guard let state = LoginGlobeDiagnostics.snapshot(in: container) else {
            throw TableFixtureFailure("The rendered globe diagnostic view is missing at \(stage).")
        }
        tableFixtureTrace("globe \(stage): frames=\(state.frameCount) elapsed=\(state.elapsed) timer=\(state.timerRunning) rotationY=\(state.rotationY) reducedMotion=\(state.reducedMotion) pause=\(state.pauseReason ?? "none")")
        return state
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw TableFixtureFailure(message) }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        container.window?.orderFront(nil)
        LoginGlobeDiagnostics.setReducedMotionOverride(nil, in: container)
        tableFixtureTrace("globe callback verification complete; window/override restored")
        if case .success = result {
            print("PASS: rendered globe frame/rotation advances, reduced motion pauses/resumes, hidden window pauses/resumes; timed screenshots captured")
        }
        completion(result)
    }
}
