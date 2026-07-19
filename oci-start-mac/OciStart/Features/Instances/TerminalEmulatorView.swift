import SwiftUI
import AppKit

/// Terminal surface for SSH (plain monospaced + key capture).
/// Strips basic ANSI CSI for readable display; not a full xterm.
struct TerminalTheme: Equatable {
    var background: NSColor
    var foreground: NSColor
    var cursor: NSColor

    static let matrix = TerminalTheme(
        background: NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 1),
        foreground: NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1),
        cursor: NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1)
    )
    static let tokyonight = TerminalTheme(
        background: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.15, alpha: 1),
        foreground: NSColor(calibratedRed: 0.66, green: 0.69, blue: 0.84, alpha: 1),
        cursor: NSColor(calibratedRed: 0.75, green: 0.79, blue: 0.96, alpha: 1)
    )
    static let dracula = TerminalTheme(
        background: NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.21, alpha: 1),
        foreground: NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.95, alpha: 1),
        cursor: NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.95, alpha: 1)
    )
    static let nord = TerminalTheme(
        background: NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1),
        foreground: NSColor(calibratedRed: 0.85, green: 0.87, blue: 0.91, alpha: 1),
        cursor: NSColor(calibratedRed: 0.85, green: 0.87, blue: 0.91, alpha: 1)
    )
    static let monokai = TerminalTheme(
        background: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.13, alpha: 1),
        foreground: NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.95, alpha: 1),
        cursor: NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.94, alpha: 1)
    )
    static let solarizedLight = TerminalTheme(
        background: NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.89, alpha: 1),
        foreground: NSColor(calibratedRed: 0.40, green: 0.48, blue: 0.51, alpha: 1),
        cursor: NSColor(calibratedRed: 0.40, green: 0.48, blue: 0.51, alpha: 1)
    )
    static let highContrast = TerminalTheme(
        background: .black,
        foreground: .white,
        cursor: .white
    )

    static func named(_ key: String) -> TerminalTheme {
        switch key {
        case "tokyonight": return .tokyonight
        case "dracula": return .dracula
        case "nord": return .nord
        case "monokai": return .monokai
        case "solarizedLight": return .solarizedLight
        case "highContrast": return .highContrast
        default: return .matrix
        }
    }
}

struct TerminalEmulatorView: NSViewRepresentable {
    @Binding var output: String
    var isInteractive: Bool
    var onInput: (String) -> Void
    var fontSize: CGFloat = 14
    var theme: TerminalTheme = .matrix
    /// 终端可视尺寸变化时回调（cols, rows）
    var onResize: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = theme.background

        let tv = KeyCatchingTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.textColor = theme.foreground
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.delegate = context.coordinator
        tv.insertionPointColor = theme.cursor
        tv.onKeyInput = { [weak coordinator = context.coordinator] s in
            coordinator?.onInput(s)
        }
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onInput = onInput
        context.coordinator.onResize = onResize
        context.coordinator.isInteractive = isInteractive
        context.coordinator.fontSize = fontSize
        guard let tv = context.coordinator.textView else { return }

        let cleaned = TerminalANSI.strip(output)
        if tv.string != cleaned {
            let wasAtBottom = context.coordinator.isNearBottom
            tv.string = cleaned
            if wasAtBottom {
                tv.scrollToEndOfDocument(nil)
            }
        }
        nsView.backgroundColor = theme.background
        tv.textColor = theme.foreground
        tv.insertionPointColor = theme.cursor
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if tv.font?.pointSize != fontSize {
            tv.font = font
        }
        context.coordinator.reportResizeIfNeeded()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onInput: (String) -> Void
        var onResize: ((Int, Int) -> Void)?
        var isInteractive = true
        var fontSize: CGFloat = 14
        weak var textView: KeyCatchingTextView?
        weak var scrollView: NSScrollView?
        private var lastCols = 0
        private var lastRows = 0

        init(onInput: @escaping (String) -> Void, onResize: ((Int, Int) -> Void)?) {
            self.onInput = onInput
            self.onResize = onResize
        }

        var isNearBottom: Bool {
            guard let tv = textView, let scroll = tv.enclosingScrollView else { return true }
            let visible = scroll.contentView.bounds
            let doc = scroll.documentView?.bounds ?? .zero
            return visible.maxY >= doc.maxY - 40
        }

        func reportResizeIfNeeded() {
            guard let scroll = scrollView else { return }
            let size = scroll.contentView.bounds.size
            guard size.width > 20, size.height > 20 else { return }
            let charW = max(NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
                .maximumAdvancement.width, 7)
            let charH = max(fontSize * 1.35, 14)
            let cols = max(40, Int(floor((size.width - 20) / charW)))
            let rows = max(10, Int(floor((size.height - 20) / charH)))
            if cols != lastCols || rows != lastRows {
                lastCols = cols
                lastRows = rows
                onResize?(cols, rows)
            }
        }
    }
}

/// Captures key events and forwards as terminal input (does not echo locally).
final class KeyCatchingTextView: NSTextView {
    var onKeyInput: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Cmd+C / Cmd+A etc. keep default for copy/select
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        // Map special keys to terminal sequences
        if let mapped = mapSpecialKey(event) {
            onKeyInput?(mapped)
            return
        }
        if let chars = event.characters, !chars.isEmpty {
            onKeyInput?(chars)
            return
        }
        super.keyDown(with: event)
    }

    private func mapSpecialKey(_ event: NSEvent) -> String? {
        switch event.keyCode {
        case 126: return "\u{001B}[A" // up
        case 125: return "\u{001B}[B" // down
        case 124: return "\u{001B}[C" // right
        case 123: return "\u{001B}[D" // left
        case 51: return "\u{007F}"    // backspace
        case 117: return "\u{001B}[3~" // delete
        case 115: return "\u{001B}[H" // home
        case 119: return "\u{001B}[F" // end
        case 116: return "\u{001B}[5~" // page up
        case 121: return "\u{001B}[6~" // page down
        case 48: return "\t"          // tab
        case 36: return "\r"          // return
        default: return nil
        }
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general.string(forType: .string) ?? ""
        if !pb.isEmpty {
            onKeyInput?(pb)
        }
    }
}

enum TerminalANSI {
    /// Strip CSI / OSC sequences for plain-text display.
    static func strip(_ s: String) -> String {
        var out = s
        if let re = try? NSRegularExpression(pattern: "\\u001B\\[[0-9;?]*[ -/]*[@-~]", options: []) {
            out = re.stringByReplacingMatches(in: out, options: [], range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        if let re2 = try? NSRegularExpression(pattern: "\\u001B\\][^\\u0007\\u001B]*(?:\\u0007|\\u001B\\\\)", options: []) {
            out = re2.stringByReplacingMatches(in: out, options: [], range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        out = out.replacingOccurrences(of: "\u{001B}", with: "")
        return out
    }

    /// 下载日志用：去掉 ANSI
    static func plainForLog(_ s: String) -> String {
        strip(s)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
