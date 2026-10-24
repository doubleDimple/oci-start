import SwiftUI
import AppKit

/// Native counterpart of `oci-start-web/src/styles/tokens.css`.
/// Sidebar colors are deliberately independent of the content appearance.
enum AppTheme {
    static let sidebarWidth: CGFloat = 220
    static let sidebarCollapsedWidth: CGFloat = 76
    static let topBarHeight: CGFloat = 56
    static let pagePadding: CGFloat = 24
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12
    static let bodySize: CGFloat = 14
    static let secondarySize: CGFloat = 13
    static let captionSize: CGFloat = 12
    static let sectionSize: CGFloat = 16
    static let dialogTitleSize: CGFloat = 18

    static let sidebarActive = Color(hex: "1b8a6a")
    static let brandHover = Color(hex: "157456")
    static let brandDeep = Color(hex: "0d4d3f")
    static let success = Color(hex: "1b8a6a")
    static let info = Color(hex: "0071e3")
    static let danger = Color(hex: "e24b4a")
    static func warning(_ dark: Bool) -> Color { Color(hex: "b45309") }

    // Keep the existing call signatures. The saved shell mode selects the palette;
    // its content brightness may differ from a view's inherited color scheme.
    private static var palette: AppContentPalette { AppearanceController.shared.contentPalette }
    static func topNavBg(_ dark: Bool) -> Color { cardBg(dark) }
    static func sidebarBg(_ dark: Bool) -> Color { Color(hex: AppearanceController.shared.chrome.sidebar) }
    static func sidebarIsLight(_ dark: Bool) -> Bool { ThemeColor.isLight(AppearanceController.shared.chrome.sidebar) }
    static func sidebarHover(_ dark: Bool) -> Color { sidebarPrimary(dark).opacity(0.08) }
    static func sidebarPrimary(_ dark: Bool) -> Color { Color(hex: sidebarIsLight(dark) ? "0f172a" : "f5f5f7") }
    static func sidebarText(_ dark: Bool) -> Color { Color(hex: sidebarIsLight(dark) ? "64748b" : "a1a1a6") }
    static func sidebarBorder(_ dark: Bool) -> Color { sidebarPrimary(dark).opacity(0.10) }
    static func brand(_ dark: Bool) -> Color { sidebarActive }
    static func pageBg(_ dark: Bool) -> Color { Color(hex: palette.page) }
    static func cardBg(_ dark: Bool) -> Color { Color(hex: palette.card) }
    static func cardSubtle(_ dark: Bool) -> Color { Color(hex: palette.cardSubtle) }
    static func inputBg(_ dark: Bool) -> Color { Color(hex: palette.search) }
    static func hover(_ dark: Bool) -> Color { Color(hex: palette.hover) }
    static func border(_ dark: Bool) -> Color { Color(hex: palette.border) }
    static func borderStrong(_ dark: Bool) -> Color { Color(hex: palette.borderStrong) }
    static func textPrimary(_ dark: Bool) -> Color { Color(hex: palette.textPrimary) }
    static func textSecondary(_ dark: Bool) -> Color { Color(hex: palette.textSecondary) }
    static func textMuted(_ dark: Bool) -> Color { Color(hex: palette.textMuted) }
    static func navIcon(_ dark: Bool) -> Color { textPrimary(dark) }
    static func statusBg(_ color: Color, _ dark: Bool) -> Color { mix(color, fraction: 0.10, with: cardBg(dark)) }
    static func tooltipBg(_ dark: Bool) -> Color {
        mix(pageBg(dark), fraction: palette.isDark ? 0.16 : 0.08,
            with: Color(hex: palette.isDark ? "363638" : "1d1d1f"))
    }
    static func cardShadow(_ dark: Bool) -> Color { Color.black.opacity(palette.shadowOpacity) }
    static var cardShadowRadius: CGFloat { AppearanceController.shared.contentPalette.shadowRadius }
    static var cardShadowY: CGFloat { AppearanceController.shared.contentPalette.shadowY }

