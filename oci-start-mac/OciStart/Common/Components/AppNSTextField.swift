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
    var onMoveSelection: ((Int) -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil
    var focusRequest = 0
    var blurRequest = 0

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
        if coord.lastBlurRequest != blurRequest {
            coord.lastBlurRequest = blurRequest
            let request = blurRequest
            DispatchQueue.main.async { [weak coord] in
                guard let coord = coord, coord.parent.blurRequest == request, let field = coord.field else { return }
                if field.currentEditor() != nil { field.window?.makeFirstResponder(nil) }
                field.stringValue = coord.parent.text
            }
        } else if coord.lastFocusRequest != focusRequest {
            coord.lastFocusRequest = focusRequest
            let request = focusRequest
            DispatchQueue.main.async { [weak coord] in
                guard let coord = coord, coord.parent.focusRequest == request, coord.parent.enabled, let field = coord.field else { return }
                field.window?.makeFirstResponder(field)
                if let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() { editor.string = coord.parent.text }
                field.stringValue = coord.parent.text
            }
        }
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
        field.textColor = NSColor(enabled ? AppTheme.textPrimary(dark) : AppTheme.textMuted(dark))
        field.isEditable = enabled
        field.isSelectable = enabled
        if let editor = field.currentEditor() as? NSTextView {
            editor.textColor = field.textColor
            editor.insertionPointColor = NSColor(AppTheme.textPrimary(dark))
        }
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
        var lastFocusRequest = 0
        var lastBlurRequest = 0

        init(_ parent: AppNSTextField) {
            self.parent = parent
            self.isSecure = parent.secure
            self.lastFocusRequest = parent.focusRequest
            self.lastBlurRequest = parent.blurRequest
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            DispatchQueue.main.async { self.parent.isFocused = true; self.parent.onFocusChange?(true) }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            DispatchQueue.main.async { self.parent.isFocused = false; self.parent.onFocusChange?(false) }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let value = field.stringValue
            DispatchQueue.main.async { self.parent.text = value }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Let the input method finish composing before treating keys as menu navigation.
            guard !textView.hasMarkedText() else { return false }
            if commandSelector == #selector(NSResponder.moveDown(_:)), let move = parent.onMoveSelection { move(1); return true }
            if commandSelector == #selector(NSResponder.moveUp(_:)), let move = parent.onMoveSelection { move(-1); return true }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), let cancel = parent.onCancel {
                cancel()
                textView.string = parent.text
                field?.stringValue = parent.text
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit?()
                return true
            }
            return false
        }
    }
}
