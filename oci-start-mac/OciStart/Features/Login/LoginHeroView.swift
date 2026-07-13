import SwiftUI
import AppKit
import Combine

/// Left hero panel — web `#heroSvg` + `heroNetCanvas` parity:
/// node net animation, eye tracking, shy password look-down, cry tears.
struct LoginHeroView: View {
    var dark: Bool
    var crying: Bool = false
    /// When true (password field focused), pupils look down (web shyMode).
    var shyMode: Bool = false

    @State private var tick: CGFloat = 0
    @State private var nodes: [HeroNetNode] = []
    @State private var panelSize: CGSize = .zero
    @State private var tearPhase: CGFloat = 0
    /// Mouse in local hero coords (top-left).
    @State private var localPointer: CGPoint? = nil

    private let viewBox: CGFloat = 520

    var body: some View {
        ZStack {
            // hero-panel background (web)
            LoginPalette.panel(dark)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(hex: dark ? "4d9eff" : "6366f1").opacity(dark ? 0.14 : 0.12),
                    Color.clear
                ]),
                center: UnitPoint(x: 0.3, y: 0.2),
                startRadius: 10,
                endRadius: 260
            )
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(hex: dark ? "8b5cf6" : "0ea5e9").opacity(0.10),
                    Color.clear
                ]),
                center: UnitPoint(x: 0.8, y: 0.8),
                startRadius: 10,
                endRadius: 240
            )

            // Animated node network (web heroNetCanvas)
            HeroNetCanvas(nodes: nodes, dark: dark)
                .opacity(0.95)

            // Characters: web viewBox 520, shared bottom baseline y=410
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height) / viewBox
                let ox = (geo.size.width - viewBox * s) / 2
                let oy = (geo.size.height - viewBox * s) / 2
                let scale = s
                // Web SVG: all characters rest on y=410 — centerY = baseline - height/2
                let baseline: CGFloat = 410
                let look = lookOffsets(panelSize: geo.size)

                ZStack(alignment: .topLeading) {
                    // back → front; bottoms on one line
                    mainCharacter(scale: scale, look: look, tearY: tearPhase)
                        .position(
                            x: ox + 278 * scale,
                            y: oy + (baseline - 149) * scale
                        )
                    rackCharacter(scale: scale, look: look, tearY: tearPhase)
                        .position(
                            x: ox + 385 * scale,
                            y: oy + (baseline - 116) * scale
                        )
                    satCharacter(scale: scale, look: look, tearY: tearPhase)
                        .position(
                            x: ox + 462 * scale,
                            y: oy + (baseline - 52) * scale
                        )
                    cloudCharacter(scale: scale, look: look, tearY: tearPhase)
                        .position(
                            x: ox + 209 * scale,
                            y: oy + (baseline - 85) * scale
                        )
                    buddyCharacter(scale: scale, look: look, tearY: tearPhase)
                        .position(
                            x: ox + 72 * scale,
                            y: oy + (baseline - 27) * scale
                        )
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(HeroMouseTracker(localPoint: $localPointer))
                .onAppear {
                    panelSize = geo.size
                    seedNodes(for: geo.size)
                }
                .onChange(of: geo.size) { newSize in
                    panelSize = newSize
                    seedNodes(for: newSize)
                }
            }
            .padding(28)
            .shadow(color: Color.black.opacity(dark ? 0.35 : 0.12), radius: 18, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            stepNetwork()
            if crying {
                tearPhase = tearPhase + 0.08
                if tearPhase > 1 { tearPhase = 0 }
            } else {
                tearPhase = 0
            }
            tick += 1
        }
        .modifier(CryShakeModifier(active: crying))
    }

    // MARK: - Look direction (web pupil track)

    private func lookOffsets(panelSize: CGSize) -> (CGFloat, CGFloat) {
        if crying {
            return (0, 1)
        }
        guard let ptr = localPointer else {
            if shyMode { return (0, 0.85) }
            return (0, 0)
        }
        let cx = panelSize.width / 2
        let cy = panelSize.height / 2
        var dx = (ptr.x - cx) / max(panelSize.width * 0.5, 1)
        var dy = (ptr.y - cy) / max(panelSize.height * 0.5, 1)
        if shyMode {
            dy = max(dy, 0.55)
        }
        let len = max(0.0001, sqrt(dx * dx + dy * dy))
        dx /= len
        dy /= len
        return (dx * 0.85, dy * 0.85)
    }

    private func pupilOffset(look: (CGFloat, CGFloat), max: CGFloat, scale: CGFloat) -> CGSize {
        CGSize(width: look.0 * max * scale, height: look.1 * max * scale)
    }

    // MARK: - Characters

    private func rackCharacter(scale: CGFloat, look: (CGFloat, CGFloat), tearY: CGFloat) -> some View {
        let w: CGFloat = 74 * scale
        let h: CGFloat = 232 * scale
        let eyeR: CGFloat = 11.5 * scale
        let pr: CGFloat = 4.4 * scale
        let po = pupilOffset(look: look, max: 5, scale: scale)
        return ZStack {
            RoundedRectangle(cornerRadius: 20 * scale)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "2A3344"), Color(hex: "151B26")]),
                    startPoint: .top, endPoint: .bottom
                ))
            glassOverlay(radius: 20 * scale)
            // status LED
            Circle().fill(Color(hex: "34D399"))
                .frame(width: 7.6 * scale, height: 7.6 * scale)
                .offset(x: 0, y: -h * 0.38)
            faceEyes(eyeR: eyeR, pupilR: pr, spacing: 34 * scale, pupilOff: po)
                .offset(y: -h * 0.12)
            mouth(happy: !crying, width: 26 * scale, stroke: Color(hex: "E2E8F0"), line: 3.8 * scale)
                .offset(y: h * 0.02)
            if crying {
                tears(pairSpacing: 50 * scale, phase: tearY, scale: scale * 0.85)
                    .offset(y: -h * 0.02)
            }
            VStack(spacing: 8 * scale) {
                Capsule().fill(Color(hex: "38BDF8").opacity(0.5)).frame(width: 40 * scale, height: 5 * scale)
                Capsule().fill(Color(hex: "64748B").opacity(0.45)).frame(width: 40 * scale, height: 5 * scale)
                Capsule().fill(Color(hex: "64748B").opacity(0.35)).frame(width: 26 * scale, height: 5 * scale)
            }
            .offset(y: h * 0.28)
        }
        .frame(width: w, height: h)
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 8)
    }

    private func mainCharacter(scale: CGFloat, look: (CGFloat, CGFloat), tearY: CGFloat) -> some View {
        let w: CGFloat = 156 * scale
        let h: CGFloat = 298 * scale
        let eyeR: CGFloat = 16 * scale
        let pr: CGFloat = 6.2 * scale
        let po = pupilOffset(look: look, max: 6.5, scale: scale)
        return ZStack {
            RoundedRectangle(cornerRadius: 36 * scale)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "6D8CFF"), Color(hex: "4D6BFF"), Color(hex: "3B5BDB")]),
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            glassOverlay(radius: 36 * scale)
            // antenna
            VStack(spacing: 0) {
                Circle().fill(Color(hex: "E0E7FF")).frame(width: 11 * scale, height: 11 * scale)
                Rectangle().fill(Color(hex: "C7D2FE")).frame(width: 3 * scale, height: 12 * scale)
                Capsule()
                    .stroke(Color(hex: "C7D2FE").opacity(0.8), lineWidth: 3)
                    .frame(width: 52 * scale, height: 17 * scale)
            }
            .offset(y: -h * 0.48)
            // LEDs
            HStack(spacing: 4 * scale) {
                RoundedRectangle(cornerRadius: 2.5 * scale).fill(Color(hex: "67E8F9")).frame(width: 10 * scale, height: 10 * scale)
                RoundedRectangle(cornerRadius: 2.5 * scale).fill(Color(hex: "A5B4FC").opacity(0.9)).frame(width: 10 * scale, height: 10 * scale)
                RoundedRectangle(cornerRadius: 2.5 * scale).fill(Color.white.opacity(0.3)).frame(width: 10 * scale, height: 10 * scale)
            }
            .offset(x: -w * 0.22, y: -h * 0.32)
            faceEyes(eyeR: eyeR, pupilR: pr, spacing: 60 * scale, pupilOff: po)
                .offset(y: -h * 0.12)
            mouth(happy: !crying, width: 46 * scale, stroke: Color(hex: "0F172A"), line: 7.5 * scale, smileDeep: true)
                .offset(y: h * 0.02)
            if crying {
                tears(pairSpacing: 84 * scale, phase: tearY, scale: scale)
                    .offset(y: -h * 0.02)
            }
            VStack(spacing: 8 * scale) {
                Capsule().fill(Color.white.opacity(0.18)).frame(width: 80 * scale, height: 7 * scale)
                Capsule().fill(Color.white.opacity(0.12)).frame(width: 52 * scale, height: 6 * scale)
            }
            .offset(y: h * 0.32)
        }
        .frame(width: w, height: h)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 10)
    }

    private func satCharacter(scale: CGFloat, look: (CGFloat, CGFloat), tearY: CGFloat) -> some View {
        let r: CGFloat = 52 * scale
        let po = pupilOffset(look: look, max: 4.5, scale: scale)
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "67E8F9"), Color(hex: "38BDF8")]),
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Circle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.2), Color.clear]),
                    startPoint: .top, endPoint: .bottom
                ))
            // ring
            Ellipse()
                .stroke(Color(hex: "E0F2FE").opacity(0.5), lineWidth: 2.2 * scale)
                .frame(width: 116 * scale, height: 28 * scale)
                .rotationEffect(.degrees(-14))
            faceEyes(eyeR: 11 * scale, pupilR: 4.2 * scale, spacing: 38 * scale, pupilOff: po)
                .offset(y: -10 * scale)
            mouth(happy: !crying, width: 28 * scale, stroke: Color(hex: "0F172A"), line: 5 * scale, flatHappy: true)
                .offset(y: 16 * scale)
            if crying {
                tears(pairSpacing: 54 * scale, phase: tearY, scale: scale * 0.9)
                    .offset(y: 4 * scale)
            }
        }
        .frame(width: r * 2, height: r * 2)
        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 6)
    }

    private func cloudCharacter(scale: CGFloat, look: (CGFloat, CGFloat), tearY: CGFloat) -> some View {
        // Web cloud path roughly bbox ~48..370 x 240..410 → center ~209, 325, size ~322x170
        let po = pupilOffset(look: look, max: 6, scale: scale)
        return ZStack {
            CloudShape()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "A78BFA"), Color(hex: "7C5CFC")]),
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 322 * scale, height: 170 * scale)
            CloudShape()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.18), Color.clear]),
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 322 * scale, height: 170 * scale)
            faceEyes(eyeR: 15 * scale, pupilR: 5.8 * scale, spacing: 52 * scale, pupilOff: po)
                .offset(x: -35 * scale, y: -5 * scale)
            mouth(happy: !crying, width: 44 * scale, stroke: Color(hex: "0F172A"), line: 7.5 * scale, smileDeep: true)
                .offset(x: -35 * scale, y: 28 * scale)
            if crying {
                tears(pairSpacing: 76 * scale, phase: tearY, scale: scale)
                    .offset(x: -35 * scale, y: 12 * scale)
            }
        }
        .frame(width: 322 * scale, height: 170 * scale)
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
    }

    private func buddyCharacter(scale: CGFloat, look: (CGFloat, CGFloat), tearY: CGFloat) -> some View {
        let w: CGFloat = 120 * scale
        let h: CGFloat = 54 * scale
        let po = pupilOffset(look: look, max: 4.2, scale: scale)
        return ZStack {
            RoundedRectangle(cornerRadius: 18 * scale)
                .fill(Color(hex: "0F172A").opacity(0.95))
            glassOverlay(radius: 18 * scale)
            Circle().fill(Color(hex: "34D399"))
                .frame(width: 5.6 * scale, height: 5.6 * scale)
                .offset(x: -w * 0.38, y: -h * 0.28)
            faceEyes(eyeR: 10 * scale, pupilR: 4.2 * scale, spacing: 30 * scale, pupilOff: po)
                .offset(x: -w * 0.12, y: -2 * scale)
            mouth(happy: !crying, width: 14 * scale, stroke: Color(hex: "E2E8F0"), line: 2.6 * scale)
                .offset(x: -w * 0.12, y: 12 * scale)
            if crying {
                tears(pairSpacing: 46 * scale, phase: tearY, scale: scale * 0.7)
                    .offset(x: -w * 0.12, y: 6 * scale)
            }
            VStack(spacing: 0) {
                Text("oci")
                    .font(.system(size: 11 * scale, weight: .heavy))
                    .foregroundColor(Color(hex: "93C5FD"))
                Text("start")
                    .font(.system(size: 11 * scale, weight: .heavy))
                    .foregroundColor(Color(hex: "E2E8F0"))
            }
            .offset(x: w * 0.28, y: 0)
        }
        .frame(width: w, height: h)
        .shadow(color: Color.black.opacity(0.16), radius: 10, y: 6)
    }

    // MARK: - Face pieces

    private func faceEyes(eyeR: CGFloat, pupilR: CGFloat, spacing: CGFloat, pupilOff: CGSize) -> some View {
        HStack(spacing: spacing - eyeR * 2) {
            eye(eyeR, pupilR, pupilOff)
            eye(eyeR, pupilR, pupilOff)
        }
    }

    private func eye(_ r: CGFloat, _ pr: CGFloat, _ off: CGSize) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: r * 2, height: r * 2)
            Circle().fill(Color(hex: "0F172A"))
                .frame(width: pr * 2, height: pr * 2)
                .offset(x: off.width, y: off.height)
        }
        .frame(width: r * 2, height: r * 2)
        .clipShape(Circle())
    }

    private func mouth(
        happy: Bool,
        width: CGFloat,
        stroke: Color,
        line: CGFloat,
        smileDeep: Bool = false,
        flatHappy: Bool = false
    ) -> some View {
        Group {
            if flatHappy && happy {
                // satellite happy = flat line
                Capsule()
                    .fill(stroke)
                    .frame(width: width, height: line)
            } else {
                SmileShape(sad: !happy, deep: smileDeep)
                    .stroke(stroke, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: width, height: width * (smileDeep ? 0.42 : 0.38))
            }
        }
    }

    private func tears(pairSpacing: CGFloat, phase: CGFloat, scale: CGFloat) -> some View {
        let drop = (phase * 14 * scale)
        let op = Double(1 - phase)
        return HStack(spacing: pairSpacing) {
            Ellipse()
                .fill(Color(hex: "7DD3FC"))
                .frame(width: 5 * scale, height: 8 * scale)
                .offset(y: drop)
                .opacity(op)
            Ellipse()
                .fill(Color(hex: "7DD3FC"))
                .frame(width: 5 * scale, height: 8 * scale)
                .offset(y: drop)
                .opacity(op)
        }
    }

    private func glassOverlay(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(LinearGradient(
                gradient: Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)]),
                startPoint: .top, endPoint: .bottom
            ))
    }

    // MARK: - Network

    private func seedNodes(for size: CGSize) {
        let area = max(1, size.width * size.height)
        let count = max(18, min(36, Int(area / 14000)))
        nodes = (0..<count).map { _ in
            HeroNetNode(
                x: CGFloat.random(in: 0...max(1, size.width)),
                y: CGFloat.random(in: 0...max(1, size.height)),
                vx: CGFloat.random(in: -0.28...0.28),
                vy: CGFloat.random(in: -0.28...0.28),
                r: CGFloat.random(in: 1.2...3.0)
            )
        }
    }

    private func stepNetwork() {
        guard panelSize.width > 1, !nodes.isEmpty else { return }
        let w = panelSize.width
        let h = panelSize.height
        for i in nodes.indices {
            nodes[i].x += nodes[i].vx
            nodes[i].y += nodes[i].vy
            if nodes[i].x < -8 { nodes[i].x = w + 8 }
            if nodes[i].x > w + 8 { nodes[i].x = -8 }
            if nodes[i].y < -8 { nodes[i].y = h + 8 }
            if nodes[i].y > h + 8 { nodes[i].y = -8 }
        }
    }
}

