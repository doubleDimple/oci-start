import SwiftUI
import AppKit

// MARK: - Exclusive open

private final class SelectMenuCoordinator {
    static let shared = SelectMenuCoordinator()
    private var openId: UUID?
    private var closeHandlers: [UUID: () -> Void] = [:]

    func register(_ id: UUID, close: @escaping () -> Void) {
        closeHandlers[id] = close
    }

    func unregister(_ id: UUID) {
        closeHandlers.removeValue(forKey: id)
        if openId == id { openId = nil }
    }

    func requestOpen(_ id: UUID) {
        if let prev = openId, prev != id {
            closeHandlers[prev]?()
        }
        openId = id
    }

    func didClose(_ id: UUID) {
        if openId == id { openId = nil }
    }
}

// MARK: - Panel / open state (reference type — safe from detached hosting view)

private final class SelectMenuPanelState: ObservableObject {
    @Published var isOpen: Bool = false
    @Published var searchText: String = ""
    @Published var hoveredId: String?
    @Published var selection: String?
    @Published var options: [SelectOption] = []
    @Published var placeholder: String = "请选择"
    @Published var allowClear: Bool = true
    @Published var showSearch: Bool = false
    @Published var maxPanelHeight: CGFloat = 240
    @Published var panelWidth: CGFloat = 160
    @Published var dark: Bool = false

    /// Writes through to the caller's `@Binding` (captured when menu opens).
    var applySelection: ((String?) -> Void)?
    var menuId: UUID = UUID()

    func resetForOpen(
        selection: String?,
        options: [SelectOption],
        placeholder: String,
        allowClear: Bool,
        showSearch: Bool,
        maxPanelHeight: CGFloat,
        panelWidth: CGFloat,
        dark: Bool
    ) {
        self.searchText = ""
        self.hoveredId = nil
        self.selection = selection
        self.options = options
        self.placeholder = placeholder
        self.allowClear = allowClear
        self.showSearch = showSearch
        self.maxPanelHeight = maxPanelHeight
        self.panelWidth = panelWidth
        self.dark = dark
    }

    func sync(
        selection: String?,
        options: [SelectOption],
        placeholder: String,
        allowClear: Bool,
        showSearch: Bool,
        maxPanelHeight: CGFloat,
        panelWidth: CGFloat,
        dark: Bool
    ) {
        if self.selection != selection { self.selection = selection }
        if self.options.map(\.id) != options.map(\.id)
            || self.options.map(\.title) != options.map(\.title) {
            self.options = options
        }
        if self.placeholder != placeholder { self.placeholder = placeholder }
        if self.allowClear != allowClear { self.allowClear = allowClear }
        if self.showSearch != showSearch { self.showSearch = showSearch }
        if self.maxPanelHeight != maxPanelHeight { self.maxPanelHeight = maxPanelHeight }
        if self.panelWidth != panelWidth { self.panelWidth = panelWidth }
        if self.dark != dark { self.dark = dark }
    }

    func pick(_ id: String?) {
        selection = id
        applySelection?(id)
        close()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        searchText = ""
        hoveredId = nil
        SelectMenuCoordinator.shared.didClose(menuId)
    }
}

// MARK: - Panel UI (hosted on window.contentView)

private struct SelectMenuPanelView: View {
    @ObservedObject var state: SelectMenuPanelState

    private var dark: Bool { state.dark }
    private var accent: Color {
        dark ? Color(hex: "4d9eff") : Color(hex: "2563eb")
    }
    private var panelBg: Color {
        dark ? Color(hex: "22262b") : Color.white
    }
    private var softDivider: Color {
        dark ? Color(hex: "31363d") : Color(hex: "e8eef5")
    }