    static func mix(_ color: Color, fraction: Double, with background: Color) -> Color {
        guard let a = NSColor(color).usingColorSpace(.sRGB),
              let b = NSColor(background).usingColorSpace(.sRGB) else { return color }
        let ratio = CGFloat(max(0, min(1, fraction)))
        return Color(red: Double(a.redComponent * ratio + b.redComponent * (1 - ratio)),
                     green: Double(a.greenComponent * ratio + b.greenComponent * (1 - ratio)),
                     blue: Double(a.blueComponent * ratio + b.blueComponent * (1 - ratio)))
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: Double
        switch h.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}

enum AppAppearanceMode: String, CaseIterable {
    case system
    case dark
    case light

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }
}

final class AppearanceController: ObservableObject {
    static let shared = AppearanceController()
    private static let chromeKey = "appChromeThemeV2"

    @Published var mode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "appAppearance")
            apply()
        }
    }

    @Published private(set) var contentPalette: AppContentPalette
    @Published private(set) var preferences: [String: AppChromePreference]
    @Published private(set) var systemDark: Bool
    private var systemObserver: NSObjectProtocol?

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appAppearance") ?? AppAppearanceMode.light.rawValue
        let initialMode = AppAppearanceMode(rawValue: raw) ?? .light
        mode = initialMode
        systemDark = Self.readSystemDark()
        let saved = UserDefaults.standard.data(forKey: Self.chromeKey)
            .flatMap { try? JSONDecoder().decode([String: AppChromePreference].self, from: $0) } ?? [:]
        preferences = [
            "light": (saved["light"] ?? .defaults(dark: false)).validated(dark: false),
            "dark": (saved["dark"] ?? .defaults(dark: true)).validated(dark: true)
        ]
        contentPalette = AppContentPalette.presets[0]
        apply()
        systemObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.systemDark = Self.readSystemDark()
            if self.mode == .system { self.apply() }
        }
    }

    deinit {
        if let observer = systemObserver { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    private static func readSystemDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    /// The selected light/dark storage slot is independent of content brightness.
    var isShellDark: Bool { mode == .dark || (mode == .system && systemDark) }
    var chrome: AppChromePreference { preferences[isShellDark ? "dark" : "light"] ?? .defaults(dark: isShellDark) }

    func apply() {
        let palette = AppContentPalette.presets.first(where: { $0.id == chrome.preset })
            ?? AppContentPalette.derived(from: chrome.page)
        contentPalette = palette
        let appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        if Thread.isMainThread {
            NSApp.appearance = appearance
        } else {
            DispatchQueue.main.async { NSApp.appearance = appearance }
        }
    }

    private func save(_ update: (inout AppChromePreference) -> Void) {
        var preference = chrome
        update(&preference)
        preferences[isShellDark ? "dark" : "light"] = preference
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.chromeKey)
        }
        apply()
    }

    func setSidebarPreset(_ id: String) {
        guard let preset = AppSidebarPreset.presets.first(where: { $0.id == id }) else { return }
        save { $0.sidebar = preset.color; $0.sidebarPreset = preset.id }
    }

    func setSidebarColor(_ hex: String) {
        guard let color = ThemeColor.normalized(hex) else { return }
        let id = AppSidebarPreset.presets.first(where: { $0.color == color })?.id ?? "custom"
        save { $0.sidebar = color; $0.sidebarPreset = id }
    }

    func setContentPreset(_ id: String) {
        guard let preset = AppContentPalette.presets.first(where: { $0.id == id }) else { return }
        save { $0.page = preset.page; $0.preset = preset.id }
    }

    func setCustomPageColor(_ hex: String) {
        guard let color = ThemeColor.normalized(hex) else { return }
        let id = AppContentPalette.presets.first(where: { $0.page == color })?.id ?? "custom"
        save { $0.page = color; $0.preset = id }
    }

    /// Like Web resetChrome(), reset only the active mode's colors.
    func resetChrome() {
        let preference = AppChromePreference.defaults(dark: isShellDark)
        save { $0 = preference }
    }

    func cycle() {
        switch mode {
        case .dark: mode = .light
        case .light: mode = .system
        case .system: mode = .dark
        }
    }

    /// Effective content appearance, including a preset of different brightness.
    var isDarkEffective: Bool { contentPalette.isDark }
}

struct AppChromePreference: Codable {
    var sidebar: String
    var page: String
    var preset: String
    var sidebarPreset: String