// MARK: - Net canvas

private struct HeroNetNode: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var r: CGFloat
}

private struct HeroNetCanvas: View {
    var nodes: [HeroNetNode]
    var dark: Bool

    var body: some View {
        GeometryReader { geo in
            let maxDist = min(140, max(90, geo.size.width * 0.22))
            let lineColor = dark ? Color(hex: "4d9eff") : Color(hex: "6366f1")
            let nodeColor = dark ? Color(hex: "7dd3fc").opacity(0.85) : Color(hex: "4f46e5").opacity(0.75)
            ZStack {
                // lines (cap pairs for type-checker / perf)
                Path { path in
                    let limit = min(nodes.count, 36)
                    for i in 0..<limit {
                        for j in (i + 1)..<limit {
                            let dx = nodes[i].x - nodes[j].x
                            let dy = nodes[i].y - nodes[j].y
                            let dist = sqrt(dx * dx + dy * dy)
                            if dist > maxDist { continue }
                            path.move(to: CGPoint(x: nodes[i].x, y: nodes[i].y))
                            path.addLine(to: CGPoint(x: nodes[j].x, y: nodes[j].y))
                        }
                    }
                }
                .stroke(lineColor.opacity(dark ? 0.22 : 0.16), lineWidth: 1)

                ForEach(nodes) { n in
                    Circle()
                        .fill(lineColor.opacity(dark ? 0.12 : 0.10))
                        .frame(width: n.r * 6.4, height: n.r * 6.4)
                        .position(x: n.x, y: n.y)
                    Circle()
                        .fill(nodeColor)
                        .frame(width: n.r * 2, height: n.r * 2)
                        .position(x: n.x, y: n.y)
                }
            }
        }
    }
}

