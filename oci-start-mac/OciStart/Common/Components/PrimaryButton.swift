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
                        .font(.system(size: AppTheme.bodySize, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(background)
            .foregroundColor(foreground)
            .cornerRadius(AppTheme.controlRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlRadius)
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
        case .danger: return AppTheme.danger
        case .secondary: return AppTheme.cardBg(dark)
        case .plain: return Color.clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: return .white
        case .secondary: return AppTheme.textPrimary(dark)
        case .plain: return AppTheme.sidebarActive
        }
    }

    private var borderColor: Color {
        kind == .secondary ? AppTheme.border(dark).opacity(0.85) : .clear
    }
}