    static func defaults(dark: Bool) -> AppChromePreference {
        AppChromePreference(sidebar: "#18181b", page: dark ? "#0b0f19" : "#f1f5f9",
                            preset: dark ? "midnight" : "slate", sidebarPreset: "obsidian")
    }

    func validated(dark: Bool) -> AppChromePreference {
        let fallback = Self.defaults(dark: dark)
        return AppChromePreference(sidebar: ThemeColor.normalized(sidebar) ?? fallback.sidebar,
                                   page: ThemeColor.normalized(page) ?? fallback.page,
                                   preset: preset, sidebarPreset: sidebarPreset)
    }
}

struct AppSidebarPreset: Identifiable {
    let id: String
    let title: String
    let englishTitle: String
    let color: String

    static let presets: [AppSidebarPreset] = [
        .init(id: "obsidian", title: "经典暗黑", englishTitle: "Obsidian Dark", color: "#18181b"),
        .init(id: "black", title: "曜石纯黑", englishTitle: "Pure Black", color: "#000000"),
        .init(id: "forest", title: "OCI 墨绿", englishTitle: "OCI Forest", color: "#0d4d3f"),
        .init(id: "navy", title: "科技深蓝", englishTitle: "Navy Blue", color: "#0f172a"),
        .init(id: "espresso", title: "沉稳深咖", englishTitle: "Espresso", color: "#29180e"),
        .init(id: "light", title: "极简素白", englishTitle: "Clean Light", color: "#ffffff")
    ]
}

/// Values and custom derivation mirror the effective useChrome.ts palette.
struct AppContentPalette: Identifiable {
    let id: String
    let title: String
    let englishTitle: String
    let isDark: Bool
    let page: String
    let card: String
    let cardSubtle: String
    let search: String
    let hover: String
    let border: String
    let borderStrong: String
    let textPrimary: String
    let textSecondary: String
    let textMuted: String
    var shadowOpacity: Double = 0.05
    var shadowRadius: CGFloat = 6
    var shadowY: CGFloat = 2

    static let presets: [AppContentPalette] = [
        .init(id: "slate", title: "经典冷灰", englishTitle: "Classic Slate", isDark: false,
              page: "#f1f5f9", card: "#ffffff", cardSubtle: "#f8fafc", search: "#e2e8f0", hover: "#f1f5f9",
              border: "#cbd5e1", borderStrong: "#94a3b8", textPrimary: "#0f172a", textSecondary: "#475569", textMuted: "#94a3b8"),
        .init(id: "pure", title: "极简纯雪", englishTitle: "Pure Snow", isDark: false,
              page: "#ffffff", card: "#f8fafc", cardSubtle: "#f1f5f9", search: "#ffffff", hover: "#eef2f6",
              border: "#e2e8f0", borderStrong: "#cbd5e1", textPrimary: "#0f172a", textSecondary: "#475569", textMuted: "#94a3b8",
              shadowOpacity: 0.04, shadowRadius: 1.5, shadowY: 1),
        .init(id: "azure", title: "科技蓝灰", englishTitle: "Cloud Azure", isDark: false,
              page: "#eef2f8", card: "#ffffff", cardSubtle: "#f4f7fb", search: "#dde6f2", hover: "#e8f0fa",
              border: "#c7d7ea", borderStrong: "#9cb7da", textPrimary: "#0c1a2e", textSecondary: "#3e5473", textMuted: "#7d95b5"),
        .init(id: "ivory", title: "温润暖米", englishTitle: "Warm Ivory", isDark: false,
              page: "#f7f4ed", card: "#ffffff", cardSubtle: "#fbf9f4", search: "#ede8dc", hover: "#f3ede1",
              border: "#dcd4c3", borderStrong: "#baa992", textPrimary: "#292524", textSecondary: "#57534e", textMuted: "#a8a29e",
              shadowOpacity: 0.04, shadowRadius: 5),
        .init(id: "midnight", title: "暗夜极客", englishTitle: "Midnight Slate", isDark: true,
              page: "#0b0f19", card: "#131b2e", cardSubtle: "#19233c", search: "#1c2742", hover: "#243254",
              border: "#243356", borderStrong: "#3b5288", textPrimary: "#f8fafc", textSecondary: "#cbd5e1", textMuted: "#8193b2",
              shadowOpacity: 0.45, shadowRadius: 10, shadowY: 4),
        .init(id: "onyx", title: "曜石极黑", englishTitle: "Onyx Black", isDark: true,
              page: "#000000", card: "#161618", cardSubtle: "#1e1e22", search: "#26262b", hover: "#2c2c33",
              border: "#36363d", borderStrong: "#4d4d57", textPrimary: "#f5f5f7", textSecondary: "#d2d2d7", textMuted: "#86868b",
              shadowOpacity: 0.65, shadowRadius: 10, shadowY: 4),
        .init(id: "aurora", title: "极光墨夜", englishTitle: "Aurora Forest", isDark: true,
              page: "#061a14", card: "#0e2a22", cardSubtle: "#14382e", search: "#164034", hover: "#1e5243",
              border: "#215f4e", borderStrong: "#2f866e", textPrimary: "#f0fdf4", textSecondary: "#bbf7d0", textMuted: "#6ee7b7",
              shadowOpacity: 0.5, shadowRadius: 10, shadowY: 4)
    ]

