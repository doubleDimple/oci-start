import SwiftUI
import AppKit

/// Lightweight list shell for Big Sur (header + rows). Prefer over macOS-12-only Table.
struct DataList<Header: View, Content: View>: View {
    var minimumWidth: CGFloat = 0
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        GeometryReader { geometry in
            NativeHorizontalTable(
                contentWidth: max(minimumWidth, geometry.size.width),
                viewportWidth: geometry.size.width,
                height: geometry.size.height
            ) {
                table
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header()
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AppTheme.cardBg(dark))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(AppTheme.border(dark).opacity(0.5)),
                alignment: .bottom
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    content()
                }
            }
        }
    }
}

struct DataListRow<Content: View>: View {
    @State private var hovered = false
    var isSelected: Bool = false
    let action: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    init(isSelected: Bool = false, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? AppTheme.sidebarActive.opacity(0.18)
                    : (hovered ? AppTheme.hover(dark) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovered = $0 }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.35)),
            alignment: .bottom
        )
    }
}

struct DataListColumnHeader: View {
    let title: String
    var width: CGFloat? = nil
    var alignment: Alignment = .leading

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        Text(title)
            .font(.system(size: AppTheme.bodySize, weight: .medium))
            .foregroundColor(AppTheme.textSecondary(dark))
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .help(title)
            .nativeTableHeader(title)
    }
}

/// One horizontal viewport contains the fixed header and independently scrolling
/// rows. Reserve space for its scrollbar so the last row stays above pagination.
struct NativeHorizontalTable<Content: View>: View {
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    let height: CGFloat
    @ViewBuilder var content: () -> Content

    private var overflows: Bool { contentWidth > viewportWidth + 0.5 }
    private var scrollbarHeight: CGFloat {
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    var body: some View {
        Group {
            if overflows {
                ScrollView(.horizontal, showsIndicators: true) {
                    content()
                        .frame(width: contentWidth, height: max(0, height - scrollbarHeight), alignment: .topLeading)
                        .background(NativeTableScrollConfiguration())
                }
                .frame(width: max(0, viewportWidth), height: max(0, height), alignment: .topLeading)
            } else {
                content()
                    .frame(width: max(0, viewportWidth), height: max(0, height), alignment: .topLeading)
            }
        }
        .accessibilityIdentifier("table.horizontal.viewport")
    }
}

/// SwiftUI's overlay scroller can be invisible until a gesture starts. Wide
/// tables keep a native scrollbar visible so mouse users can reach every column.
private struct NativeTableScrollConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> NativeTableScrollConfigurationView {
        NativeTableScrollConfigurationView()
    }

    func updateNSView(_ view: NativeTableScrollConfigurationView, context: Context) {
        view.configureScroll()
    }

    static func dismantleNSView(_ view: NativeTableScrollConfigurationView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class NativeTableScrollConfigurationView: NSView {
    private var configurationQueued = false
    private weak var horizontalScroll: NSScrollView?
    private var wheelMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopMonitoring() } else { configureScroll() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureScroll()
    }

    override func layout() {
        super.layout()
        configureScroll()
    }

    func configureScroll() {
        guard !configurationQueued else { return }
        configurationQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.configurationQueued = false
            guard self.window != nil else { return }
            var ancestor = self.superview
            while let view = ancestor {
                if let scroll = view as? NSScrollView, scroll.hasHorizontalScroller {
                    if scroll.scrollerStyle != .legacy { scroll.scrollerStyle = .legacy }
                    if scroll.autohidesScrollers { scroll.autohidesScrollers = false }
                    self.horizontalScroll = scroll
                    self.startMonitoring()
                    return
                }
                ancestor = view.superview
            }
        }
    }

    private func startMonitoring() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.routeHorizontalWheel(event) == true ? nil : event
        }
    }

    /// Big Sur's inner vertical SwiftUI scroll view consumes horizontal wheel
    /// events. Route only this table's horizontal gestures before that happens.
    private func routeHorizontalWheel(_ event: NSEvent) -> Bool {
        guard let scroll = horizontalScroll, let window = window, let root = window.contentView,
              window.isVisible, !isHiddenOrHasHiddenAncestor, let document = scroll.documentView else { return false }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let delta: CGFloat
        if abs(dx) > abs(dy) { delta = dx }
        else if event.modifierFlags.contains(.shift), abs(dx) < 0.01 { delta = dy }
        else { return false }
        guard abs(delta) > 0.001 else { return false }

        let location: NSPoint
        if let eventWindow = event.window {
            guard eventWindow === window else { return false }
            location = event.locationInWindow
        } else {
            // AppKit reports screen coordinates for events without a window.
            // Require the actual frontmost window at that point to be ours.
            let screenPoint = event.locationInWindow
            guard NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0) == window.windowNumber else { return false }
            location = window.convertPoint(fromScreen: screenPoint)
        }
        let clip = scroll.contentView
        guard clip.bounds.contains(clip.convert(location, from: nil)) else { return false }
        let hitPoint = root.convert(root.convert(location, from: nil), to: root.superview)
        guard let hit = root.hitTest(hitPoint), hit === scroll || hit.isDescendant(of: scroll) else { return false }
        let limit = max(document.bounds.minX, document.bounds.maxX - clip.bounds.width)
        guard limit > document.bounds.minX + 0.5 else { return false }
        let distance = event.hasPreciseScrollingDeltas ? delta : delta * scroll.horizontalLineScroll
        let x = min(limit, max(document.bounds.minX, clip.bounds.minX - distance))
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
        scroll.reflectScrolledClipView(clip)
        return true
    }

    func stopMonitoring() {
        if let monitor = wheelMonitor { NSEvent.removeMonitor(monitor) }
        wheelMonitor = nil
        horizontalScroll = nil
    }

    deinit { if let monitor = wheelMonitor { NSEvent.removeMonitor(monitor) } }
}

extension View {
    @ViewBuilder func nativeTableHeader(_ title: String) -> some View {
        #if DEBUG
        self.background(NativeTableHeaderProbe(title: title))
        #else
        self
        #endif
    }
}

#if DEBUG
struct NativeTableHeaderSnapshot {
    let title: String
    let frameInWindow: NSRect
}

@MainActor
enum NativeTableDiagnostics {
    static func headers(in view: NSView) -> [NativeTableHeaderSnapshot] {
        var result: [NativeTableHeaderSnapshot] = []
        if let header = view as? NativeTableHeaderProbeView, !header.isHiddenOrHasHiddenAncestor {
            result.append(NativeTableHeaderSnapshot(title: header.title, frameInWindow: header.convert(header.bounds, to: nil)))
        }
        for child in view.subviews { result.append(contentsOf: headers(in: child)) }
        return result
    }
}

private struct NativeTableHeaderProbe: NSViewRepresentable {
    let title: String
    func makeNSView(context: Context) -> NativeTableHeaderProbeView { NativeTableHeaderProbeView() }
    func updateNSView(_ view: NativeTableHeaderProbeView, context: Context) { view.title = title }
}

private final class NativeTableHeaderProbeView: NSView {
    var title = ""
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
