import SwiftUI
import AppKit

/// Public geography from the Vue login, drawn locally with a 3D interactive rotating globe.
struct LoginHeroView: View {
    var dark: Bool
    var locale: AppLocale = .zhCN
    @State private var showDirectory = false

    private var english: Bool { locale == .enUS }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 11) {
                        Image(systemName: "drop")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(LoginPalette.highlight(dark))
                        Text("OCI-START")
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(0.4)
                        Text(english ? "/ Workspace" : "/ 云端工作台")
                            .font(.system(size: 14))
                            .foregroundColor(LoginPalette.muted(dark))
                    }
                    Spacer(minLength: 36)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(english ? "Your cloud,\nin one workspace." : "让云端资源，\n井然有序。")
                            .font(.system(size: 30, weight: .semibold))
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(english
                             ? "Manage your instances, networks and services from one place."
                             : "从实例到网络，从监控到运维，\n在一个工作台中管理你的云端资源。")
                            .font(.system(size: 14))
                            .lineSpacing(6)
                            .foregroundColor(LoginPalette.muted(dark))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 20)
                    HStack {
                        Text(english ? "OCI public regions" : "OCI 公共区域")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(LoginPublicRegion.all.count) " + (english ? "regions" : "个区域"))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(LoginPalette.muted(dark))
                    }
                    LoginRegionMap(dark: dark, english: english)
                        .frame(height: max(220, min(320, (geo.size.width - 68) * 0.65)))
                        .padding(.horizontal, -12)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                    Button(action: { showDirectory.toggle() }) {
                        HStack(spacing: 6) {
                            Text(english ? "Browse region directory" : "查看区域目录")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(LoginPalette.muted(dark))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $showDirectory, arrowEdge: .bottom) { directory }
                    Text(english
                         ? "City reference points · interactive 3D globe"
                         : "城市参考位置 · 3D 可交互地球示意")
                        .font(.system(size: 12))
                        .foregroundColor(LoginPalette.muted(dark))
                        .padding(.top, 8)
                    Spacer(minLength: 24)
                    HStack(spacing: 8) {
                        Text("© 2026 doubleDimple")
                        Text("·")
                        Link("GitHub", destination: URL(string: "https://github.com/doubleDimple/oci-start")!)
                        Text("·")
                        Link(english ? "Docs" : "文档", destination: URL(string: "https://github.com/doubleDimple/oci-start#readme")!)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(LoginPalette.muted(dark))
                }
                .foregroundColor(LoginPalette.text(dark))
                .padding(.horizontal, geo.size.width < 500 ? 30 : 46)
                .padding(.top, 34)
                .padding(.bottom, 30)
                .frame(minHeight: geo.size.height, alignment: .topLeading)
            }
        }
        .background(LoginPalette.bg(dark))
    }

    private var directory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(english ? "OCI public commercial regions" : "OCI 公共商业区域")
                .font(.system(size: 16, weight: .semibold))
            Text(english
                 ? "Directory checked 2026-09-15. Coordinates refer to cities, not data centres."
                 : "目录核对于 2026-09-15。坐标为城市参考点，并非机房位置。")
                .font(.system(size: 13))
                .foregroundColor(LoginPalette.muted(dark))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(LoginPublicRegion.all) { region in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(english ? region.en : region.zh)
                                .font(.system(size: 14, weight: .medium))
                            Text(region.id)
                                .font(.system(size: 12, design: .monospaced))
                            Text(region.coordinates)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(LoginPalette.muted(dark))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                        .overlay(LoginPalette.line(dark).frame(height: 1), alignment: .bottom)
                    }
                }
            }
            HStack(spacing: 16) {
                Link(english ? "Oracle directory" : "Oracle 区域目录", destination: URL(string: "https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm")!)
                Link("GeoNames", destination: URL(string: "https://www.geonames.org/")!)
            }
            .font(.system(size: 12))
            .foregroundColor(LoginPalette.highlight(dark))
        }
        .padding(22)
        .frame(width: 390, height: 500)
        .foregroundColor(LoginPalette.text(dark))
        .background(LoginPalette.card(dark))
    }
}

private struct LoginRegionMap: NSViewRepresentable {
    var dark: Bool
    var english: Bool

    func makeNSView(context: Context) -> LoginRegionMapView { LoginRegionMapView() }
    func updateNSView(_ nsView: LoginRegionMapView, context: Context) {
        nsView.dark = dark
        nsView.english = english
        nsView.needsDisplay = true
    }
}