    static func derived(from rawHex: String) -> AppContentPalette {
        let page = ThemeColor.normalized(rawHex) ?? "#f1f5f9"
        let hsl = ThemeColor.hsl(page)
        let light = ThemeColor.isLight(page)
        if light && (page == "#ffffff" || hsl.l >= 99) {
            let pure = presets[1]
            return .init(id: "custom", title: "自定义皮肤", englishTitle: "Custom", isDark: false,
                         page: page, card: pure.card, cardSubtle: pure.cardSubtle, search: pure.search, hover: pure.hover,
                         border: pure.border, borderStrong: pure.borderStrong, textPrimary: pure.textPrimary,
                         textSecondary: pure.textSecondary, textMuted: pure.textMuted,
                         shadowOpacity: 0.04, shadowRadius: 1.5, shadowY: 1)
        }
        func hex(_ saturation: Double, _ lightness: Double) -> String {
            ThemeColor.hex(hue: hsl.h, saturation: saturation, lightness: lightness)
        }
        if light {
            return .init(id: "custom", title: "自定义皮肤", englishTitle: "Custom", isDark: false,
                         page: page, card: "#ffffff", cardSubtle: hex(min(hsl.s, 18), 97),
                         search: hex(hsl.s, max(0, hsl.l - 7)), hover: hex(hsl.s, max(0, hsl.l - 4)),
                         border: hex(min(hsl.s, 25), max(0, hsl.l - 15)),
                         borderStrong: hex(min(hsl.s, 30), max(0, hsl.l - 26)),
                         textPrimary: "#0f172a", textSecondary: "#475569", textMuted: "#94a3b8", shadowRadius: 5)
        }
        let cardLightness = min(80, hsl.l + 10)
        return .init(id: "custom", title: "自定义皮肤", englishTitle: "Custom", isDark: true,
                     page: page, card: hex(min(hsl.s, 35), cardLightness),
                     cardSubtle: hex(min(hsl.s, 35), cardLightness + 4),
                     search: hex(min(hsl.s, 35), min(85, hsl.l + 13)), hover: hex(min(hsl.s, 35), min(88, hsl.l + 17)),
                     border: hex(min(hsl.s, 30), min(90, hsl.l + 20)), borderStrong: hex(min(hsl.s, 35), min(92, hsl.l + 28)),
                     textPrimary: "#f8fafc", textSecondary: "#cbd5e1", textMuted: "#94a3b8",
                     shadowOpacity: 0.45, shadowRadius: 10, shadowY: 4)
    }
}

