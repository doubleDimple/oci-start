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
                .frame(minWidth: 180, maxWidth: 320)
            SelectMenu(options: RegionContinent.allCases.map { SelectOption(id: $0.rawValue, title: $0.title) },
                       selection: Binding(get: { model.continent.rawValue }, set: { model.continent = RegionContinent(rawValue: $0 ?? "") ?? .all }),
                       width: 150, allowClear: false)
            SelectMenu(options: RegionStatusFilter.allCases.map { SelectOption(id: $0.rawValue, title: $0.title) },
                       selection: Binding(get: { model.statusFilter.rawValue }, set: { model.statusFilter = RegionStatusFilter(rawValue: $0 ?? "") ?? .all }),
                       width: 140, allowClear: false)
            Spacer(minLength: 0)
            sourceError(regionText("ARM 开机记录", "ARM launch records"), model.armError)
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
                    Toggle(regionText("ARM 记录", "ARM history"), isOn: $model.showArm)
                    Toggle(regionText("我的区域", "My regions"), isOn: $model.showMine)
                    Toggle(regionText("交集", "Overlap"), isOn: $model.onlyShared)
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
                legend(Color(hex: "f4b760"), regionText("ARM 记录", "ARM history"))
                legend(Color(hex: "1b8a6a"), regionText("我的区域", "My regions"))
                legend(Color(hex: "1b8a6a"), regionText("交集 \(model.sharedCount)", "Overlap \(model.sharedCount)"), outlined: true)
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
                Text(regionText("开机记录 \(row.openCount) · 本月 \(row.monthlyOpenCount)", "Launches \(row.openCount) · This month \(row.monthlyOpenCount)")).font(.system(size: 13))
                Text(regionText("最近上报：", "Last report: ") + (row.lastNotifyTime ?? "—")).font(.system(size: 12))
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
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            tableCell(regionText("区域", "Region"), 260)
                            tableCell(regionText("状态", "Status"), 145)
                            tableCell(regionText("架构", "Architecture"), 85)
                            tableCell(regionText("开机次数", "Launches"), 85)
                            tableCell(regionText("本月", "This month"), 85)
                            tableCell(regionText("首次开机", "First launch"), 175)
                            tableCell(regionText("最近上报", "Last report"), 175)
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
                    .frame(width: max(1010, geometry.size.width), height: geometry.size.height)
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
                Text(!model.armLoaded ? "—" : row.isOpen ? regionText("有开机记录", "Has launch history") : regionText("无开机记录", "No launch history"))
                if row.isMine { Text(regionText("我的区域", "My region")).foregroundColor(AppTheme.brand(dark)).font(.system(size: 12)) }
            }.padding(.horizontal, 12).frame(width: 145, alignment: .leading)
            tableCell(row.architectureType, 85)
            tableCell(model.armLoaded ? "\(row.openCount)" : "—", 85)
            tableCell(model.armLoaded ? "\(row.monthlyOpenCount)" : "—", 85)
            tableCell(row.openTime ?? "—", 175)
            tableCell(row.lastNotifyTime ?? "—", 175)
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
            Text(regionText("ARM \(model.armLoaded ? "\(model.openArmCount)" : "—")", "ARM \(model.armLoaded ? "\(model.openArmCount)" : "—")"))
            Text(regionText("我的区域 \(model.mineLoaded ? "\(model.mineCount)" : "—")", "My regions \(model.mineLoaded ? "\(model.mineCount)" : "—")"))
            Text(regionText("今日新增 \(model.armLoaded ? "\(model.todayNewCount)" : "—")", "New today \(model.armLoaded ? "\(model.todayNewCount)" : "—")"))
            Spacer(minLength: 0)
            Text(model.lastUpdateText).help(regionText("最近完整刷新时间", "Last complete refresh"))
        }.font(.system(size: 13)).lineLimit(1)
    }
    private func tableCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).lineLimit(2).padding(.horizontal, 12).frame(width: width, alignment: .leading).help(text)
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
    static func dismantleNSView(_ view: RegionWorldCanvas, coordinator: ()) { view.stop() }
}

