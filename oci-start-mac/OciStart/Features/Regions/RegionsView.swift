import SwiftUI
import AppKit

struct RegionsView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = RegionsViewModel()
    @AppStorage("appLocale") private var locale = "zh_CN"
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        GeometryReader { viewport in
            PageScaffold(title: regionText("区域管理", "Regions"), subtitle: "", systemImage: "globe", layout: .workspace,
                         toolbar: { toolbar }, content: {
                VStack(spacing: 14) {
                    if model.showMapBoard {
                        mapCard.frame(height: max(250, min(390, viewport.size.height * 0.44)))
                    }
                    listCard
                    footer
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, AppTheme.pagePadding)
                .foregroundColor(AppTheme.textPrimary(dark))
            })
        }
        .background(AppTheme.pageBg(dark))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: locale) { _ in model.localeChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in Task { await model.refresh() } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            AppTextField(text: $model.searchText, placeholder: regionText("搜索区域名称或标识", "Search region name or identifier"), leadingSystemImage: "magnifyingglass")
                .frame(width: 240)
            SelectMenu(options: RegionContinent.allCases.map { SelectOption(id: $0.rawValue, title: $0.title) },
                       selection: Binding(get: { model.continent.rawValue }, set: { model.continent = RegionContinent(rawValue: $0 ?? "") ?? .all }),
                       width: 150, allowClear: false)
            SelectMenu(options: RegionStatusFilter.allCases.map { SelectOption(id: $0.rawValue, title: $0.title) },
                       selection: Binding(get: { model.statusFilter.rawValue }, set: { model.statusFilter = RegionStatusFilter(rawValue: $0 ?? "") ?? .all }),
                       width: 140, allowClear: false)
            Spacer(minLength: 0)
            sourceError(regionText("我的区域", "My regions"), model.mineError)
            AppButton(title: "", systemImage: model.showMapBoard ? "map.fill" : "map", kind: .secondary) { model.showMapBoard.toggle() }
                .help(regionText("显示 / 隐藏地图", "Show / hide map"))
            AppButton(title: "", systemImage: "arrow.clockwise", kind: .secondary, isLoading: model.isLoading) { Task { await model.refresh() } }
                .help(regionText("刷新区域数据", "Refresh regions"))
        }
    }

    private var mapCard: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    Group {
                    Toggle(regionText("我的区域", "My regions"), isOn: $model.showMine)
                    Divider().frame(height: 20)
                    Toggle(regionText("标签", "Labels"), isOn: $model.showLabels)
                    Toggle(regionText("脉冲", "Pulse"), isOn: $model.showPulse)
                        .disabled(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                    Toggle(regionText("连线", "Links"), isOn: $model.showLinks)
                    }
                    Group {
                    SelectMenu(options: model.mapRows.map { SelectOption(id: $0.regionCode, title: "\($0.displayName) · \($0.regionCode)") },
                               selection: $model.selectedRegion, placeholder: regionText("定位区域", "Locate region"), width: 205, allowClear: true)
                    Button { model.zoom = min(5, model.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help(regionText("放大", "Zoom in"))
                    Button { model.zoom = max(1, model.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help(regionText("缩小", "Zoom out"))
                    Button { model.zoom = 1; model.selectedRegion = nil } label: { Image(systemName: "arrow.counterclockwise") }
                        .help(regionText("复位地图", "Reset map"))
                    }
                }
                .toggleStyle(CheckboxToggleStyle())
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 13))
                .padding(12)
            }
            NativeRegionWorldMap(rows: model.mapRows, selected: model.selectedRegion, zoom: model.zoom,
                                 labels: model.showLabels, pulse: model.showPulse, links: model.showLinks, dark: dark,
                                 onSelect: { row in model.select(row, locateTable: true) }, onZoom: { model.zoom = $0 })
                .overlay(selectedDetail, alignment: .bottomLeading)
                .clipped()
            HStack(spacing: 16) {
                legend(Color(hex: "b65b22"), regionText("已关联账号", "Account linked"))
                Spacer(minLength: 0)
                if model.unknownCoordinates > 0 {
                    Text(regionText("\(model.unknownCoordinates) 个区域无坐标，仍保留在列表", "\(model.unknownCoordinates) unmapped regions remain in the table"))
                        .font(.system(size: 12))
                }
                Text(regionText("地图连线仅作示意", "Links are illustrative")).font(.system(size: 12))
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(AppTheme.cardBg(dark))
        .cornerRadius(AppTheme.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.border(dark), lineWidth: 1))
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let row = model.selectedRow {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.displayName).font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 12)
                    Button { model.selectedRegion = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(PlainButtonStyle()).help(regionText("关闭详情", "Close details"))
                }
                Text(row.regionCode).font(.system(size: 12))
                if row.coordinate == nil { Text(regionText("暂无公开坐标", "No known coordinates")).font(.system(size: 12)) }
            }
            .padding(12).frame(width: 270)
            .background(AppTheme.cardBg(dark).opacity(0.95)).cornerRadius(10)
            .padding(12)
        }
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                NativeHorizontalTable(contentWidth: max(640, geometry.size.width), viewportWidth: geometry.size.width, height: geometry.size.height) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            tableCell(regionText("区域", "Region"), 260).nativeTableHeader(regionText("区域", "Region"))
                            tableCell(regionText("状态", "Status"), 145).nativeTableHeader(regionText("状态", "Status"))
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .frame(height: 42).background(AppTheme.hover(dark))
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(model.pageRows) { row in
                                    Button { model.select(row) } label: { tableRow(row) }
                                        .buttonStyle(PlainButtonStyle())
                                        .accessibilityLabel("\(row.displayName), \(row.regionCode)")
                                }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                        }.overlay(Group {
                            if model.pageRows.isEmpty {
                                EmptyStateView(icon: "globe", title: model.isLoading ? regionText("加载中…", "Loading…") : regionText("没有匹配的区域", "No matching regions"),
                                               subtitle: regionText("调整搜索或筛选", "Adjust the search or filters"))
                            }
                        })
                    }
                    .frame(width: max(640, geometry.size.width), alignment: .topLeading)
                }
            }
            PaginationBar(state: $model.pageState, onChange: { model.goPage { _ in } })
        }
        .background(AppTheme.cardBg(dark))
        .cornerRadius(AppTheme.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.border(dark), lineWidth: 1))
    }

    private func tableRow(_ row: RegionRow) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayName).font(.system(size: 14, weight: .medium))
                Text(row.regionCode).font(.system(size: 13))
            }.lineLimit(1).padding(.horizontal, 12).frame(width: 260, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(!model.mineLoaded ? "—" : row.isMine ? regionText("已关联账号", "Account linked") : regionText("未关联账号", "No linked account"))
            }.padding(.horizontal, 12).frame(width: 145, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: 14))
        .frame(height: 64)
        .background(model.selectedRegion == row.regionCode ? AppTheme.hover(dark) : AppTheme.cardBg(dark))
        .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .bottom)
    }
    private var footer: some View {
        HStack(spacing: 16) {
            Text(regionText("区域 \(model.totalRegions)", "\(model.totalRegions) regions"))
            Text(regionText("我的区域 \(model.mineLoaded ? "\(model.mineCount)" : "—")", "My regions \(model.mineLoaded ? "\(model.mineCount)" : "—")"))
            Spacer(minLength: 0)
            Text(model.lastUpdateText).help(regionText("最近完整刷新时间", "Last complete refresh"))
        }.font(.system(size: 13)).lineLimit(1)
    }
    private func tableCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).lineLimit(1).padding(.horizontal, 12).frame(width: width, alignment: .leading).help(text)
    }
    private func legend(_ color: Color, _ text: String, outlined: Bool = false) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color(hex: "f4b760"), lineWidth: outlined ? 2 : 0))
            Text(text).font(.system(size: 12))
        }
    }
    @ViewBuilder private func sourceError(_ source: String, _ detail: String?) -> some View {
        if let detail = detail {
            Button {
                let alert = NSAlert()
                alert.messageText = source
                alert.informativeText = detail
                alert.addButton(withTitle: regionText("关闭", "Close"))
                alert.runModal()
            } label: { Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red) }
            .buttonStyle(PlainButtonStyle()).help(source + " · " + regionText("刷新失败，保留上次数据", "Refresh failed; previous data retained"))
        }
    }
}