private enum ThemeColor {
    static func normalized(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) else { return nil }
        return "#" + value
    }

    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let number = UInt64(String((normalized(hex) ?? "#f1f5f9").dropFirst()), radix: 16) ?? 0
        return (Double((number >> 16) & 255) / 255, Double((number >> 8) & 255) / 255, Double(number & 255) / 255)
    }

    static func isLight(_ hex: String) -> Bool {
        let rgb = self.rgb(hex)
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b) >= 0.42
    }

    static func hsl(_ hex: String) -> (h: Double, s: Double, l: Double) {
        let rgb = self.rgb(hex)
        let maximum = max(rgb.r, max(rgb.g, rgb.b))
        let minimum = min(rgb.r, min(rgb.g, rgb.b))
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum
        guard delta != 0 else { return (0, 0, (lightness * 100).rounded()) }
        let saturation = lightness > 0.5 ? delta / (2 - maximum - minimum) : delta / (maximum + minimum)
        let hue: Double
        if maximum == rgb.r { hue = (rgb.g - rgb.b) / delta + (rgb.g < rgb.b ? 6 : 0) }
        else if maximum == rgb.g { hue = (rgb.b - rgb.r) / delta + 2 }
        else { hue = (rgb.r - rgb.g) / delta + 4 }
        return ((hue * 60).rounded(), (saturation * 100).rounded(), (lightness * 100).rounded())
    }

    static func hex(hue: Double, saturation: Double, lightness: Double) -> String {
        let l = lightness / 100
        let a = saturation / 100 * min(l, 1 - l)
        func channel(_ n: Double) -> Int {
            let k = (n + hue / 30).truncatingRemainder(dividingBy: 12)
            let color = l - a * max(min(min(k - 3, 9 - k), 1), -1)
            return Int((255 * max(0, min(1, color))).rounded())
        }
        return String(format: "#%02x%02x%02x", channel(0), channel(8), channel(4))
    }

    static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02x%02x%02x", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}

