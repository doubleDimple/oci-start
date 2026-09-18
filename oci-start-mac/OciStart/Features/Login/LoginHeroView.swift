import SwiftUI
import AppKit

/// Public geography from the Vue login, drawn locally without account requests.
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
                    Spacer(minLength: 48)
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
                    .padding(.bottom, 26)
                    HStack {
                        Text(english ? "OCI public regions" : "OCI 公共区域")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(LoginPublicRegion.all.count) " + (english ? "regions" : "个区域"))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(LoginPalette.muted(dark))
                    }
                    LoginRegionMap(dark: dark, english: english)
                        .frame(height: max(180, min(280, (geo.size.width - 68) * 0.43)))
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
                         ? "City reference points · decorative connections"
                         : "城市参考位置 · 连线为示意")
                        .font(.system(size: 12))
                        .foregroundColor(LoginPalette.muted(dark))
                        .padding(.top, 8)
                    Spacer(minLength: 32)
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

private final class LoginRegionMapView: NSView {
    var dark = true
    var english = false { didSet { if oldValue != english { updateRegionTooltips() } } }
    private var landPath = NSBezierPath()
    private var cachedSize = NSSize.zero
    private var tooltipStrings: [NSString] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
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
        guard bounds.size != cachedSize else { return }
        cachedSize = bounds.size
        landPath = NSBezierPath()
        for point in Self.landDots {
            let p = project(longitude: point.x, latitude: point.y)
            landPath.appendOval(in: NSRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
        }
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
        let next = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func project(longitude: CGFloat, latitude: CGFloat) -> NSPoint {
        NSPoint(x: (longitude + 180) / 360 * bounds.width,
                y: (78 - latitude) / 130 * bounds.height)
    }
    private func position(_ region: LoginPublicRegion) -> NSPoint {
        project(longitude: region.longitude, latitude: region.latitude)
    }
    private func updateRegionTooltips() {
        removeAllToolTips()
        tooltipStrings.removeAll()
        // Same-city regions retain their real coordinates and every region code.
        for region in LoginPublicRegion.locations {
            let p = position(region)
            let names = LoginPublicRegion.all.filter { $0.latitude == region.latitude && $0.longitude == region.longitude }
                .map { (english ? $0.en : $0.zh) + " · " + $0.id + "\n" + $0.coordinates }
                .joined(separator: "\n")
            let tooltip = names as NSString
            tooltipStrings.append(tooltip)
            addToolTip(NSRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10), owner: tooltip, userData: nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(dark ? LoginPalette.bg(true) : LoginPalette.bg(false)).setFill()
        bounds.fill()
        NSColor(Color(hex: dark ? "1e3140" : "718d9c")).setFill()
        landPath.fill()
        let node = NSColor(Color(hex: dark ? "2fe0a6" : "08724f"))
        // These connections decorate the public directory; they are not telemetry.
        for (index, pair) in Self.routes.enumerated() {
            guard let a = LoginPublicRegion.all.first(where: { $0.id == pair.0 }),
                  let b = LoginPublicRegion.all.first(where: { $0.id == pair.1 }) else { continue }
            let start = position(a), end = position(b)
            let control = NSPoint(x: (start.x + end.x) / 2,
                                  y: min(start.y, end.y) - min(abs(end.x - start.x) * 0.22, 60))
            let path = NSBezierPath()
            path.move(to: start)
            path.curve(to: end,
                       controlPoint1: NSPoint(x: start.x + (control.x - start.x) * 2 / 3,
                                              y: start.y + (control.y - start.y) * 2 / 3),
                       controlPoint2: NSPoint(x: end.x + (control.x - end.x) * 2 / 3,
                                              y: end.y + (control.y - end.y) * 2 / 3))
            path.lineWidth = 0.75
            node.withAlphaComponent(dark ? 0.27 : 0.36).setStroke()
            path.stroke()
            if timer != nil {
                let t = CGFloat((Date.timeIntervalSinceReferenceDate / 6 + Double(index) * 0.17).truncatingRemainder(dividingBy: 1))
                let s = 1 - t
                let p = NSPoint(x: s * s * start.x + 2 * s * t * control.x + t * t * end.x,
                                y: s * s * start.y + 2 * s * t * control.y + t * t * end.y)
                node.withAlphaComponent(0.75).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)).fill()
            }
        }
        for region in LoginPublicRegion.locations {
            let p = position(region)
            node.withAlphaComponent(0.10).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill()
            node.setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)).fill()
        }
    }

    private static let routes = [
        ("us-sanjose-1", "ap-tokyo-1"), ("us-ashburn-1", "uk-london-1"),
        ("eu-frankfurt-1", "ap-mumbai-1"), ("ap-mumbai-1", "ap-singapore-1"),
        ("ap-singapore-1", "ap-sydney-1"), ("us-ashburn-1", "sa-saopaulo-1")
    ]
    private static let landDots: [CGPoint] = {
        var points: [CGPoint] = []
        for latitude in stride(from: CGFloat(-52), through: 78, by: 2.6) {
            for longitude in stride(from: CGFloat(-178), through: 178, by: 2.6) {
                if land.contains(where: { polygon in
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
                    return inside
                }) { points.append(CGPoint(x: longitude, y: latitude)) }
            }
        }
        return points
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
    // Snapshot copied from Vue `views/auth/regions.ts`, checked 2026-09-15.
    // Scope: 45 public commercial regions (44 OC1 + 1 OC20), not tenancy availability.
    // Oracle region identifiers: https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm
    // City reference coordinates: https://www.geonames.org/ (not data-centre coordinates).
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