/// Draws the same supplied 5px dot artwork as Vue using AppKit, without web content.
private final class RegionWorldCanvas: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var rows: [RegionRow] = []
    private var selected: String?
    private var magnification = 1.0
    private var labels = true, pulse = true, links = true, dark = false
    private var center = RegionCoordinate(lat: 13, lng: 0)
    private var onSelect: ((RegionRow) -> Void)?
    private var onZoom: ((Double) -> Void)?
    private var timer: Timer?
    private var phase = 0.0
    private var cachedBase: NSBezierPath?
    private var cacheKey = ""
    private var dragOrigin: NSPoint?
    private var dragCenter: RegionCoordinate?
    private var dragged = false
    private var tracking: NSTrackingArea?
    private var markerFrames: [(RegionRow, NSPoint)] = []
    private var hovered: String?
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

    func configure(rows: [RegionRow], selected: String?, zoom: Double, labels: Bool, pulse: Bool, links: Bool,
                   dark: Bool, onSelect: @escaping (RegionRow) -> Void, onZoom: @escaping (Double) -> Void) {
        if selected != self.selected {
            if let row = rows.first(where: { $0.regionCode == selected }), let coordinate = row.coordinate, zoom > 1.01 { center = coordinate }
            else if selected == nil { center = RegionCoordinate(lat: 13, lng: 0) }
        }
        self.rows = rows
        self.selected = selected
        self.magnification = zoom
        self.labels = labels
        self.pulse = pulse
        self.links = links
        self.dark = dark
        self.onSelect = onSelect
        self.onZoom = onZoom
        toolTip = regionText("拖动平移，双指缩放；点击区域查看记录。", "Drag to pan, pinch to zoom, and select a region to view records.")
        needsDisplay = true
        updateTimer()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateTimer() }
    func stop() { timer?.invalidate(); timer = nil }
    private func updateTimer() {
        guard window != nil, pulse, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { stop(); return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true, !self.isHiddenOrHasHiddenAncestor, NSApp.isActive,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            self.phase = Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            self.needsDisplay = true
        }
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
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        (dark ? color(0x0a1420) : NSColor.white).setFill()
        bounds.fill()
        buildBaseIfNeeded()
        (dark ? color(0x22506b) : color(0xc3d2dc)).setFill()
        cachedBase?.fill()
        markerFrames = rows.compactMap { row in
            guard let coordinate = row.coordinate else { return nil }
            return (row, project(coordinate))
        }.filter { bounds.insetBy(dx: -16, dy: -16).contains($0.1) }
        if links { drawLinks() }
        var labelRects: [NSRect] = []
        let ordered = markerFrames.sorted { ($0.0.regionCode == selected ? 1 : 0) < ($1.0.regionCode == selected ? 1 : 0) }
        for (row, point) in ordered {
            let mine = dark ? color(0x4fe3c1) : color(0x1b8a6a)
            let arm = dark ? color(0xf4b760) : color(0xb7791f)
            let markerColor = row.isMine ? mine : arm
            let active = row.regionCode == selected || row.regionCode == hovered
            if pulse && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let radius = CGFloat(5 + phase * 10)
                markerColor.withAlphaComponent(CGFloat((1 - phase) * 0.5)).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                ring.lineWidth = 1
                ring.stroke()
            }
            let radius: CGFloat = active ? 5 : 3.5
            markerColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
            if row.isMine && row.isOpen || active {
                (row.isOpen ? arm : mine).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: point.x - radius - 2, y: point.y - radius - 2, width: radius * 2 + 4, height: radius * 2 + 4))
                ring.lineWidth = active ? 2 : 1
                ring.stroke()
            }
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
        guard markerFrames.count > 1 else { return }
        let origin = markerFrames.first(where: { $0.0.regionCode == selected }) ?? markerFrames[0]
        (dark ? color(0x4fe3c1) : color(0x1b8a6a)).withAlphaComponent(0.22).setStroke()
        for destination in markerFrames where destination.0.regionCode != origin.0.regionCode {
            let a = origin.1, b = destination.1
            let curve = NSBezierPath()
            curve.move(to: a)
            let lift = min(CGFloat(70), abs(a.x - b.x) * 0.18)
            curve.curve(to: b, controlPoint1: NSPoint(x: a.x + (b.x - a.x) / 3, y: a.y - lift),
                        controlPoint2: NSPoint(x: a.x + (b.x - a.x) * 2 / 3, y: b.y - lift))
            curve.lineWidth = 0.7
            curve.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragCenter = center
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let original = dragCenter else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        if abs(delta.x) + abs(delta.y) > 4 { dragged = true }
        center = RegionCoordinate(lat: max(-58, min(84, original.lat + Double(delta.y / scale))),
                                  lng: max(-180, min(180, original.lng - Double(delta.x / scale))))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil; dragCenter = nil }
        guard !dragged else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let nearest = closest(to: point) { onSelect?(nearest.0) }
    }
    override func magnify(with event: NSEvent) { onZoom?(max(1, min(5, magnification * (1 + Double(event.magnification))))) }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nearest = closest(to: point)
        hovered = nearest?.0.regionCode
        toolTip = nearest.map { "\($0.0.displayName) · \($0.0.regionCode)" }
        if nearest == nil { NSCursor.arrow.set() } else { NSCursor.pointingHand.set() }
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; NSCursor.arrow.set(); needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "+" { onZoom?(min(5, magnification * 1.25)); return }
        if event.charactersIgnoringModifiers == "-" { onZoom?(max(1, magnification / 1.25)); return }
        super.keyDown(with: event)
    }
    private func closest(to point: NSPoint) -> (RegionRow, NSPoint)? {
        markerFrames.filter { hypot($0.1.x - point.x, $0.1.y - point.y) <= 14 }
            .min { hypot($0.1.x - point.x, $0.1.y - point.y) < hypot($1.1.x - point.x, $1.1.y - point.y) }
    }
    deinit { timer?.invalidate() }
}
