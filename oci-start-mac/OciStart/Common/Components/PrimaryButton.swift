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
    @Environment(\.isEnabled) private var parentEnabled
    @State private var hovering = false
    private var dark: Bool { appearance.isDarkEffective }
    private var available: Bool { enabled && parentEnabled && !isLoading }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        .colorScheme(kind == .primary || kind == .danger ? .dark : (dark ? .dark : .light))
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
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled || isLoading)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var background: Color {
        switch kind {
        case .primary:
            if !available { return AppTheme.mix(AppTheme.sidebarActive, fraction: 0.5, with: AppTheme.cardBg(dark)) }
            return hovering ? AppTheme.brandHover : AppTheme.sidebarActive
        case .danger:
            return AppTheme.mix(AppTheme.danger, fraction: available ? (hovering ? 0.7 : 1) : 0.5, with: AppTheme.cardBg(dark))
        case .secondary:
            if !available { return AppTheme.hover(dark) }
            return hovering ? AppTheme.statusBg(AppTheme.success, dark) : AppTheme.cardBg(dark)
        case .plain: return available && hovering ? AppTheme.hover(dark) : .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: return .white
        case .secondary: return !available ? AppTheme.textMuted(dark) : (hovering ? AppTheme.sidebarActive : AppTheme.textPrimary(dark))
        case .plain: return available ? AppTheme.sidebarActive : AppTheme.textMuted(dark)
        }
    }

    private var borderColor: Color {
        kind == .secondary ? (available && hovering ? AppTheme.sidebarActive : AppTheme.border(dark)) : .clear
    }
}
