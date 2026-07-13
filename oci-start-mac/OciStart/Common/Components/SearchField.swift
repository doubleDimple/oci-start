import SwiftUI

/// Unified search input — login-style chrome, **no system blue focus ring**.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索…"
    var onSubmit: (() -> Void)? = nil
    var maxWidth: CGFloat? = 280
    /// When true, expand to parent width (sidebar).
    var fillsWidth: Bool = false

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    @State private var focused = false

    var body: some View {
        AppInputChrome(
            dark: dark,
            focused: focused,
            height: AppInputStyle.height,
            leading: AnyView(
                Image(systemName: "magnifyingglass")
                    .font(.system(size: AppInputStyle.iconSize, weight: .medium))
                    .foregroundColor(focused ? AppInputStyle.border(dark, focused: true) : AppInputStyle.icon(dark))
            ),
            trailing: text.isEmpty ? nil : AnyView(
                Button(action: {
                    text = ""
                    onSubmit?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AppInputStyle.iconSize))
                        .foregroundColor(AppInputStyle.icon(dark).opacity(0.9))
                }
                .buttonStyle(PlainButtonStyle())
            )
        ) {
            AppNSTextField(
                text: $text,
                placeholder: placeholder,
                secure: false,
                dark: dark,
                enabled: true,
                fontSize: AppInputStyle.fontSize,
                isFocused: $focused,
                onCommit: onSubmit
            )
            .frame(maxWidth: .infinity)
            .frame(height: 20)
        }
        .frame(
            minWidth: fillsWidth ? 0 : 140,
            idealWidth: fillsWidth ? nil : 220,
            maxWidth: fillsWidth ? .infinity : maxWidth
        )
    }
}
