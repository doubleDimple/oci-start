import SwiftUI

/// Login has its own palette, matching Vue `views/auth/login.scss`.
enum LoginPalette {
    static func bg(_ dark: Bool) -> Color { Color(hex: dark ? "090d12" : "f6f8f9") }
    static func panel(_ dark: Bool) -> Color { bg(dark) }
    static func card(_ dark: Bool) -> Color { Color(hex: dark ? "0d131a" : "ffffff") }
    static func text(_ dark: Bool) -> Color { Color(hex: dark ? "e8eef4" : "000000") }
    static func muted(_ dark: Bool) -> Color { Color(hex: dark ? "7d8f9d" : "000000") }
    static func line(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.09) : Color(hex: "0a1e2d").opacity(0.11)
    }
    static func primary(_ dark: Bool) -> Color { Color(hex: dark ? "15a077" : "0f8b64") }
    static func highlight(_ dark: Bool) -> Color { Color(hex: dark ? "1cc194" : "0b7454") }
    static func input(_ dark: Bool) -> Color { Color(hex: dark ? "090d12" : "fbfcfd") }
    static func oauthBg(_ dark: Bool) -> Color { Color(hex: dark ? "111922" : "ffffff") }
    static func oauthBorder(_ dark: Bool) -> Color { line(dark) }
    static func tabActiveBg(_ dark: Bool) -> Color { primary(dark).opacity(dark ? 0.13 : 0.09) }
    static func tabActiveText(_ dark: Bool) -> Color { highlight(dark) }
    static func divider(_ dark: Bool) -> Color { Color(hex: dark ? "1f242a" : "dce0e3") }
    static func chipBg(_ dark: Bool) -> Color { card(dark) }
}
