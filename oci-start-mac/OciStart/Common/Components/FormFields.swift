import SwiftUI

// MARK: - Shared Vue console input chrome

/// Console inputs match index.scss: pill radius, search fill, inset focus border.
/// Login has its own independent LoginField and palette.
enum AppInputStyle {
    static let height: CGFloat = 36
    static let radius: CGFloat = AppTheme.controlRadius
    static let pillRadius: CGFloat = 999
    static let fontSize: CGFloat = AppTheme.bodySize
    static let iconSize: CGFloat = 14
    static let hPad: CGFloat = 12

    static func fill(_ dark: Bool, focused: Bool = false) -> Color {
        AppTheme.inputBg(dark)
    }

    static func border(_ dark: Bool, focused: Bool = false, hovering: Bool = false) -> Color {
        if focused {
            return AppTheme.sidebarActive
        }
        if hovering {
            return AppTheme.borderStrong(dark)
        }
        return AppTheme.border(dark)
    }

    static func glow(_ dark: Bool, focused: Bool) -> Color {
        .clear
    }

    static func text(_ dark: Bool) -> Color {
        AppTheme.textPrimary(dark)
    }

    static func placeholder(_ dark: Bool) -> Color {
        AppTheme.textMuted(dark)
    }

    static func icon(_ dark: Bool) -> Color {
        AppTheme.textSecondary(dark)
    }
}

/// Visual shell for text fields / select triggers: fill + border + optional leading/trailing.
struct AppInputChrome<Content: View>: View {
    var dark: Bool
    var focused: Bool = false
    var height: CGFloat = AppInputStyle.height
    var leading: AnyView? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 8) {
            if let leading = leading {
                leading
            }
            content()
            if let trailing = trailing {
                trailing
            }
        }
        .padding(.horizontal, AppInputStyle.hPad)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: AppInputStyle.pillRadius)
                .fill(enabled ? AppInputStyle.fill(dark, focused: focused) : AppTheme.hover(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppInputStyle.pillRadius)
                .strokeBorder(
                    AppInputStyle.border(dark, focused: focused && enabled, hovering: hovering && enabled),
                    lineWidth: focused && enabled ? 2 : 1
                )
        )
        .shadow(
            color: AppInputStyle.glow(dark, focused: focused),
            radius: focused ? 6 : 0,
            y: 0
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Labeled form row

struct FormFieldRow<Content: View>: View {
    let label: String
    var required: Bool = false
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary(dark))
                if required {
                    Text("*")
                        .font(.system(size: AppTheme.bodySize, weight: .bold))
                        .foregroundColor(AppTheme.danger)
                }
            }
            content()
        }
    }
}

// MARK: - Primary text / secure field

struct AppTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    var secure: Bool = false
    var leadingSystemImage: String? = nil
    var height: CGFloat = AppInputStyle.height
    var onCommit: (() -> Void)? = nil

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    @State private var focused = false

    var body: some View {
        AppInputChrome(
            dark: dark,
            focused: focused,
            height: height,
            leading: leadingSystemImage.map { name in
                AnyView(
                    Image(systemName: name)
                        .font(.system(size: AppInputStyle.iconSize, weight: .medium))
                        .foregroundColor(AppInputStyle.icon(dark))
                )
            },
            trailing: text.isEmpty ? nil : AnyView(
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AppInputStyle.iconSize))
                        .foregroundColor(AppInputStyle.icon(dark).opacity(0.85))
                }
                .buttonStyle(PlainButtonStyle())
            )
        ) {
            AppNSTextField(
                text: $text,
                placeholder: placeholder,
                secure: secure,
                dark: dark,
                enabled: enabled,
                fontSize: AppInputStyle.fontSize,
                isFocused: $focused,
                onCommit: onCommit
            )
            .frame(maxWidth: .infinity)
            .frame(height: 20)
        }
    }
}

// MARK: - Compact field (pagination jump etc.) — same tokens as AppInputStyle

struct AppCompactField: View {
    @Binding var text: String
    var placeholder: String = ""
    var width: CGFloat = 56
    var height: CGFloat = 32
    var onCommit: (() -> Void)? = nil

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    @State private var focused = false

    var body: some View {
        AppInputChrome(dark: dark, focused: focused, height: height) {
            AppNSTextField(
                text: $text,
                placeholder: placeholder,
                secure: false,
                dark: dark,
                enabled: enabled,
                fontSize: AppTheme.bodySize,
                isFocused: $focused,
                onCommit: onCommit
            )
            .frame(maxWidth: .infinity)
            .frame(height: 18)
        }
        .frame(width: width)
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(size: AppTheme.bodySize))
                .foregroundColor(AppTheme.textSecondary(dark))
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: AppTheme.bodySize, weight: .medium))
                .foregroundColor(AppTheme.textPrimary(dark))
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