private struct Point3D {
    var vx: CGFloat
    var vy: CGFloat
    var vz: CGFloat
    var continent: Int = 0
}

private struct Project3D {
    var sx: CGFloat
    var sy: CGFloat
    var z: CGFloat
}

private struct RouteArc {
    var a: LoginPublicRegion
    var b: LoginPublicRegion
    var samples: [Point3D]
}

private final class LoginRegionMapView: NSView {
    var dark = true
    var english = false { didSet { if oldValue != english { updateRegionTooltips() } } }
    private var tooltipStrings: [NSString] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?

    // 3D rotation state (Polar spin & view pitch angle)
    private var rotY: CGFloat = 0.3
    private var rotX: CGFloat = 0.28
    private var velY: CGFloat = 0
    private var velX: CGFloat = 0
    private var isDragging = false
    private var lastMouseLocation = NSPoint.zero

    private static let RAD = CGFloat.pi / 180.0
    private static let TAU = CGFloat.pi * 2.0
    private static let AXIAL_TILT: CGFloat = -0.409 // ~23.44° real Earth axial tilt

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateAnimation()
            })
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateAnimation() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let observer = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimation() }

    override func layout() {
        super.layout()
        updateRegionTooltips()
        needsDisplay = true
    }

    private func updateAnimation() {
        timer?.invalidate()
        timer = nil
        guard window?.isVisible == true, window?.occlusionState.contains(.visible) == true,
              NSApp.isActive, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            needsDisplay = true
            return
        }
        let next = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isDragging {
                self.rotY += 0.0025 + self.velY
                self.rotX += self.velX
                self.velY *= 0.94
                self.velX *= 0.94
                self.rotX = max(-0.8, min(0.8, self.rotX))
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    // Pointer mouse drag interaction
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        isDragging = true
        lastMouseLocation = loc
        velY = 0
        velX = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let dx = loc.x - lastMouseLocation.x
        let dy = loc.y - lastMouseLocation.y
        rotY += dx * 0.006
        rotX = max(-0.8, min(0.8, rotX + dy * 0.006))
        velY = dx * 0.002
        velX = dy * 0.002
        lastMouseLocation = loc
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    private func project3D(_ vx: CGFloat, _ vy: CGFloat, _ vz: CGFloat,
                           spinY: CGFloat, pitchX: CGFloat,
                           cx: CGFloat, cy: CGFloat, radius: CGFloat) -> Project3D {
        let cosSpin = cos(spinY), sinSpin = sin(spinY)
        let cosTilt = cos(Self.AXIAL_TILT), sinTilt = sin(Self.AXIAL_TILT)
        let cosPitch = cos(pitchX), sinPitch = sin(pitchX)

        // 1. Spin around polar Y axis
        let x1 = vx * cosSpin + vz * sinSpin
        let y1 = vy
        let z1 = -vx * sinSpin + vz * cosSpin

        // 2. 23.44° axial tilt around Z axis
        let x2 = x1 * cosTilt - y1 * sinTilt
        let y2 = x1 * sinTilt + y1 * cosTilt
        let z2 = z1

        // 3. View pitch tilt around X axis
        let x3 = x2
        let y3 = y2 * cosPitch - z2 * sinPitch
        let z3 = y2 * sinPitch + z2 * cosPitch

        return Project3D(
            sx: cx + x3 * radius,
            sy: cy - y3 * radius,
            z: z3
        )
    }

    private func updateRegionTooltips() {
        removeAllToolTips()
        tooltipStrings.removeAll()
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        let radius = min(bounds.width, bounds.height) * 0.40

        for region in LoginPublicRegion.locations {
            let phi = region.latitude * Self.RAD
            let lam = region.longitude * Self.RAD
            let cosPhi = cos(phi)
            let p = project3D(cosPhi * sin(lam), sin(phi), cosPhi * cos(lam),
                              spinY: rotY, pitchX: rotX, cx: cx, cy: cy, radius: radius)
            guard p.z > 0.05 else { continue }
            let names = LoginPublicRegion.all.filter { $0.latitude == region.latitude && $0.longitude == region.longitude }
                .map { (english ? $0.en : $0.zh) + " · " + $0.id + "\n" + $0.coordinates }
                .joined(separator: "\n")
            let tooltip = names as NSString
            tooltipStrings.append(tooltip)
            addToolTip(NSRect(x: p.sx - 8, y: p.sy - 8, width: 16, height: 16), owner: tooltip, userData: nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Container Background Fill
        NSColor(dark ? LoginPalette.bg(true) : LoginPalette.bg(false)).setFill()
        bounds.fill()

        let width = bounds.width
        let height = bounds.height
        guard width > 20, height > 20 else { return }

        let cx = width / 2
        let cy = height / 2
        let radius = min(width, height) * 0.40

        let nodeColor = NSColor(Color(hex: dark ? "ff6600" : "ff4500"))
        let lineColor = NSColor(Color(hex: dark ? "ff6600" : "ff4500")).withAlphaComponent(0.55)
        let oceanColor = NSColor(Color(hex: dark ? "0b1219" : "edf3f8"))
        let oceanEdgeColor = NSColor(Color(hex: dark ? "162330" : "cbdbe6"))
        let graticuleColor = NSColor(Color(hex: dark ? "78a5c8" : "142841")).withAlphaComponent(dark ? 0.22 : 0.35)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // 1. Atmosphere Outer Glow
        let glowColors = [nodeColor.withAlphaComponent(0.14).cgColor, CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
        if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(glowGrad,
                                   startCenter: CGPoint(x: cx, y: cy), startRadius: radius * 0.85,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: radius * 1.22,
                                   options: [.drawsAfterEndLocation])
        }

        // 2. 3D Globe Surface Fill
        let bodyColors = [oceanColor.cgColor, oceanColor.cgColor, oceanEdgeColor.cgColor] as CFArray
        if let bodyGrad = CGGradient(colorsSpace: colorSpace, colors: bodyColors, locations: [0.0, 0.65, 1.0]) {
            ctx.drawRadialGradient(bodyGrad,
                                   startCenter: CGPoint(x: cx - radius * 0.3, y: cy - radius * 0.3), startRadius: radius * 0.1,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: radius,
                                   options: [.drawsAfterEndLocation])
        }

        // Atmosphere Rim Border
        nodeColor.withAlphaComponent(0.35).setStroke()
        let rimPath = NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        rimPath.lineWidth = 1.2
        rimPath.stroke()

        // Tilted Polar Axis Line (23.44°)
        let poleNorth = project3D(0, 1.13, 0, spinY: rotY, pitchX: rotX, cx: cx, cy: cy, radius: radius)
        let poleSouth = project3D(0, -1.13, 0, spinY: rotY, pitchX: rotX, cx: cx, cy: cy, radius: radius)
        let axisPath = NSBezierPath()
        axisPath.move(to: NSPoint(x: poleNorth.sx, y: poleNorth.sy))
        axisPath.line(to: NSPoint(x: poleSouth.sx, y: poleSouth.sy))
        let pattern: [CGFloat] = [4, 4]
        axisPath.setLineDash(pattern, count: 2, phase: 0)
        nodeColor.withAlphaComponent(0.3).setStroke()
        axisPath.lineWidth = 1.0
        axisPath.stroke()

        // 3. Graticule Lines (Parallels & Meridians)
        graticuleColor.setStroke()
        for line in Self.graticules {
            let path = NSBezierPath()
            path.lineWidth = 0.95
            var drawing = false
            for pt in line {
                let p = project3D(pt.vx, pt.vy, pt.vz, spinY: rotY, pitchX: rotX, cx: cx, cy: cy, radius: radius)
                if p.z > 0.02 {
                    let pos = NSPoint(x: p.sx, y: p.sy)
                    if !drawing { path.move(to: pos); drawing = true }
                    else { path.line(to: pos) }
                } else { drawing = false }
            }
            path.stroke()
        }

        // 4. Land Dots (Multi-Color Continents)
        let baseDotR = max(0.9, radius * 0.009)
        for c in 0..<12 {
            let cColor = Self.continentColor(c, dark: dark)
            cColor.setFill()
            let path = NSBezierPath()
            for dot in Self.landDots {
                guard dot.continent == c else { continue }
                let p = project3D(dot.vx, dot.vy, dot.vz, spinY: rotY, pitchX: rotX, cx: cx, cy: cy, radius: radius)
                if p.z > 0.02 {
                    let r = baseDotR * (0.65 + p.z * 0.45)
                    path.appendOval(in: NSRect(x: p.sx - r, y: p.sy - r, width: r * 2, height: r * 2))
                }
            }
            path.fill()
        }

        // 5. 3D Great-Circle Network Arcs & Traveling Energy Particles
        lineColor.setStroke()
        let now = Date.timeIntervalSinceReferenceDate
        for (rIdx, route) in Self.routes.enumerated() {
            let path = NSBezierPath()
            path.lineWidth = 1.1
            var drawing = false
            for pt in route.samples {
                let p = project3D(pt.vx, pt.vy, pt.vz, spinY: rotY, pitchX: rotX, cx: cx, cy: cy, radius: radius)
                if p.z > 0.02 {
                    let pos = NSPoint(x: p.sx, y: p.sy)
                    if !drawing { path.move(to: pos); drawing = true }
                    else { path.line(to: pos) }
                } else { drawing = false }
            }
            path.stroke()

            // Traveling Light Particle
            if timer != nil, !route.samples.isEmpty {
                let progress = CGFloat((now / 3.0 + Double(rIdx) * 0.22).truncatingRemainder(dividingBy: 1.0))
                let sampleIdx = Int(progress * CGFloat(route.samples.count - 1))
                let pt = route.samples[sampleIdx]
                let p = project3D(pt.vx, pt.vy, pt.vz, spinY: rotY, pitchX: rotX, cx: cx, cy: cy, radius: radius)
                if p.z > 0.05 {
                    let alpha = sin(.pi * progress) * min(1.0, p.z * 2.0)
                    nodeColor.withAlphaComponent(alpha).setFill()
                    NSBezierPath(ovalIn: NSRect(x: p.sx - 2.5, y: p.sy - 2.5, width: 5.0, height: 5.0)).fill()
                }
            }
        }

        // 6. Project & Render OCI Region Nodes (Enlarged Orange Nodes + Bright White Center)
        for region in LoginPublicRegion.locations {
            let phi = region.latitude * Self.RAD
            let lam = region.longitude * Self.RAD
            let cosPhi = cos(phi)
            let p = project3D(cosPhi * sin(lam), sin(phi), cosPhi * cos(lam),
                              spinY: rotY, pitchX: rotX, cx: cx, cy: cy, radius: radius)
            guard p.z > 0.05 else { continue }

            let depthAlpha = min(1.0, p.z * 2.2)

            // Outer Pulsing Ring
            if timer != nil {
                let phase = Double(region.id.hashValue & 0xffff)
                let progress = CGFloat((now * 0.45 + phase * 0.001).truncatingRemainder(dividingBy: 1.0))
                let ringR = 4.0 + progress * 12.0
                nodeColor.withAlphaComponent((1.0 - progress) * 0.45 * depthAlpha).setStroke()
                let ringPath = NSBezierPath(ovalIn: NSRect(x: p.sx - ringR, y: p.sy - ringR, width: ringR * 2, height: ringR * 2))
                ringPath.lineWidth = 1.3
                ringPath.stroke()
            }

            // Glowing Halo
            let glowR: CGFloat = 12.0
            let haloColors = [nodeColor.withAlphaComponent(0.32 * depthAlpha).cgColor, CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
            if let haloGrad = CGGradient(colorsSpace: colorSpace, colors: haloColors, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(haloGrad,
                                       startCenter: CGPoint(x: p.sx, y: p.sy), startRadius: 0,
                                       endCenter: CGPoint(x: p.sx, y: p.sy), endRadius: glowR,
                                       options: [.drawsAfterEndLocation])
            }

            // Outer Orange Core (Enlarged)
            nodeColor.withAlphaComponent(depthAlpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.sx - 3.8, y: p.sy - 3.8, width: 7.6, height: 7.6)).fill()

            // Bright White Inner Beacon Center
            NSColor.white.withAlphaComponent(depthAlpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.sx - 1.8, y: p.sy - 1.8, width: 3.6, height: 3.6)).fill()
        }
    }

    private static func continentColor(_ continent: Int, dark: Bool) -> NSColor {
        if dark {
            switch continent {
            case 0: return NSColor(Color(hex: "38bdf8")) // 北美洲 Sky Blue
            case 1: return NSColor(Color(hex: "67e8f9")) // 格陵兰 Ice Cyan
            case 2: return NSColor(Color(hex: "fbbf24")) // 南美洲 Amber Gold
            case 3: return NSColor(Color(hex: "eab308")) // 非洲 Sun Gold
            case 4: return NSColor(Color(hex: "34d399")) // 欧亚大陆 Emerald Green
            case 5: return NSColor(Color(hex: "a3e635")) // 东南亚 Lime Green
            case 6: return NSColor(Color(hex: "c084fc")) // 大洋洲 Purple
            case 7: return NSColor(Color(hex: "e879f9")) // 新西兰 Orchid
            case 8: return NSColor(Color(hex: "fb7185")) // 日本 Rose Pink
            case 9: return NSColor(Color(hex: "2dd4bf")) // 英国 Teal
            case 10: return NSColor(Color(hex: "eab308")) // 马达加斯加
            default: return NSColor(Color(hex: "34d399"))
            }
        } else {
            switch continent {
            case 0: return NSColor(Color(hex: "0284c7")) // 北美洲 Sky Blue
            case 1: return NSColor(Color(hex: "0891b2")) // 格陵兰 Ice Cyan
            case 2: return NSColor(Color(hex: "d97706")) // 南美洲 Amber
            case 3: return NSColor(Color(hex: "ca8a04")) // 非洲 Golden Bronze
            case 4: return NSColor(Color(hex: "059669")) // 欧亚大陆 Emerald Green
            case 5: return NSColor(Color(hex: "65a30d")) // 东南亚 Lime Green
            case 6: return NSColor(Color(hex: "7c3aed")) // 大洋洲 Purple
            case 7: return NSColor(Color(hex: "9333ea")) // 新西兰 Violet
            case 8: return NSColor(Color(hex: "e11d48")) // 日本 Rose Red
            case 9: return NSColor(Color(hex: "0d9488")) // 英国 Teal
            case 10: return NSColor(Color(hex: "ca8a04")) // 马达加斯加
            default: return NSColor(Color(hex: "059669"))
            }
        }
    }

    private static let routePairs = [
        ("us-phoenix-1", "us-ashburn-1"), ("us-ashburn-1", "uk-london-1"),
        ("uk-london-1", "eu-frankfurt-1"), ("eu-frankfurt-1", "me-jeddah-1"),
        ("me-jeddah-1", "ap-mumbai-1"), ("ap-mumbai-1", "ap-singapore-1"),
        ("ap-singapore-1", "ap-tokyo-1"), ("ap-tokyo-1", "ap-sydney-1")
    ]

    private static let routes: [RouteArc] = {
        var result: [RouteArc] = []
        for pair in routePairs {
            guard let rA = LoginPublicRegion.all.first(where: { $0.id == pair.0 }),
                  let rB = LoginPublicRegion.all.first(where: { $0.id == pair.1 }) else { continue }
            let phiA = rA.latitude * RAD, lamA = rA.longitude * RAD
            let phiB = rB.latitude * RAD, lamB = rB.longitude * RAD
            let cosPhiA = cos(phiA), cosPhiB = cos(phiB)
            let vA = Point3D(vx: cosPhiA * sin(lamA), vy: sin(phiA), vz: cosPhiA * cos(lamA))
            let vB = Point3D(vx: cosPhiB * sin(lamB), vy: sin(phiB), vz: cosPhiB * cos(lamB))

            var samples: [Point3D] = []
            let numSamples = 24
            let dotVal = max(-1.0, min(1.0, vA.vx * vB.vx + vA.vy * vB.vy + vA.vz * vB.vz))
            let omega = acos(dotVal)
            let sinOmega = sin(omega)

            for s in 0...numSamples {
                let t = CGFloat(s) / CGFloat(numSamples)
                let scaleA = sinOmega > 0.001 ? sin((1 - t) * omega) / sinOmega : (1 - t)
                let scaleB = sinOmega > 0.001 ? sin(t * omega) / sinOmega : t
                let vx = vA.vx * scaleA + vB.vx * scaleB
                let vy = vA.vy * scaleA + vB.vy * scaleB
                let vz = vA.vz * scaleA + vB.vz * scaleB
                let h = 1.0 + 0.18 * sin(.pi * t)
                samples.append(Point3D(vx: vx * h, vy: vy * h, vz: vz * h))
            }
            result.append(RouteArc(a: rA, b: rB, samples: samples))
        }
        return result
    }()

    private static func getLandContinentIndex(longitude: CGFloat, latitude: CGFloat) -> Int {
        for (k, polygon) in land.enumerated() {
            var inside = false
            var j = polygon.count - 1
            for i in polygon.indices {
                let a = polygon[i], b = polygon[j]
                if (a[1] > latitude) != (b[1] > latitude),
                   longitude < (b[0] - a[0]) * (latitude - a[1]) / (b[1] - a[1]) + a[0] {
                    inside.toggle()
                }
                j = i
            }
            if inside { return k }
        }
        return -1
    }

    private static let landDots: [Point3D] = {
        var points: [Point3D] = []
        for latitude in stride(from: CGFloat(-72), through: 76, by: 2.4) {
            let phi = latitude * RAD
            let cosPhi = cos(phi)
            if cosPhi < 0.05 { continue }
            let lngStep = 2.4 / cosPhi
            for longitude in stride(from: CGFloat(-180), through: 180, by: lngStep) {
                let cIdx = getLandContinentIndex(longitude: longitude, latitude: latitude)
                if cIdx >= 0 {
                    let lam = longitude * RAD
                    points.append(Point3D(vx: cosPhi * sin(lam), vy: sin(phi), vz: cosPhi * cos(lam), continent: cIdx))
                }
            }
        }
        for (k, polygon) in land.enumerated() {
            for pt in polygon {
                let lng = pt[0], lat = pt[1]
                let phi = lat * RAD, lam = lng * RAD
                let cosPhi = cos(phi)
                points.append(Point3D(vx: cosPhi * sin(lam), vy: sin(phi), vz: cosPhi * cos(lam), continent: k))
            }
        }
        return points
    }()

    private static let graticules: [[Point3D]] = {
        var lines: [[Point3D]] = []
        for lat in [-60.0, -30.0, 0.0, 30.0, 60.0] {
            var line: [Point3D] = []
            let phi = CGFloat(lat) * RAD
            let cosPhi = cos(phi), sinPhi = sin(phi)
            for lng in stride(from: CGFloat(-180), through: 180, by: 8.0) {
                let lam = lng * RAD
                line.append(Point3D(vx: cosPhi * sin(lam), vy: sinPhi, vz: cosPhi * cos(lam)))
            }
            lines.append(line)
        }
        for lng in stride(from: CGFloat(-180), through: 180, by: 30.0) {
            var line: [Point3D] = []
            let lam = lng * RAD
            let sinLam = sin(lam), cosLam = cos(lam)
            for lat in stride(from: CGFloat(-80), through: 80, by: 8.0) {
                let phi = lat * RAD
                let cosPhi = cos(phi)
                line.append(Point3D(vx: cosPhi * sinLam, vy: sin(phi), vz: cosPhi * cosLam))
            }
            lines.append(line)
        }
        return lines
    }()

    // Same simplified outlines as Vue `views/auth/loginMap.js`.
    private static let land: [[[CGFloat]]] = [
        [[-168,65],[-165,60],[-158,57],[-152,58],[-146,60],[-138,59],[-131,53],[-125,49],[-124,42],[-120,34],[-117,32],[-110,24],[-105,20],[-97,16],[-92,15],[-88,16],[-87,21],[-91,21],[-95,19],[-97,23],[-97,26],[-94,29],[-89,29],[-84,30],[-81,25],[-80,32],[-76,35],[-70,42],[-67,45],[-60,47],[-56,51],[-56,54],[-64,60],[-78,62],[-78,55],[-82,55],[-86,66],[-95,68],[-105,68],[-115,70],[-125,70],[-135,69],[-145,70],[-156,71],[-166,68]],
        [[-45,60],[-52,64],[-53,68],[-62,70],[-68,76],[-62,82],[-40,83],[-24,80],[-20,73],[-30,68],[-42,61]],
        [[-81,-4],[-79,0],[-77,8],[-72,12],[-62,10],[-60,8],[-52,5],[-50,0],[-44,-2],[-38,-5],[-35,-8],[-39,-13],[-39,-18],[-48,-25],[-53,-34],[-58,-38],[-62,-40],[-65,-45],[-68,-50],[-70,-54],[-75,-52],[-74,-45],[-73,-37],[-71,-30],[-70,-20],[-75,-15],[-81,-6]],
        [[-17,15],[-16,20],[-12,28],[-10,32],[-5,36],[10,37],[20,32],[28,31],[33,28],[35,23],[38,18],[43,12],[51,12],[51,5],[42,-1],[40,-10],[35,-20],[32,-26],[27,-34],[20,-35],[18,-30],[13,-20],[9,-1],[3,6],[-8,4],[-13,9]],
        [[-10,36],[-9,43],[-2,48],[3,51],[6,53],[9,54],[11,58],[16,60],[22,60],[30,60],[28,66],[21,70],[32,71],[46,68],[62,70],[76,73],[92,75],[106,77],[116,74],[132,72],[146,70],[160,70],[170,66],[179,65],[172,60],[162,58],[155,52],[142,48],[135,43],[130,35],[122,32],[120,25],[110,20],[105,10],[100,6],[97,16],[90,22],[82,17],[77,8],[72,20],[66,25],[57,25],[50,30],[45,37],[36,36],[30,41],[26,38],[22,40],[16,38],[13,45],[8,44],[3,42],[-2,37]],
        [[95,5],[105,-6],[115,-9],[125,-9],[135,-5],[141,-3],[141,-9],[131,-8],[120,-10],[110,-8],[100,0]],
        [[113,-22],[114,-35],[118,-35],[129,-32],[137,-35],[141,-38],[147,-39],[151,-37],[153,-28],[145,-15],[142,-11],[136,-12],[130,-11],[125,-14],[118,-20]],
        [[172,-41],[174,-37],[178,-38],[176,-41],[174,-46],[168,-46],[167,-44]],
        [[130,31],[134,34],[139,35],[141,39],[145,44],[142,42],[137,37],[132,34]],
        [[-5,50],[-6,55],[-3,58],[-1,56],[1,53],[1,51],[-4,50]],
        [[43,-12],[50,-15],[50,-25],[45,-25],[43,-17]],
        [[120,18],[124,18],[126,10],[122,6],[119,11]]
    ]
}

private struct LoginPublicRegion: Identifiable {
    let id: String
    let zh: String
    let en: String
    let latitude: CGFloat
    let longitude: CGFloat
    var coordinates: String {
        String(format: "%.4f° %@ · %.4f° %@", Double(abs(latitude)), latitude < 0 ? "S" : "N",
               Double(abs(longitude)), longitude < 0 ? "W" : "E")
    }
    static let locations = all.reduce(into: [LoginPublicRegion]()) { locations, region in
        if !locations.contains(where: { $0.latitude == region.latitude && $0.longitude == region.longitude }) {
            locations.append(region)
        }
    }
    static let all: [LoginPublicRegion] = [
        LoginPublicRegion(id: "ap-sydney-1", zh: "悉尼", en: "Sydney", latitude: -33.8688, longitude: 151.2093),
        LoginPublicRegion(id: "ap-melbourne-1", zh: "墨尔本", en: "Melbourne", latitude: -37.8136, longitude: 144.9631),
        LoginPublicRegion(id: "sa-saopaulo-1", zh: "圣保罗", en: "São Paulo", latitude: -23.5505, longitude: -46.6333),
        LoginPublicRegion(id: "sa-vinhedo-1", zh: "维涅杜", en: "Vinhedo", latitude: -23.0304, longitude: -46.9834),
        LoginPublicRegion(id: "ca-montreal-1", zh: "蒙特利尔", en: "Montréal", latitude: 45.5017, longitude: -73.5673),
        LoginPublicRegion(id: "ca-toronto-1", zh: "多伦多", en: "Toronto", latitude: 43.6532, longitude: -79.3832),
        LoginPublicRegion(id: "sa-santiago-1", zh: "圣地亚哥", en: "Santiago", latitude: -33.4489, longitude: -70.6693),
        LoginPublicRegion(id: "sa-valparaiso-1", zh: "瓦尔帕莱索", en: "Valparaíso", latitude: -33.0472, longitude: -71.6127),
        LoginPublicRegion(id: "sa-bogota-1", zh: "波哥大", en: "Bogotá", latitude: 4.711, longitude: -74.0721),
        LoginPublicRegion(id: "eu-paris-1", zh: "巴黎", en: "Paris", latitude: 48.8566, longitude: 2.3522),
        LoginPublicRegion(id: "eu-marseille-1", zh: "马赛", en: "Marseille", latitude: 43.2965, longitude: 5.3698),
        LoginPublicRegion(id: "eu-frankfurt-1", zh: "法兰克福", en: "Frankfurt", latitude: 50.1109, longitude: 8.6821),
        LoginPublicRegion(id: "ap-hyderabad-1", zh: "海得拉巴", en: "Hyderabad", latitude: 17.385, longitude: 78.4867),
        LoginPublicRegion(id: "ap-mumbai-1", zh: "孟买", en: "Mumbai", latitude: 19.076, longitude: 72.8777),
        LoginPublicRegion(id: "ap-batam-1", zh: "巴淡", en: "Batam", latitude: 1.1074, longitude: 104.03),
        LoginPublicRegion(id: "il-jerusalem-1", zh: "耶路撒冷", en: "Jerusalem", latitude: 31.7683, longitude: 35.2137),
        LoginPublicRegion(id: "eu-milan-1", zh: "米兰", en: "Milan", latitude: 45.4642, longitude: 9.19),
        LoginPublicRegion(id: "eu-turin-1", zh: "都灵", en: "Turin", latitude: 45.0703, longitude: 7.6869),
        LoginPublicRegion(id: "ap-osaka-1", zh: "大阪", en: "Osaka", latitude: 34.6937, longitude: 135.5023),
        LoginPublicRegion(id: "ap-tokyo-1", zh: "东京", en: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        LoginPublicRegion(id: "ap-kulai-2", zh: "古来", en: "Kulai", latitude: 1.6629, longitude: 103.5999),
        LoginPublicRegion(id: "mx-queretaro-1", zh: "克雷塔罗", en: "Querétaro", latitude: 20.5888, longitude: -100.3899),
        LoginPublicRegion(id: "mx-monterrey-1", zh: "蒙特雷", en: "Monterrey", latitude: 25.6866, longitude: -100.3161),
        LoginPublicRegion(id: "af-casablanca-1", zh: "卡萨布兰卡", en: "Casablanca", latitude: 33.5731, longitude: -7.5898),
        LoginPublicRegion(id: "eu-amsterdam-1", zh: "阿姆斯特丹", en: "Amsterdam", latitude: 52.3676, longitude: 4.9041),
        LoginPublicRegion(id: "me-riyadh-1", zh: "利雅得", en: "Riyadh", latitude: 24.7136, longitude: 46.6753),
        LoginPublicRegion(id: "me-jeddah-1", zh: "吉达", en: "Jeddah", latitude: 21.4858, longitude: 39.1925),
        LoginPublicRegion(id: "eu-jovanovac-1", zh: "乔万诺瓦茨", en: "Jovanovac", latitude: 44.0501, longitude: 20.9507),
        LoginPublicRegion(id: "ap-singapore-1", zh: "新加坡", en: "Singapore", latitude: 1.3521, longitude: 103.8198),
        LoginPublicRegion(id: "ap-singapore-2", zh: "新加坡西部", en: "Singapore West", latitude: 1.3521, longitude: 103.8198),
        LoginPublicRegion(id: "af-johannesburg-1", zh: "约翰内斯堡", en: "Johannesburg", latitude: -26.2041, longitude: 28.0473),
        LoginPublicRegion(id: "ap-seoul-1", zh: "首尔", en: "Seoul", latitude: 37.5665, longitude: 126.978),
        LoginPublicRegion(id: "ap-chuncheon-1", zh: "春川", en: "Chuncheon", latitude: 37.8747, longitude: 127.7342),
        LoginPublicRegion(id: "eu-madrid-1", zh: "马德里", en: "Madrid", latitude: 40.4168, longitude: -3.7038),
        LoginPublicRegion(id: "eu-madrid-3", zh: "马德里 3", en: "Madrid 3", latitude: 40.4168, longitude: -3.7038),
        LoginPublicRegion(id: "eu-stockholm-1", zh: "斯德哥尔摩", en: "Stockholm", latitude: 59.3293, longitude: 18.0686),
        LoginPublicRegion(id: "eu-zurich-1", zh: "苏黎世", en: "Zurich", latitude: 47.3769, longitude: 8.5417),
        LoginPublicRegion(id: "me-abudhabi-1", zh: "阿布扎比", en: "Abu Dhabi", latitude: 24.4539, longitude: 54.3773),
        LoginPublicRegion(id: "me-dubai-1", zh: "迪拜", en: "Dubai", latitude: 25.2048, longitude: 55.2708),
        LoginPublicRegion(id: "uk-london-1", zh: "伦敦", en: "London", latitude: 51.5074, longitude: -0.1278),
        LoginPublicRegion(id: "uk-cardiff-1", zh: "纽波特", en: "Newport", latitude: 51.5877, longitude: -2.9984),
        LoginPublicRegion(id: "us-ashburn-1", zh: "阿什本", en: "Ashburn", latitude: 39.0438, longitude: -77.4874),
        LoginPublicRegion(id: "us-chicago-1", zh: "芝加哥", en: "Chicago", latitude: 41.8781, longitude: -87.6298),
        LoginPublicRegion(id: "us-phoenix-1", zh: "凤凰城", en: "Phoenix", latitude: 33.4484, longitude: -112.074),
        LoginPublicRegion(id: "us-sanjose-1", zh: "圣何塞", en: "San Jose", latitude: 37.3382, longitude: -121.8863),
    ]
}
