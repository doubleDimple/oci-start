import SwiftUI
import AppKit

/// Borderless AppKit text field with **no system focus ring** (login / search / forms).
struct AppNSTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var secure: Bool = false
    var dark: Bool
    var enabled: Bool = true
    var fontSize: CGFloat = AppInputStyle.fontSize
    @Binding var isFocused: Bool
    var onCommit: (() -> Void)? = nil

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
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
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
        field.textColor = NSColor(AppTheme.textPrimary(dark))
        field.placeholderAttributedString = placeholderAttr()
        field.focusRingType = .none
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        if let cell = field.cell as? NSTextFieldCell {
            cell.focusRingType = .none
        }
    }

    private func placeholderAttr() -> NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor(AppTheme.textMuted(dark)),
                .font: NSFont.systemFont(ofSize: fontSize, weight: .regular)
            ]
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AppNSTextField
        weak var field: NSTextField?
        var isSecure: Bool = false

        init(_ parent: AppNSTextField) {
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