// MARK: - Cloud path (web GCP-style cloud)

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Normalized from web path M86,410 ... within bbox (48,240)-(370,410)
        // ViewBox path coords mapped into rect
        let minX: CGFloat = 48, maxX: CGFloat = 370
        let minY: CGFloat = 240, maxY: CGFloat = 410
        func sx(_ x: CGFloat) -> CGFloat { (x - minX) / (maxX - minX) * rect.width + rect.minX }
        func sy(_ y: CGFloat) -> CGFloat { (y - minY) / (maxY - minY) * rect.height + rect.minY }

        var p = Path()
        p.move(to: CGPoint(x: sx(86), y: sy(410)))
        p.addCurve(to: CGPoint(x: sx(48), y: sy(372)),
                   control1: CGPoint(x: sx(64), y: sy(410)),
                   control2: CGPoint(x: sx(48), y: sy(394)))
        p.addCurve(to: CGPoint(x: sx(82), y: sy(332)),
                   control1: CGPoint(x: sx(48), y: sy(352)),
                   control2: CGPoint(x: sx(62), y: sy(336)))
        p.addCurve(to: CGPoint(x: sx(140), y: sy(284)),
                   control1: CGPoint(x: sx(86), y: sy(304)),
                   control2: CGPoint(x: sx(110), y: sy(284)))
        p.addCurve(to: CGPoint(x: sx(216), y: sy(256)),
                   control1: CGPoint(x: sx(156), y: sy(260)),
                   control2: CGPoint(x: sx(186), y: sy(248)))
        p.addCurve(to: CGPoint(x: sx(282), y: sy(266)),
                   control1: CGPoint(x: sx(236), y: sy(240)),
                   control2: CGPoint(x: sx(266), y: sy(244)))
        p.addCurve(to: CGPoint(x: sx(330), y: sy(322)),
                   control1: CGPoint(x: sx(310), y: sy(270)),
                   control2: CGPoint(x: sx(330), y: sy(294)))
        p.addCurve(to: CGPoint(x: sx(370), y: sy(376)),
                   control1: CGPoint(x: sx(354), y: sy(328)),
                   control2: CGPoint(x: sx(370), y: sy(350)))
        p.addCurve(to: CGPoint(x: sx(328), y: sy(410)),
                   control1: CGPoint(x: sx(370), y: sy(398)),
                   control2: CGPoint(x: sx(352), y: sy(410)))
        p.closeSubpath()
        return p
    }
}

