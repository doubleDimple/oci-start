import SwiftUI

enum StatusTone {
    case success, warning, danger, info, neutral

    func color(dark: Bool) -> Color {
        switch self {
        case .success: return Color(hex: "3fb950")
        case .warning: return Color(hex: "d29922")
        case .danger:  return Color(hex: "f85149")
        case .info:    return Color(hex: "58a6ff")
        case .neutral: return dark ? Color(hex: "8b949e") : Color(hex: "6B7280")
        }
    }

    /// Map common OCI/instance states.
    static func fromState(_ state: String?) -> StatusTone {
        switch (state ?? "").uppercased() {
        case "RUNNING", "ACTIVE", "AVAILABLE", "ONLINE": return .success
        case "STOPPED", "STOPPING", "TERMINATED", "FAILED", "ERROR": return .danger
        case "PROVISIONING", "STARTING", "CREATING": return .warning
        default: return .neutral
        }
    }
}

struct StatusBadge: View {
    let text: String
    var tone: StatusTone = .neutral

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        let c = tone.color(dark: dark)
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(c)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(c.opacity(0.15))
            .cornerRadius(10)
    }

    static func state(_ state: String?) -> StatusBadge {
        StatusBadge(text: state ?? "—", tone: .fromState(state))
    }
}
