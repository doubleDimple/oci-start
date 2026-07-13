import Foundation
import SwiftUI

// MARK: - API models (web `/api/getOracleEndpoint` + `/api/getCurrentIp`)

struct SpeedRegionEndpoint: Identifiable, Hashable {
    let code: String
    let name: String
    let simpleName: String
    let endpoint: String

    var id: String { code }
}

enum SpeedLatencyState: Equatable {
    case idle
    case testing
    case ok(Int)   // ms
    case timeout

    var displayText: String {
        switch self {
        case .idle: return "--"
        case .testing: return "..."
        case .ok(let ms): return "\(ms)"
        case .timeout: return "timeOut"
        }
    }

    var milliseconds: Int? {
        if case .ok(let ms) = self { return ms }
        return nil
    }
}

enum SpeedLatencyTone {
    case neutral, fast, mid, slow

    static func from(ms: Int) -> SpeedLatencyTone {
        if ms < 150 { return .fast }
        if ms < 300 { return .mid }
        return .slow
    }
}

struct SpeedRankItem: Identifiable, Hashable {
    let code: String
    let name: String
    let ms: Int
    var id: String { code }
}

// MARK: - Theme (speed_test.css)

enum SpeedTestTheme {
    static func bg(_ dark: Bool) -> Color {
        dark ? Color(hex: "0f1117") : Color(hex: "f4f6f9")
    }
    static func surface(_ dark: Bool) -> Color {
        dark ? Color(hex: "1a1d27") : Color.white
    }
    static func surface2(_ dark: Bool) -> Color {
        dark ? Color(hex: "1f2233") : Color(hex: "f5f5f5")
    }
    static func border(_ dark: Bool) -> Color {
        dark ? Color(hex: "2a2d3a") : Color(hex: "e9ecef")
    }
    static func text(_ dark: Bool) -> Color {
        dark ? Color(hex: "e2e8f0") : Color(hex: "333333")
    }
    static func muted(_ dark: Bool) -> Color {
        dark ? Color(hex: "8892a4") : Color(hex: "6c757d")
    }
    static func primary(_ dark: Bool) -> Color {
        dark ? Color(hex: "4a9eff") : Color(hex: "2196f3")
    }
    static let success = Color(hex: "00c853")
    static let warning = Color(hex: "ffab00")
    static let danger = Color(hex: "ff5252")
    static func nodeCodeBg(_ dark: Bool) -> Color {
        dark ? Color(hex: "252838") : Color(hex: "f8f9fa")
    }
    static func progressTrack(_ dark: Bool) -> Color {
        dark ? Color(hex: "252838") : Color(hex: "f1f3f5")
    }

    static func toneColor(_ tone: SpeedLatencyTone, dark: Bool) -> Color {
        switch tone {
        case .neutral: return muted(dark)
        case .fast: return success
        case .mid: return warning
        case .slow: return danger
        }
    }
}
