import SwiftUI
import AppKit

/// Visual tokens aligned with Web `header.css` / sidebar (dark default).
enum AppTheme {
    // Web dark
    static let topNavBgDark = Color(hex: "1f1f1f")
    static let sidebarBgDark = Color(hex: "1e2124")
    static let sidebarHoverDark = Color(hex: "292d30")
    static let sidebarTextDark = Color(hex: "a9b7c6")
    static let sidebarActive = Color(hex: "1abc9c")
    static let brandGold = Color(hex: "FFD700")
    static let pageBgDark = Color(hex: "1a1d21")
    static let borderDark = Color(hex: "383c40")

    // Web light
    static let topNavBgLight = Color(hex: "d0dae6")
    static let sidebarBgLight = Color(hex: "e4eaf2")
    static let sidebarHoverLight = Color(hex: "d6dfe9")
    static let sidebarTextLight = Color(hex: "374a61")
    static let brandBrown = Color(hex: "b45309")
    static let pageBgLight = Color(hex: "f0f4f8")
    static let borderLight = Color(hex: "b8c8d8")

    static func topNavBg(_ dark: Bool) -> Color { dark ? topNavBgDark : topNavBgLight }
    static func sidebarBg(_ dark: Bool) -> Color { dark ? sidebarBgDark : sidebarBgLight }
    static func sidebarHover(_ dark: Bool) -> Color { dark ? sidebarHoverDark : sidebarHoverLight }
    static func sidebarText(_ dark: Bool) -> Color { dark ? sidebarTextDark : sidebarTextLight }
    static func brand(_ dark: Bool) -> Color { dark ? brandGold : brandBrown }
    static func pageBg(_ dark: Bool) -> Color { dark ? pageBgDark : pageBgLight }
    static func border(_ dark: Bool) -> Color { dark ? borderDark : borderLight }
    static func navIcon(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.9) : Color(hex: "1e2f42")
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

    @Published var mode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "appAppearance")
            apply()
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appAppearance") ?? AppAppearanceMode.dark.rawValue
        mode = AppAppearanceMode(rawValue: raw) ?? .dark
        apply()
    }

    func apply() {
        let appearance = mode.nsAppearance
        if Thread.isMainThread {
            NSApp.appearance = appearance
        } else {
            DispatchQueue.main.async { NSApp.appearance = appearance }
        }
    }

    func cycle() {
        switch mode {
        case .dark: mode = .light
        case .light: mode = .system
        case .system: mode = .dark
        }
    }

    /// Effective dark for drawing when mode is system.
    var isDarkEffective: Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .system:
            if let a = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
                return a == .darkAqua
            }
            return true
        }
    }
}
