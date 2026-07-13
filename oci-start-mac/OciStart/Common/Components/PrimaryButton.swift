import SwiftUI

enum AppButtonStyleKind {
    case primary, secondary, danger, plain
}

struct AppButton: View {
    let title: String
    var systemImage: String? = nil
    var kind: AppButtonStyleKind = .primary
    var isLoading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(background)
            .foregroundColor(foreground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: kind == .secondary ? 1 : 0)
            )
            .opacity(enabled && !isLoading ? 1 : 0.5)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled || isLoading)
    }

    private var background: Color {
        switch kind {
        case .primary: return AppTheme.sidebarActive
        case .danger: return Color(hex: "f85149")
        case .secondary: return dark ? Color(hex: "2c3136") : Color(hex: "eef2f6")
        case .plain: return Color.clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: return .white
        case .secondary: return dark ? Color.white.opacity(0.92) : Color(hex: "1e2f42")
        case .plain: return AppTheme.sidebarActive
        }
    }

    private var borderColor: Color {
        kind == .secondary ? AppTheme.border(dark).opacity(0.85) : .clear
    }
}
