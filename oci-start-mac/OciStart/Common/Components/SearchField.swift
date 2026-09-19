import SwiftUI

/// Vue console search input with a single themed pill frame.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索…"
    var onSubmit: (() -> Void)? = nil
    var maxWidth: CGFloat? = 280
    /// When true, expand to parent width (sidebar).
    var fillsWidth: Bool = false
    var onMoveSelection: ((Int) -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var focusRequest = 0
    var blurRequest = 0
    var shortcutHint: String? = nil

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
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
            trailing: text.isEmpty ? shortcutHint.map {
                AnyView(Text($0).font(.system(size: AppTheme.captionSize)).foregroundColor(AppTheme.textMuted(dark)).fixedSize())
            } : AnyView(
                Button(action: {
                    text = ""
                    if let onClear = onClear { onClear() } else { onSubmit?() }
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
                enabled: enabled,
                fontSize: AppInputStyle.fontSize,
                isFocused: $focused,
                onCommit: onSubmit,
                onMoveSelection: onMoveSelection,
                onCancel: onCancel,
                onFocusChange: onFocusChange,
                focusRequest: focusRequest,
                blurRequest: blurRequest
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