private struct NativeRegionWorldMap: NSViewRepresentable {
    let rows: [RegionRow]
    let selected: String?
    let zoom: Double
    let labels: Bool
    let pulse: Bool
    let links: Bool
    let dark: Bool
    let onSelect: (RegionRow) -> Void
    let onZoom: (Double) -> Void
    func makeNSView(context: Context) -> RegionWorldCanvas { RegionWorldCanvas() }
    func updateNSView(_ view: RegionWorldCanvas, context: Context) {
        view.configure(rows: rows, selected: selected, zoom: zoom, labels: labels, pulse: pulse, links: links,
                       dark: dark, onSelect: onSelect, onZoom: onZoom)
    }
    static func dismantleNSView(_ view: RegionWorldCanvas, coordinator: ()) { view.dispose() }
}

/// Draws the same supplied 5px dot artwork as Vue using AppKit, without web content.
private final class RegionWorldCanvas: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var mappedRows: [(row: RegionRow, coordinate: RegionCoordinate)] = []
    private var linkCoordinates: [(RegionCoordinate, RegionCoordinate)] = []
    private var pulsePhases: [String: TimeInterval] = [:]
    private var haloGradients: [Int: CGGradient] = [:]
    private var selected: String?
    private var magnification = 1.0
    private var labels = true, pulse = true, links = true, dark = false
    private var center = RegionCoordinate(lat: 13, lng: 0)
    private var onSelect: ((RegionRow) -> Void)?
    private var onZoom: ((Double) -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private weak var scrollClip: NSClipView?
    private var scrollObservers: [NSObjectProtocol] = []
    private var refreshQueued = false
    private var disposed = false
    private var lastTickTime: TimeInterval?
    private var elapsed: TimeInterval = 0
    private var cachedBase: NSBezierPath?
    private var cacheKey = ""
    private var dragOrigin: NSPoint?
    private var dragCenter: RegionCoordinate?
    private var dragged = false
    private var tracking: NSTrackingArea?
    private var markerFrames: [(RegionRow, NSPoint)] = []
    private var hovered: String?
    private var pointerLocation: NSPoint?

    private static func phaseFor(_ code: String) -> TimeInterval {
        var hash: Int32 = 0
        for byte in code.utf8 { hash = (hash &* 31) &+ Int32(byte) }
        return Double(abs(Int64(hash)) % 2200) / 1000.0
    }

    private static let landShapes: [NSBezierPath] = KnownRegions.land.map { polygon in
        let path = NSBezierPath()
        for (index, coordinate) in polygon.enumerated() {
            let point = NSPoint(x: coordinate[0], y: coordinate[1])
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }
    private var scale: CGFloat { max(0.001, min(max(1, bounds.width - 24) / 360, max(1, bounds.height - 24) / 142)) * CGFloat(magnification) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification, NSWindow.didExposeNotification,
                     NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self = self else { return }
                if let changedWindow = notification.object as? NSWindow, changedWindow !== self.window { return }
                if notification.name == NSWindow.willCloseNotification { self.stop(); return }
                if notification.name == NSApplication.didResignActiveNotification || notification.name == NSWindow.didResignKeyNotification {
                    self.cancelInteraction()
                }
                self.updateTimer()
                self.refreshAfterLayout()
            })
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateTimer(); self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(rows: [RegionRow], selected: String?, zoom: Double, labels: Bool, pulse: Bool, links: Bool,
                   dark: Bool, onSelect: @escaping (RegionRow) -> Void, onZoom: @escaping (Double) -> Void) {
        if selected != self.selected {
            if let row = rows.first(where: { $0.regionCode == selected }), let coordinate = row.coordinate, zoom > 1.01 { center = coordinate }
            else if selected == nil { center = RegionCoordinate(lat: 13, lng: 0) }
        }
        // Data changes are infrequent; keep sorting and hashing out of every frame.
        mappedRows = rows.compactMap { row in row.coordinate.map { (row: row, coordinate: $0) } }
        pulsePhases = mappedRows.reduce(into: [:]) { result, entry in
            result[entry.row.regionCode] = Self.phaseFor(entry.row.regionCode)
        }
        let ordered = mappedRows.sorted { $0.row.regionCode < $1.row.regionCode }
        linkCoordinates = zip(ordered, ordered.dropFirst()).compactMap { start, end in
            let a = start.coordinate, b = end.coordinate
            return a.lat == b.lat && a.lng == b.lng ? nil : (a, b)
        }
        self.selected = selected
        self.magnification = zoom
        self.labels = labels
        self.pulse = pulse
        self.links = links
        self.dark = dark
        self.onSelect = onSelect
        self.onZoom = onZoom
        refreshHover()
        needsDisplay = true
        updateTimer()
        refreshAfterLayout()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop(); detachScrollObserver() }
        else { refreshAfterLayout() }
    }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); refreshAfterLayout() }
    override func viewDidHide() { super.viewDidHide(); stop() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshAfterLayout() }
    override func layout() {
        super.layout()
        refreshHover()
        refreshAfterLayout()
        needsDisplay = true
    }
    private func refreshAfterLayout() {
        guard !disposed, !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshQueued = false
            guard !self.disposed else { return }
            self.attachScrollObserver()
            self.updateTimer()
        }
    }
    private func attachScrollObserver() {
        var ancestor = superview
        var clip: NSClipView?
        while let view = ancestor {
            if let found = view as? NSClipView { clip = found; break }
            ancestor = view.superview
        }
        guard clip !== scrollClip else { return }
        detachScrollObserver()
        guard let found = clip else { return }
        scrollClip = found
        found.postsBoundsChangedNotifications = true
        found.postsFrameChangedNotifications = true
        for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
            scrollObservers.append(NotificationCenter.default.addObserver(forName: name, object: found, queue: .main) { [weak self] _ in
                self?.refreshAfterLayout()
            })
        }
    }
    private func detachScrollObserver() {
        scrollObservers.forEach { NotificationCenter.default.removeObserver($0) }
        scrollObservers.removeAll()
        scrollClip = nil
    }
    func dispose() {
        disposed = true
        stop()
        detachScrollObserver()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let observer = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObserver = nil
        if let tracking = tracking { removeTrackingArea(tracking) }
        tracking = nil
        onSelect = nil
        onZoom = nil
    }
    private func cancelInteraction() {
        dragOrigin = nil
        dragCenter = nil
        pointerLocation = nil
        refreshHover()
    }
    private func stop(cancelInteraction: Bool = true) {
        timer?.invalidate()
        timer = nil
        lastTickTime = nil
        if cancelInteraction { self.cancelInteraction() }
    }
    private var isVisibleForAnimation: Bool {
        guard !disposed, let window = window, window.isVisible, !window.isMiniaturized,
              window.occlusionState.contains(.visible), !NSApp.isHidden, !isHiddenOrHasHiddenAncestor,
              bounds.width > 0, bounds.height > 0, !visibleRect.isEmpty else { return false }
        return true
    }
    private var canAnimate: Bool {
        isVisibleForAnimation && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion &&
            ((pulse && !mappedRows.isEmpty) || (links && !linkCoordinates.isEmpty))
    }
    private func updateTimer() {
        guard canAnimate else {
            // Disabling decoration must not cancel manual pan/zoom or hover.
            stop(cancelInteraction: !isVisibleForAnimation)
            return
        }
        guard timer == nil else { return }
        lastTickTime = ProcessInfo.processInfo.systemUptime
        let next = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.canAnimate else { self.updateTimer(); return }
            let now = ProcessInfo.processInfo.systemUptime
            let delta = min(0.05, max(0, now - (self.lastTickTime ?? now)))
            self.lastTickTime = now
            self.elapsed += delta
            self.needsDisplay = true
        }
        next.tolerance = 0.003
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
    override func updateTrackingAreas() {
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }
    private func project(_ coordinate: RegionCoordinate) -> NSPoint {
        NSPoint(x: bounds.midX + CGFloat(coordinate.lng - center.lng) * scale,
                y: bounds.midY + CGFloat(center.lat - coordinate.lat) * scale)
    }
    private func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private func haloGradient(active: Bool, color: NSColor) -> CGGradient? {
        let key = (dark ? 4 : 0) + (active ? 1 : 0)
        if let cached = haloGradients[key] { return cached }
        let colors = [color.withAlphaComponent(active ? 0.5 : 0.32).cgColor,
                      color.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
        haloGradients[key] = gradient
        return gradient
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if timer == nil { refreshAfterLayout() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        (dark ? color(0x0a1420) : NSColor.white).setFill()
        bounds.fill()
        buildBaseIfNeeded()
        (dark ? color(0x22506b) : color(0xc3d2dc)).setFill()
        cachedBase?.fill()
        markerFrames = mappedRows.map { ($0.row, project($0.coordinate)) }
            .filter { bounds.insetBy(dx: -16, dy: -16).contains($0.1) }
        if links { drawLinks() }
        var labelRects: [NSRect] = []
        let ordered = markerFrames.filter { $0.0.regionCode != selected } + markerFrames.filter { $0.0.regionCode == selected }
        let moving = pulse && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let markerColor = dark ? color(0xffb47a) : color(0xb65b22)

        for (row, point) in ordered {
            let active = (row.regionCode == selected || row.regionCode == hovered)

            // Outer Pulsing Ring
            if moving {
                let phase = pulsePhases[row.regionCode] ?? 0
                let ringProgress = CGFloat(((elapsed + phase) / 2.2).truncatingRemainder(dividingBy: 1.0))
                let ringRadius = 3.0 + ringProgress * (active ? 16.0 : 11.0)
                let ringColor = markerColor
                ringColor.withAlphaComponent((1.0 - ringProgress) * (active ? 0.75 : 0.45)).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: point.x - ringRadius, y: point.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
                ring.lineWidth = 1.2
                ring.stroke()
            }

            // Glowing Radial Gradient Halo
            let glowRadius: CGFloat = active ? 13.0 : 9.0
            if let haloGrad = haloGradient(active: active, color: markerColor) {
                ctx.drawRadialGradient(haloGrad,
                                       startCenter: CGPoint(x: point.x, y: point.y), startRadius: 0,
                                       endCenter: CGPoint(x: point.x, y: point.y), endRadius: glowRadius,
                                       options: [])
            }

            if active {
                markerColor.withAlphaComponent(0.8).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: point.x - 6.6, y: point.y - 6.6, width: 13.2, height: 13.2))
                ring.lineWidth = 1.0
                ring.stroke()
            }

            // Core Dot
            let coreR: CGFloat = active ? 3.4 : 2.6
            markerColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - coreR, y: point.y - coreR, width: coreR * 2, height: coreR * 2)).fill()

            if labels || active {
                let name = KnownRegions.cityName(row.regionCode) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: active ? .semibold : .regular),
                                                                .foregroundColor: dark ? color(0xdcecf3) : color(0x25323d)]
                let size = name.size(withAttributes: attributes)
                var placement: NSRect?
                for vertical in [CGFloat(-15), 3, -30, 18, -45, 33] {
                    let x = point.x > bounds.maxX - size.width - 20 ? point.x - size.width - 9 : point.x + 9
                    let candidate = NSRect(x: max(4, x), y: point.y + vertical, width: size.width, height: size.height)
                    if bounds.insetBy(dx: 4, dy: 4).contains(candidate) &&
                        (active || !labelRects.contains(where: { $0.insetBy(dx: -3, dy: -2).intersects(candidate) })) {
                        placement = candidate
                        break
                    }
                }
                if let placement = placement { name.draw(in: placement, withAttributes: attributes); labelRects.append(placement) }
            }
        }
    }
    private func buildBaseIfNeeded() {
        let key = "\(bounds.size.width):\(bounds.size.height):\(magnification):\(center.lat):\(center.lng)"
        guard cacheKey != key else { return }
        cacheKey = key
        let path = NSBezierPath()
        let step: CGFloat = 5
        for y in stride(from: CGFloat(2.5), to: bounds.height, by: step) {
            let latitude = center.lat - Double((y - bounds.midY) / scale)
            guard latitude >= -58, latitude <= 84 else { continue }
            for x in stride(from: CGFloat(2.5), to: bounds.width, by: step) {
                let longitude = center.lng + Double((x - bounds.midX) / scale)
                guard longitude >= -180, longitude <= 180 else { continue }
                let coordinate = NSPoint(x: longitude, y: latitude)
                if Self.landShapes.contains(where: { $0.bounds.contains(coordinate) && $0.contains(coordinate) }) {
                    path.appendOval(in: NSRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
                }
            }
        }
        cachedBase = path
    }
    private func drawLinks() {
        guard !linkCoordinates.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let mineColor = dark ? color(0x4fe3c1) : color(0x1b8a6a)
        let moving = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let progress = CGFloat((elapsed / 2.6).truncatingRemainder(dividingBy: 1.0))
        let remaining = 1.0 - progress
        for (a, b) in linkCoordinates {
            let start = project(a)
            let end = project(b)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let controlX = (start.x + end.x) / 2.0 - dy * 0.22
            let controlY = (start.y + end.y) / 2.0 + dx * 0.22

            ctx.saveGState()
            ctx.beginPath()
            ctx.move(to: CGPoint(x: start.x, y: start.y))
            ctx.addQuadCurve(to: CGPoint(x: end.x, y: end.y), control: CGPoint(x: controlX, y: controlY))
            mineColor.withAlphaComponent(0.35).setStroke()
            ctx.setLineWidth(1.0)
            ctx.strokePath()

            // Traveling Light Particle along Link
            if moving {
                let px = remaining * remaining * start.x + 2.0 * remaining * progress * controlX + progress * progress * end.x
                let py = remaining * remaining * start.y + 2.0 * remaining * progress * controlY + progress * progress * end.y
                let alpha = sin(.pi * progress)
                mineColor.withAlphaComponent(alpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: px - 1.8, y: py - 1.8, width: 3.6, height: 3.6)).fill()
            }
            ctx.restoreGState()
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragCenter = center
        dragged = false
        refreshHover()
        NSCursor.closedHand.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let original = dragCenter else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        if !dragged {
            guard hypot(delta.x, delta.y) > 4 else { return }
            dragged = true
        }
        center = RegionCoordinate(lat: max(-58, min(84, original.lat + Double(delta.y / scale))),
                                  lng: max(-180, min(180, original.lng - Double(delta.x / scale))))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let wasDragged = dragged
        dragOrigin = nil
        dragCenter = nil
        if !wasDragged, let nearest = closest(to: point) { onSelect?(nearest.0) }
        pointerLocation = point
        refreshHover()
    }
    override func magnify(with event: NSEvent) { onZoom?(max(1, min(5, magnification * (1 + Double(event.magnification))))) }
    override func mouseMoved(with event: NSEvent) {
        pointerLocation = convert(event.locationInWindow, from: nil)
        refreshHover()
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    private func refreshHover() {
        let nearest = dragOrigin == nil ? pointerLocation.flatMap { closest(to: $0) } : nil
        if hovered != nearest?.0.regionCode {
            hovered = nearest?.0.regionCode
            needsDisplay = true
        }
        let text = nearest.map { "\($0.0.displayName) · \($0.0.regionCode)" } ??
            regionText("拖动平移，双指缩放；点击区域查看记录。", "Drag to pan, pinch to zoom, and select a region to view records.")
        if toolTip != text { toolTip = text }
        if pointerLocation != nil, window?.isKeyWindow == true, dragOrigin == nil {
            if nearest == nil { NSCursor.arrow.set() } else { NSCursor.pointingHand.set() }
        }
    }
    override func mouseExited(with event: NSEvent) {
        pointerLocation = nil
        refreshHover()
        NSCursor.arrow.set()
    }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "+" { onZoom?(min(5, magnification * 1.25)); return }
        if event.charactersIgnoringModifiers == "-" { onZoom?(max(1, magnification / 1.25)); return }
        super.keyDown(with: event)
    }
    private func closest(to point: NSPoint) -> (RegionRow, NSPoint)? {
        guard bounds.contains(point) else { return nil }
        var nearest: (RegionRow, NSPoint)?
        var distance: CGFloat = 14 * 14
        // Project the current viewport, even if a resize/zoom has not drawn yet.
        for entry in mappedRows {
            let marker = project(entry.coordinate)
            let dx = marker.x - point.x, dy = marker.y - point.y
            let candidate = dx * dx + dy * dy
            if candidate < distance {
                nearest = (entry.row, marker)
                distance = candidate
            }
        }
        return nearest
    }
    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        scrollObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let observer = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
