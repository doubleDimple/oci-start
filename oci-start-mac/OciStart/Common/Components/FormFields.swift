import SwiftUI

// MARK: - Shared input chrome (aligned with login page filled fields)

/// Global input tokens — match login filled box (soft fill, radius 12, focus glow).
/// Toolbar/filter height is slightly denser than login form (40 vs 48).
enum AppInputStyle {
    static let height: CGFloat = 40
    static let radius: CGFloat = 12
    static let fontSize: CGFloat = 13
    static let iconSize: CGFloat = 12
    static let hPad: CGFloat = 12

    static func fill(_ dark: Bool, focused: Bool = false) -> Color {
        if focused {
            return dark ? Color(hex: "1a1d21") : Color.white
        }
        return dark ? Color(hex: "292d32") : Color(hex: "f8f9fa")
    }

    static func border(_ dark: Bool, focused: Bool = false, hovering: Bool = false) -> Color {
        if focused {
            return dark ? Color(hex: "4d9eff") : Color(hex: "42b983")
        }
        if hovering {
            return dark ? Color(hex: "4d9eff").opacity(0.45) : Color(hex: "42b983").opacity(0.45)
        }
        return dark ? Color(hex: "31363d") : Color(hex: "e4e7ed")
    }

    static func glow(_ dark: Bool, focused: Bool) -> Color {
        guard focused else { return .clear }
        return dark
            ? Color(hex: "4d9eff").opacity(0.18)
            : Color(hex: "42b983").opacity(0.14)
    }

    static func text(_ dark: Bool) -> Color {
        dark ? Color(hex: "cdd9e5") : Color(hex: "2c3e50")
    }

    static func placeholder(_ dark: Bool) -> Color {
        dark ? Color(hex: "768390") : Color(hex: "999999")
    }

    static func icon(_ dark: Bool) -> Color {
        dark ? Color(hex: "768390") : Color(hex: "6b7280")
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
            RoundedRectangle(cornerRadius: AppInputStyle.radius)
                .fill(AppInputStyle.fill(dark, focused: focused))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppInputStyle.radius)
                .stroke(
                    AppInputStyle.border(dark, focused: focused, hovering: hovering),
                    lineWidth: focused ? 1.5 : 1
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarText(dark))
                if required {
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "f85149"))
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
                enabled: true,
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
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    @State private var focused = false

    var body: some View {
        AppInputChrome(dark: dark, focused: focused, height: height) {
            AppNSTextField(
                text: $text,
                placeholder: placeholder,
                secure: false,
                dark: dark,
                enabled: true,
                fontSize: 12,
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
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