private struct SmileShape: Shape {
    var sad: Bool
    var deep: Bool = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if sad {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.2))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.2),
                control: CGPoint(x: rect.midX, y: rect.minY + (deep ? 0 : rect.height * 0.1))
            )
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.15))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.15),
                control: CGPoint(x: rect.midX, y: rect.maxY - (deep ? 0 : rect.height * 0.05))
            )
        }
        return p
    }
}

private struct CryShakeModifier: ViewModifier {
    var active: Bool
    @State private var x: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .onChange(of: active) { on in
                if on { runShake() } else { x = 0 }
            }
    }

    private func runShake() {
        let steps: [CGFloat] = [0, -3, 3, -3, 3, 0]
        for (i, v) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(i)) {
                withAnimation(.easeInOut(duration: 0.06)) { x = v }
            }
        }
    }
}

// MARK: - Local mouse tracker (eye follow)

private struct HeroMouseTracker: NSViewRepresentable {
    @Binding var localPoint: CGPoint?

    final class TrackView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        private var tracking: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking = tracking {
                removeTrackingArea(tracking)
            }
            let opts: NSTrackingArea.Options = [
                .activeInKeyWindow, .mouseMoved, .inVisibleRect, .mouseEnteredAndExited
            ]
            let area = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseMoved(with event: NSEvent) {
            // Convert to top-left SwiftUI coords inside this view
            let p = convert(event.locationInWindow, from: nil)
            let y = bounds.height - p.y
            onMove?(CGPoint(x: p.x, y: y))
        }

        override func mouseEntered(with event: NSEvent) {
            mouseMoved(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            onMove?(nil)
        }

        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil } // never steal clicks
    }

    func makeNSView(context: Context) -> TrackView {
        let v = TrackView()
        v.wantsLayer = true
        v.onMove = { pt in
            DispatchQueue.main.async { self.localPoint = pt }
        }
        return v
    }

    func updateNSView(_ nsView: TrackView, context: Context) {
        nsView.onMove = { pt in
            DispatchQueue.main.async { self.localPoint = pt }
        }
    }
}