    private var filteredOptions: [SelectOption] {
        let q = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return state.options }
        return state.options.filter {
            $0.title.lowercased().contains(q)
                || ($0.subtitle?.lowercased().contains(q) ?? false)
                || $0.id.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.showSearch {
                searchBar
                Rectangle().fill(softDivider).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if state.allowClear {
                        row(
                            id: "__clear__",
                            title: state.placeholder,
                            subtitle: nil,
                            selected: state.selection == nil,
                            muted: true,
                            enabled: true
                        ) {
                            state.pick(nil)
                        }
                        Rectangle().fill(softDivider).frame(height: 1)
                    }

                    if filteredOptions.isEmpty {
                        Text("无匹配项")
                            .font(.system(size: 12))
                            .foregroundColor(AppInputStyle.placeholder(dark))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(filteredOptions) { opt in
                            row(
                                id: opt.id,
                                title: opt.title,
                                subtitle: opt.subtitle,
                                selected: state.selection == opt.id,
                                muted: false,
                                enabled: opt.enabled
                            ) {
                                guard opt.enabled else { return }
                                state.pick(opt.id)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: state.maxPanelHeight)
        }
        .frame(width: state.panelWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppInputStyle.radius)
                .fill(panelBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppInputStyle.radius)
                .stroke(AppInputStyle.border(dark, focused: true).opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(dark ? 0.45 : 0.14), radius: 14, y: 6)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppInputStyle.icon(dark))
            TextField("搜索…", text: $state.searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
                .foregroundColor(AppInputStyle.text(dark))
            if !state.searchText.isEmpty {
                Button(action: { state.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppInputStyle.icon(dark))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(dark ? Color(hex: "292d32") : Color(hex: "f8fafc"))
    }

    private func row(
        id: String,
        title: String,
        subtitle: String?,
        selected: Bool,
        muted: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let hovering = state.hoveredId == id
        let titleColor: Color = {
            if !enabled { return AppInputStyle.placeholder(dark).opacity(0.65) }
            if muted { return AppInputStyle.placeholder(dark) }
            if selected || hovering { return accent }
            return AppInputStyle.text(dark)
        }()
        let bg: Color = {
            guard enabled else { return .clear }
            if selected { return accent.opacity(dark ? 0.16 : 0.12) }
            if hovering { return accent.opacity(dark ? 0.10 : 0.07) }
            return .clear
        }()

        return Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: (selected && !muted) ? .semibold : .regular))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(AppInputStyle.placeholder(dark))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if selected && !muted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(accent)
                }
            }
            .padding(.horizontal, AppInputStyle.hPad)
            .padding(.vertical, (subtitle?.isEmpty == false) ? 7 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 36)
            .background(bg)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
        .onHover { inside in
            if inside {
                state.hoveredId = id
            } else if state.hoveredId == id {
                state.hoveredId = nil
            }
        }
    }
}

// MARK: - Window-level floating panel bridge

/// Anchor under the trigger. When open, attaches the option panel to
/// `window.contentView` so it paints and receives clicks above ScrollView siblings.
private struct SelectMenuFloatBridge: NSViewRepresentable {
    final class AnchorView: NSView {
        var panelWidth: CGFloat = 160
        var gap: CGFloat = 4
        var panelState: SelectMenuPanelState?

        private var panelHost: NSHostingView<AnyView>?
        private var mouseMonitor: Any?
        private var keyMonitor: Any?

        override var isFlipped: Bool { true }

        var isPresented: Bool { panelHost != nil }

        func present() {
            guard let window = window, let content = window.contentView, let state = panelState else { return }

            if panelHost == nil {
                let root = SelectMenuPanelView(state: state)
                    .environmentObject(AppearanceController.shared)
                let host = NSHostingView(rootView: AnyView(root))
                host.wantsLayer = true
                host.layer?.zPosition = 10_000
                content.addSubview(host, positioned: .above, relativeTo: nil)
                panelHost = host
            }

            layoutPanel()
            startMonitoring()
        }

        func dismiss() {
            stopMonitoring()
            panelHost?.removeFromSuperview()
            panelHost = nil
        }

        override func layout() {
            super.layout()
            if panelHost != nil {
                layoutPanel()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                dismiss()
            }
        }

