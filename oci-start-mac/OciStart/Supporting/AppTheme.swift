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
    static func warning(_ dark: Bool) -> Color { Color(hex: dark ? "f5b861" : "b45309") }

    static func topNavBg(_ dark: Bool) -> Color { cardBg(dark) }
    static func sidebarBg(_ dark: Bool) -> Color { Color(hex: dark ? "000000" : "1d1d1f") }
    static func sidebarHover(_ dark: Bool) -> Color { Color(hex: "2c2c2e") }
    static func sidebarText(_ dark: Bool) -> Color { Color(hex: "a1a1a6") }
    static func brand(_ dark: Bool) -> Color { sidebarActive }
    static func pageBg(_ dark: Bool) -> Color { Color(hex: dark ? "000000" : "f5f5f7") }
    static func cardBg(_ dark: Bool) -> Color { Color(hex: dark ? "1d1d1f" : "ffffff") }
    static func inputBg(_ dark: Bool) -> Color { Color(hex: dark ? "2c2c2e" : "f5f5f7") }
    static func hover(_ dark: Bool) -> Color { inputBg(dark) }
    static func border(_ dark: Bool) -> Color { Color(hex: dark ? "424245" : "d2d2d7") }
    static func textPrimary(_ dark: Bool) -> Color { Color(hex: dark ? "f5f5f7" : "000000") }
    static func textSecondary(_ dark: Bool) -> Color { Color(hex: dark ? "d2d2d7" : "000000") }
    static func textMuted(_ dark: Bool) -> Color { Color(hex: dark ? "b5b5bd" : "000000") }
    static func navIcon(_ dark: Bool) -> Color { textPrimary(dark) }
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
        let raw = UserDefaults.standard.string(forKey: "appAppearance") ?? AppAppearanceMode.system.rawValue
        mode = AppAppearanceMode(rawValue: raw) ?? .system
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