/// Native counterpart of ThemeDrawer.vue. Choices apply and persist immediately.
struct ThemePreferencesView: View {
    let onClose: () -> Void
    @EnvironmentObject private var appearance: AppearanceController
    @ObservedObject private var language = LanguageManager.shared
    @State private var didReset = false
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    modeSection
                    sidebarSection
                    contentSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
            footer
        }
        .frame(width: 390, height: 700)
        .background(AppTheme.cardBg(dark))
        .foregroundColor(AppTheme.textPrimary(dark))
        .preferredColorScheme(dark ? .dark : .light)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "paintpalette")
                .font(.system(size: 20))
                .foregroundColor(AppTheme.sidebarActive)
                .frame(width: 38, height: 38)
                .background(AppTheme.statusBg(AppTheme.success, dark))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("外观与换肤", "Appearance & Themes"))
                    .font(.system(size: AppTheme.sectionSize, weight: .semibold))
                Text(language.text("定制侧边栏、内容区域及容器层级配色", "Customize sidebar, content, and card colors"))
                    .font(.system(size: AppTheme.secondarySize))
                    .foregroundColor(AppTheme.textSecondary(dark))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onClose) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(language.text("关闭", "Close"))
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .bottom)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("主题模式", "Appearance mode", icon: "circle.lefthalf.fill")
            HStack(spacing: 8) {
                modeButton(.light, title: language.text("浅色", "Light"), icon: "sun.max")
                modeButton(.dark, title: language.text("深色", "Dark"), icon: "moon")
                modeButton(.system, title: language.text("跟随系统", "System"), icon: "desktopcomputer")
            }
        }
    }

    private func modeButton(_ mode: AppAppearanceMode, title: String, icon: String) -> some View {
        let selected = appearance.mode == mode
        return Button(action: { appearance.mode = mode; didReset = false }) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: AppTheme.secondarySize, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(selected ? AppTheme.sidebarActive : AppTheme.textPrimary(dark))
            .background(selected ? AppTheme.statusBg(AppTheme.success, dark) : AppTheme.cardBg(dark))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? AppTheme.sidebarActive : AppTheme.border(dark)))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityValue(selected ? language.text("已选中", "Selected") : "")
    }

    private var sidebarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("侧边栏风格", "Sidebar style", icon: "sidebar.left")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AppSidebarPreset.presets) { preset in
                    sidebarButton(preset)
                }
            }
            ColorPicker(language.text("自定义取色", "Custom color"), selection: sidebarColor, supportsOpacity: false)
                .font(.system(size: AppTheme.secondarySize, weight: .medium))
        }
    }

    private func sidebarButton(_ preset: AppSidebarPreset) -> some View {
        let selected = appearance.chrome.sidebar == preset.color
        return Button(action: { appearance.setSidebarPreset(preset.id); didReset = false }) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: preset.color)).frame(width: 18, height: 18)
                    .overlay(Circle().stroke(AppTheme.border(dark)))
                Text(language.text(preset.title, preset.englishTitle))
                    .font(.system(size: AppTheme.secondarySize, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").foregroundColor(AppTheme.sidebarActive) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? AppTheme.statusBg(AppTheme.success, dark) : AppTheme.cardBg(dark))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? AppTheme.sidebarActive : AppTheme.border(dark)))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityValue(selected ? language.text("已选中", "Selected") : "")
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("内容区域与卡片皮肤", "Content & card surfaces", icon: "square.grid.2x2")
            Text(language.text("切换底色与容器层级，整站卡片、表格与输入框自动适配", "Synchronizes page canvas, cards, tables, inputs, and borders"))
                .font(.system(size: AppTheme.secondarySize))
                .foregroundColor(AppTheme.textSecondary(dark))
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppContentPalette.presets) { preset in contentButton(preset) }
            }
            VStack(alignment: .leading, spacing: 8) {
                ColorPicker(language.text("内容区配色", "Content color"), selection: pageColor, supportsOpacity: false)
                    .font(.system(size: AppTheme.bodySize, weight: .medium))
                Text(appearance.chrome.page.uppercased())
                    .font(.system(size: AppTheme.secondarySize, design: .monospaced))
                Text(language.text("卡片、输入框与边框随所选颜色自动调整。亮色和暗色模式分别保存。", "Cards, inputs, and borders adapt to your color. Light and dark modes save separately."))
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundColor(AppTheme.textMuted(dark))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(AppTheme.hover(dark))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.borderStrong(dark), style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
    }

    private func contentButton(_ preset: AppContentPalette) -> some View {
        let selected = appearance.chrome.preset == preset.id
        return Button(action: { appearance.setContentPreset(preset.id); didReset = false }) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: appearance.chrome.sidebar)).frame(width: 18)
                    VStack(spacing: 5) {
                        Rectangle().fill(Color(hex: preset.border)).frame(height: 1).padding(.vertical, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: preset.textPrimary)).frame(width: 40, height: 3)
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: preset.textMuted)).frame(width: 58, height: 3)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(6).background(Color(hex: preset.card)).cornerRadius(6)
                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: preset.cardSubtle)).frame(height: 12)
                    }
                }
                .padding(7).frame(height: 76).background(Color(hex: preset.page))
                HStack(spacing: 4) {
                    Text(language.text(preset.title, preset.englishTitle))
                        .font(.system(size: AppTheme.secondarySize, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(AppTheme.sidebarActive)
                    } else {
                        Image(systemName: preset.isDark ? "moon" : "sun.max")
                            .font(.system(size: AppTheme.captionSize)).foregroundColor(AppTheme.textMuted(dark))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .background(AppTheme.cardBg(dark))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? AppTheme.sidebarActive : AppTheme.border(dark), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityValue(selected ? language.text("已选中", "Selected") : "")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if didReset {
                Text(language.text("已恢复默认外观设置", "Default appearance restored"))
                    .font(.system(size: AppTheme.secondarySize)).foregroundColor(AppTheme.success)
            }
            HStack {
                AppButton(title: language.text("恢复默认主题", "Reset theme"), systemImage: "arrow.counterclockwise", kind: .secondary) {
                    appearance.resetChrome(); didReset = true
                }
                Spacer(minLength: 8)
                AppButton(title: language.text("完成", "Done"), action: onClose)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .top)
    }

    private func sectionTitle(_ title: String, _ english: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(AppTheme.sidebarActive)
            Text(language.text(title, english)).font(.system(size: AppTheme.bodySize, weight: .semibold))
        }
    }

    private var sidebarColor: Binding<Color> {
        Binding(get: { Color(hex: appearance.chrome.sidebar) }, set: { color in
            if let hex = ThemeColor.hex(color) { appearance.setSidebarColor(hex); didReset = false }
        })
    }

    private var pageColor: Binding<Color> {
        Binding(get: { Color(hex: appearance.chrome.page) }, set: { color in
            if let hex = ThemeColor.hex(color) { appearance.setCustomPageColor(hex); didReset = false }
        })
    }
}