        func layoutPanel() {
            guard let host = panelHost, let content = window?.contentView else { return }

            let fitting = host.fittingSize
            let w = max(panelWidth, 1)
            let estimated: CGFloat = {
                guard let state = panelState else { return 160 }
                var h: CGFloat = 8
                if state.showSearch { h += 38 }
                if state.allowClear { h += 36 }
                let rows = CGFloat(min(max(state.options.count, 1), 8))
                h += rows * 36
                return min(h, state.maxPanelHeight + (state.showSearch ? 38 : 0) + 8)
            }()
            let h = max(fitting.height > 10 ? fitting.height : estimated, 40)
            host.frame.size = NSSize(width: w, height: h)

            // Trigger in window base coordinates (origin bottom-left).
            let triggerWin = convert(bounds, to: nil)

            var panelWin = NSRect(
                x: triggerWin.minX,
                y: triggerWin.minY - gap - h,
                width: w,
                height: h
            )

            let contentBounds = content.convert(content.bounds, to: nil)
            if panelWin.minY < contentBounds.minY + 4 {
                let aboveY = triggerWin.maxY + gap
                if aboveY + h <= contentBounds.maxY - 4 {
                    panelWin.origin.y = aboveY
                } else {
                    panelWin.origin.y = max(contentBounds.minY + 4, panelWin.minY)
                }
            }
            if panelWin.maxX > contentBounds.maxX - 4 {
                panelWin.origin.x = max(contentBounds.minX + 4, contentBounds.maxX - 4 - w)
            }
            if panelWin.minX < contentBounds.minX + 4 {
                panelWin.origin.x = contentBounds.minX + 4
            }

            host.frame = content.convert(panelWin, from: nil)
            content.addSubview(host, positioned: .above, relativeTo: nil)
        }

        func startMonitoring() {
            stopMonitoring()
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self else { return event }
                if !self.eventHitsMenu(event) {
                    DispatchQueue.main.async {
                        self.panelState?.close()
                    }
                }
                return event
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    DispatchQueue.main.async {
                        self?.panelState?.close()
                    }
                    return nil
                }
                return event
            }
        }

        func stopMonitoring() {
            if let mouseMonitor = mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            if let keyMonitor = keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        private func eventHitsMenu(_ event: NSEvent) -> Bool {
            guard let window = self.window, event.window == window else {
                return false
            }
            let p = event.locationInWindow

            let trigger = convert(bounds, to: nil).insetBy(dx: -4, dy: -4)
            if trigger.contains(p) { return true }

            if let host = panelHost {
                let panel = host.convert(host.bounds, to: nil).insetBy(dx: -4, dy: -4)
                if panel.contains(p) { return true }
            }
            return false
        }

        deinit { dismiss() }
    }

    @ObservedObject var panelState: SelectMenuPanelState
    var panelWidth: CGFloat

    func makeNSView(context: Context) -> AnchorView {
        let v = AnchorView()
        v.panelWidth = panelWidth
        v.panelState = panelState
        return v
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.panelWidth = panelWidth
        nsView.panelState = panelState
        if panelState.isOpen {
            if nsView.isPresented {
                nsView.layoutPanel()
            } else {
                nsView.present()
            }
        } else {
            nsView.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: ()) {
        nsView.dismiss()
    }
}

// MARK: - SelectMenu

/// In-window custom dropdown (Web `custom-select` style).
/// Trigger matches `AppInputChrome`; option list floats on `window.contentView`
/// so ScrollView / card siblings never cover it or steal clicks.
struct SelectMenu: View {
    let options: [SelectOption]
    @Binding var selection: String?
    var placeholder: String = "请选择"
    var width: CGFloat? = 160
    var enabled: Bool = true
    /// Leading clear row that sets selection to nil.
    var allowClear: Bool = true
    /// Search box: `nil` = auto when options ≥ 8.
    var searchable: Bool? = nil
    var maxPanelHeight: CGFloat = 240

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    @StateObject private var panelState = SelectMenuPanelState()

    private var accent: Color {
        dark ? Color(hex: "4d9eff") : Color(hex: "2563eb")
    }

    private var resolvedWidth: CGFloat { width ?? 160 }
    private var panelWidth: CGFloat { resolvedWidth }

    private var displayTitle: String {
        if let id = selection, let opt = options.first(where: { $0.id == id }) {
            return opt.title
        }
        return placeholder
    }

    private var showingPlaceholder: Bool {
        guard let id = selection else { return true }
        return !options.contains(where: { $0.id == id })
    }

    private var showSearch: Bool {
        if let searchable = searchable { return searchable }
        return options.count >= 8
    }

