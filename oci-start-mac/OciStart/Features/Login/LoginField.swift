import SwiftUI
import AppKit

// MARK: - Filled rounded field (web `.form-control` style, no underline)

/// Smooth box input aligned with web `login_user.css` `.form-control`:
/// height 48, radius 12, soft fill, focus border + glow — no bottom underline.
struct LoginField: View {
    /// Shared with trailing action buttons so rows stay equal height.
    static let boxHeight: CGFloat = 48
    static let boxRadius: CGFloat = AppInputStyle.radius

    let title: String
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var dark: Bool = true
    var enabled: Bool = true
    var onCommit: (() -> Void)? = nil
    /// Increment to play empty-field shake (web `.input-shake`).
    var shakeToken: Int = 0
    /// Optional external focus report (e.g. password shy-mode for hero).
    var isFocusedOut: Binding<Bool>? = nil

    @State private var focused = false
    @State private var revealPassword = false
    @State private var shakeX: CGFloat = 0
    @State private var lastShake = 0
    @State private var hovering = false

    private var fillColor: Color {
        AppInputStyle.fill(dark, focused: focused)
    }

    private var borderColor: Color {
        if shakeX != 0 {
            return Color(hex: dark ? "f87171" : "ef4444")
        }
        return AppInputStyle.border(dark, focused: focused, hovering: hovering && enabled)
    }

    private var glowColor: Color {
        AppInputStyle.glow(dark, focused: focused)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(LoginPalette.text(dark))
            }

            HStack(spacing: 8) {
                LoginNSTextField(
                    text: $text,
                    placeholder: placeholder,
                    secure: secure && !revealPassword,
                    dark: dark,
                    enabled: enabled,
                    isFocused: $focused,
                    onCommit: onCommit
                )
                .frame(maxWidth: .infinity)
                .frame(height: 22)

                if secure && enabled {
                    Button(action: { revealPassword.toggle() }) {
                        Image(systemName: revealPassword ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(focused ? borderColor : LoginPalette.muted(dark))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(revealPassword ? "隐藏密码" : "显示密码")
                }

                if enabled && !text.isEmpty && (focused || hovering) {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(LoginPalette.muted(dark).opacity(0.9))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: Self.boxHeight)
            .background(
                RoundedRectangle(cornerRadius: Self.boxRadius)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.boxRadius)
                    .stroke(borderColor, lineWidth: focused ? 1.5 : 1)
            )
            .shadow(color: glowColor, radius: focused ? 6 : 0, y: 0)
            .animation(.easeOut(duration: 0.18), value: focused)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 && enabled }
        }
        // Empty-title fields sit inline with action buttons — no extra bottom pad.
        .padding(.bottom, title.isEmpty ? 0 : 6)
        .opacity(enabled ? 1 : 0.5)
        .offset(x: shakeX)
        .onChange(of: shakeToken) { token in
            guard token != lastShake, token > 0 else { return }
            lastShake = token
            runShake()
        }
        .onChange(of: focused) { on in
            isFocusedOut?.wrappedValue = on
        }
    }

    private func runShake() {
        let steps: [CGFloat] = [0, -8, 8, -6, 6, -3, 3, 0]
        for (i, x) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045 * Double(i)) {
                withAnimation(.linear(duration: 0.045)) {
                    shakeX = x
                }
            }
        }
    }
}

// MARK: - Trailing action (same height / radius as LoginField box)

/// Pill-free side button matched to `LoginField.boxHeight` for code/send & connect rows.
struct LoginFieldActionButton: View {
    let title: String
    var loading: Bool = false
    var enabled: Bool = true
    var dark: Bool = true
    var minWidth: CGFloat = 108
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(LoginPalette.text(dark))
            .padding(.horizontal, 16)
            .frame(minWidth: minWidth)
            .frame(height: LoginField.boxHeight)
            .background(
                RoundedRectangle(cornerRadius: LoginField.boxRadius)
                    .fill(LoginPalette.oauthBg(dark).opacity(hovering && enabled ? 0.92 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LoginField.boxRadius)
                    .stroke(LoginPalette.oauthBorder(dark), lineWidth: 1)
            )
        }
        .buttonStyle(LoginPressButtonStyle())
        .disabled(!enabled || loading)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 && enabled }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: loading)
    }
}

// MARK: - AppKit field (no system focus ring)

private struct LoginNSTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var secure: Bool
    var dark: Bool
    var enabled: Bool
    @Binding var isFocused: Bool
    var onCommit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let field = buildField(secure: secure)
        field.delegate = context.coordinator
        context.coordinator.field = field
        context.coordinator.isSecure = secure
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        applyStyle(field)
        field.stringValue = text
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        if coord.isSecure != secure || coord.field == nil {
            coord.field?.removeFromSuperview()
            let field = buildField(secure: secure)
            field.delegate = coord
            field.stringValue = text
            field.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                field.centerYAnchor.constraint(equalTo: nsView.centerYAnchor)
            ])
            coord.field = field
            coord.isSecure = secure
        }

        guard let field = coord.field else { return }
        applyStyle(field)
        field.isEditable = enabled
        field.isSelectable = enabled
        if field.stringValue != text, field.currentEditor() == nil {
            field.stringValue = text
        }
        field.placeholderAttributedString = placeholderAttr()
    }

    private func buildField(secure: Bool) -> NSTextField {
        let field: NSTextField
        if secure {
            field = NSSecureTextField(string: "")
        } else {
            field = NSTextField(string: "")
        }
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.backgroundColor = .clear
        field.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        if let cell = field.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
            cell.focusRingType = .none
            cell.usesSingleLineMode = true
        }
        return field
    }

    private func applyStyle(_ field: NSTextField) {
        field.textColor = nsHex(dark ? "cdd9e5" : "2c3e50")
        field.placeholderAttributedString = placeholderAttr()
        field.focusRingType = .none
        field.drawsBackground = false
        field.backgroundColor = .clear
        if let cell = field.cell as? NSTextFieldCell {
            cell.focusRingType = .none
        }
    }

    private func placeholderAttr() -> NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: nsHex(dark ? "768390" : "999999"),
                .font: NSFont.systemFont(ofSize: 16, weight: .regular)
            ]
        )
    }

    private func nsHex(_ hex: String) -> NSColor {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LoginNSTextField
        weak var field: NSTextField?
        var isSecure: Bool = false

        init(_ parent: LoginNSTextField) {
            self.parent = parent
            self.isSecure = parent.secure
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            DispatchQueue.main.async { self.parent.isFocused = true }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            DispatchQueue.main.async { self.parent.isFocused = false }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let value = field.stringValue
            DispatchQueue.main.async { self.parent.text = value }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit?()
                return true
            }
            return false
        }
    }
}

// MARK: - Pill button

struct LoginPillButton: View {
    let title: String
    var loading: Bool = false
    var enabled: Bool = true
    var dark: Bool = true
    var secondary: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundColor(secondary ? LoginPalette.text(dark) : Color.white)
            .background(
                (secondary ? LoginPalette.oauthBg(dark) : LoginPalette.primary(dark))
                    .opacity(hovering ? 0.92 : 1)
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(secondary ? LoginPalette.oauthBorder(dark) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(LoginPressButtonStyle())
        .disabled(!enabled || loading)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }
}

struct LoginPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