    var body: some View {
        trigger
            .frame(width: resolvedWidth, height: AppInputStyle.height, alignment: .topLeading)
            .background(
                SelectMenuFloatBridge(panelState: panelState, panelWidth: panelWidth)
            )
            .zIndex(panelState.isOpen ? 900 : 0)
            .opacity(enabled ? 1 : 0.55)
            .disabled(!enabled)
            .animation(.easeOut(duration: 0.14), value: panelState.isOpen)
            .onAppear {
                panelState.menuId = UUID()
                SelectMenuCoordinator.shared.register(panelState.menuId) { [weak panelState] in
                    panelState?.close()
                }
                syncBindingWriter()
                syncPanelData(reset: false)
            }
            .onDisappear {
                SelectMenuCoordinator.shared.unregister(panelState.menuId)
                if panelState.isOpen {
                    panelState.close()
                }
            }
            // Keep panel data in sync while open (options may load async).
            .onChange(of: selection) { newVal in
                if panelState.selection != newVal {
                    panelState.selection = newVal
                }
            }
            .onChange(of: options.map(\.id).joined(separator: "\u{1e}")) { _ in
                if panelState.isOpen { syncPanelData(reset: false) }
            }
    }

    // MARK: Trigger

    private var trigger: some View {
        Button(action: toggleOpen) {
            HStack(spacing: 8) {
                Text(displayTitle)
                    .font(.system(size: AppInputStyle.fontSize))
                    .foregroundColor(
                        showingPlaceholder
                            ? AppInputStyle.placeholder(dark)
                            : AppInputStyle.text(dark)
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(panelState.isOpen ? accent : AppInputStyle.icon(dark))
                    .rotationEffect(.degrees(panelState.isOpen ? 180 : 0))
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, AppInputStyle.hPad)
            .frame(width: resolvedWidth, height: AppInputStyle.height)
            .background(
                RoundedRectangle(cornerRadius: AppInputStyle.radius)
                    .fill(AppInputStyle.fill(dark, focused: panelState.isOpen))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppInputStyle.radius)
                    .stroke(
                        AppInputStyle.border(dark, focused: panelState.isOpen),
                        lineWidth: panelState.isOpen ? 1.5 : 1
                    )
            )
            .shadow(
                color: AppInputStyle.glow(dark, focused: panelState.isOpen),
                radius: panelState.isOpen ? 6 : 0,
                y: 0
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(displayTitle)
    }

    // MARK: Open / close

    private func toggleOpen() {
        if panelState.isOpen {
            panelState.close()
        } else {
            openMenu()
        }
    }

    private func openMenu() {
        guard enabled else { return }
        SelectMenuCoordinator.shared.requestOpen(panelState.menuId)
        syncBindingWriter()
        syncPanelData(reset: true)
        panelState.isOpen = true
    }

    private func syncBindingWriter() {
        // Capture Binding (reference-like) so detached panel can write selection.
        let binding = $selection
        panelState.applySelection = { id in
            binding.wrappedValue = id
        }
    }

    private func syncPanelData(reset: Bool) {
        if reset {
            panelState.resetForOpen(
                selection: selection,
                options: options,
                placeholder: placeholder,
                allowClear: allowClear,
                showSearch: showSearch,
                maxPanelHeight: maxPanelHeight,
                panelWidth: panelWidth,
                dark: dark
            )
        } else {
            panelState.sync(
                selection: selection,
                options: options,
                placeholder: placeholder,
                allowClear: allowClear,
                showSearch: showSearch,
                maxPanelHeight: maxPanelHeight,
                panelWidth: panelWidth,
                dark: dark
            )
        }
    }
}

// MARK: - Int64 helper

struct SelectMenuInt64: View {
    let options: [SelectOption]
    @Binding var selection: Int64?
    var placeholder: String = "请选择"
    var width: CGFloat? = 160
    var allowClear: Bool = true
    var searchable: Bool? = nil

    private var stringBinding: Binding<String?> {
        Binding(
            get: { selection.map(String.init) },
            set: { selection = $0.flatMap { Int64($0) } }
        )
    }

    var body: some View {
        SelectMenu(
            options: options,
            selection: stringBinding,
            placeholder: placeholder,
            width: width,
            allowClear: allowClear,
            searchable: searchable
        )
    }
}
