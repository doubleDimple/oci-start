import SwiftUI
import AppKit
import SwiftTerm

/// Exact ANSI palettes from the Web terminal. Surrounding controls use AppTheme.
struct TerminalTheme: Equatable {
    var background: String
    var foreground: String
    var cursor: String
    var colors: [String]
    var selection: String? = nil

    static var matrix: TerminalTheme { named("matrix") }
    static func named(_ key: String) -> TerminalTheme {
        switch key {
        case "tokyonight": return TerminalTheme(background: "1a1b26", foreground: "a9b1d6", cursor: "c0caf5", colors: ["15161e", "f7768e", "9ece6a", "e0af68", "7aa2f7", "bb9af7", "7dcfff", "a9b1d6", "414868", "f7768e", "9ece6a", "e0af68", "7aa2f7", "bb9af7", "7dcfff", "c0caf5"])
        case "dracula": return TerminalTheme(background: "282a36", foreground: "f8f8f2", cursor: "f8f8f2", colors: ["000000", "ff5555", "50fa7b", "f1fa8c", "bd93f9", "ff79c6", "8be9fd", "bbbbbb", "555555", "ff5555", "50fa7b", "f1fa8c", "bd93f9", "ff79c6", "8be9fd", "ffffff"])
        case "nord": return TerminalTheme(background: "2e3440", foreground: "d8dee9", cursor: "d8dee9", colors: ["3b4252", "bf616a", "a3be8c", "ebcb8b", "81a1c1", "b48ead", "88c0d0", "e5e9f0", "4c566a", "bf616a", "a3be8c", "ebcb8b", "81a1c1", "b48ead", "8fbcbb", "eceff4"])
        case "monokai": return TerminalTheme(background: "272822", foreground: "f8f8f2", cursor: "f8f8f0", colors: ["272822", "f92672", "a6e22e", "f4bf75", "66d9ef", "ae81ff", "a1efe4", "f8f8f2", "75715e", "f92672", "a6e22e", "f4bf75", "66d9ef", "ae81ff", "a1efe4", "f9f8f5"])
        case "solarizedLight": return TerminalTheme(background: "fdf6e3", foreground: "657b83", cursor: "657b83", colors: ["073642", "dc322f", "859900", "b58900", "268bd2", "d33682", "2aa198", "eee8d5", "002b36", "cb4b16", "586e75", "657b83", "839496", "6c71c4", "93a1a1", "fdf6e3"])
        case "highContrast": return TerminalTheme(background: "000000", foreground: "ffffff", cursor: "ffffff", colors: ["000000", "ff0000", "00ff00", "ffff00", "0088ff", "ff00ff", "00ffff", "ffffff", "7f7f7f", "ff4c4c", "4cff4c", "ffff4c", "4c9dff", "ff4cff", "4cffff", "ffffff"])
        case "matrix": return TerminalTheme(background: "000000", foreground: "00ff00", cursor: "00ff00", colors: ["000000", "ff0000", "00ff00", "ffff00", "00ffff", "ff00ff", "00ffff", "ffffff", "333333", "ff5555", "00ff00", "ffff55", "55ffff", "ff55ff", "55ffff", "ffffff"])
        default:
            let page = AppearanceController.shared.contentPalette
            var result = named(page.isDark ? "tokyonight" : "solarizedLight")
            result.background = page.card
            result.foreground = page.textPrimary
            result.cursor = page.textPrimary
            result.selection = page.border
            return result
        }
    }

    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    static func ansi(_ hex: String) -> SwiftTerm.Color {
        let value = UInt32(hex, radix: 16) ?? 0
        return SwiftTerm.Color(red: UInt16((value >> 16) & 255) * 257,
                               green: UInt16((value >> 8) & 255) * 257,
                               blue: UInt16(value & 255) * 257)
    }
}

enum TerminalShortcut { case search, increaseFont, decreaseFont, fullscreen }

/// Owns incremental output independently of SwiftUI updates and transcript retention.
/// All methods run on the main thread, as do NativeWSClient's callbacks.
final class TerminalSessionController {
    private weak var host: TerminalHostView?
    private var pending: [[UInt8]] = []
    private var pendingIndex = 0
    private var pendingBytes = 0
    private var scheduled = false
    private var generation = 0
    private var blocked = false
    private var archivedLog = ""
    private var bufferVersion = 0
    private var searchVersion = -1
    private var searchQuery = ""
    private var searchRows: [Int] = []
    private var searchIndex = -1
    var onOverflow: (() -> Void)?
    var onSearchResult: ((Int, Int) -> Void)?

    fileprivate func attach(_ view: TerminalHostView) {
        host = view
        scheduleDrain()
    }

    fileprivate func detach(_ view: TerminalHostView) {
        guard host === view else { return }
        generation += 1
        pending.removeAll(); pendingIndex = 0; pendingBytes = 0; scheduled = false
        host = nil
    }

    func write(_ text: String) { write(Data(text.utf8)) }

    func write(_ data: Data) {
        guard !blocked, !data.isEmpty else { return }
        let fragments = (data.count + 32767) / 32768
        guard data.count + pendingBytes <= 8 * 1024 * 1024,
              pending.count - pendingIndex + fragments <= 8192 else {
            blocked = true
            onOverflow?()
            return
        }
        let bytes = [UInt8](data)
        for start in stride(from: 0, to: bytes.count, by: 32768) {
            pending.append(Array(bytes[start..<min(start + 32768, bytes.count)]))
        }
        pendingBytes += bytes.count
        scheduleDrain()
    }

    private func scheduleDrain() {
        guard host != nil, !scheduled, pendingIndex < pending.count else { return }
        scheduled = true
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
            guard let self = self, expected == self.generation else { return }
            self.scheduled = false
            guard let view = self.host, self.pendingIndex < self.pending.count else { return }
            var bytes: [UInt8] = []
            while self.pendingIndex < self.pending.count {
                let next = self.pending[self.pendingIndex]
                if bytes.count + next.count > 32768 { break }
                bytes.append(contentsOf: next)
                self.pending[self.pendingIndex] = []
                self.pendingIndex += 1
            }
            self.pendingBytes -= bytes.count
            view.terminal.feed(byteArray: bytes[...])
            self.bufferVersion += 1
            if self.pendingIndex == self.pending.count {
                self.pending.removeAll(keepingCapacity: true); self.pendingIndex = 0
            } else if self.pendingIndex >= 256 {
                self.pending.removeFirst(self.pendingIndex); self.pendingIndex = 0
            }
            self.scheduleDrain()
        }
    }

    /// A fresh engine also discards unfinished UTF-8, OSC, CSI and IME sequences.
    func reset(clearLog: Bool = false) {
        if clearLog { archivedLog = "" } else { archiveVisibleText() }
        generation += 1
        pending.removeAll(); pendingIndex = 0; pendingBytes = 0
        scheduled = false; blocked = false
        host?.replaceTerminal()
        bufferVersion += 1
        clearSearch()
    }

    func clear() {
        archiveVisibleText()
        host?.terminal.clearVisibleBuffer()
        bufferVersion += 1
        clearSearch()
    }

    private func visibleText() -> String {
        guard let rows = host?.terminal.retainedBufferLines() else { return "" }
        var lines: [String] = []
        for row in rows {
            if row.isWrapped && !lines.isEmpty { lines[lines.count - 1] += row.text }
            else { lines.append(row.text) }
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private func archiveVisibleText() {
        let current = visibleText()
        if !current.isEmpty { archivedLog += current + "\n" }
        // This independent export history never feeds the VT parser.
        if archivedLog.utf8.count > 4 * 1024 * 1024 {
            archivedLog = String(archivedLog.suffix(1_000_000))
        }
    }

    func exportText() -> String { archivedLog + visibleText() }

    func search(_ query: String, direction: Int = 0) {
        guard !query.isEmpty, let native = host?.terminal else { clearSearch(); return }
        if query != searchQuery || searchVersion != bufferVersion {
            let sameQuery = query == searchQuery
            searchQuery = query
            let needle = query.lowercased()
            searchRows = native.retainedBufferLines().enumerated().compactMap {
                $0.element.text.lowercased().contains(needle) ? $0.offset : nil
            }
            searchIndex = sameQuery ? min(searchIndex, searchRows.count - 1) : -1
            searchVersion = bufferVersion
        }
        guard !searchRows.isEmpty else { searchIndex = -1; onSearchResult?(0, 0); return }
        if searchIndex < 0 { searchIndex = direction < 0 ? searchRows.count - 1 : 0 }
        else if direction != 0 {
            searchIndex = (searchIndex + direction + searchRows.count) % searchRows.count
        } else { searchIndex = 0 }
        native.scrollToBufferRow(searchRows[searchIndex])
        onSearchResult?(searchIndex + 1, searchRows.count)
    }

    private func clearSearch() {
        searchQuery = ""; searchRows = []; searchIndex = -1; searchVersion = -1
        host?.terminal.selectNone()
        onSearchResult?(0, 0)
    }

    fileprivate func resized() { bufferVersion += 1 }
}

struct TerminalEmulatorView: NSViewRepresentable {
    var controller: TerminalSessionController
    var isInteractive: Bool
    var onInput: (String) -> Void
    var fontSize: CGFloat = 14
    var theme: TerminalTheme = .matrix
    var onResize: ((Int, Int) -> Void)?
    var onShortcut: ((TerminalShortcut) -> Void)?

    func makeNSView(context: Context) -> TerminalHostView {
        let view = TerminalHostView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        view.controller = controller
        configure(view)
        controller.attach(view)
        return view
    }

    func updateNSView(_ view: TerminalHostView, context: Context) { configure(view) }

    private func configure(_ view: TerminalHostView) {
        view.onInput = onInput; view.onResize = onResize; view.onShortcut = onShortcut
        let wasInteractive = view.isInteractive
        view.isInteractive = isInteractive
        view.apply(fontSize: fontSize, theme: theme)
        if !wasInteractive && isInteractive {
            DispatchQueue.main.async { [weak view] in
                guard let view = view, view.isInteractive else { return }
                view.window?.makeFirstResponder(view.terminal)
            }
        }
        view.publishSize()
    }

    static func dismantleNSView(_ view: TerminalHostView, coordinator: ()) {
        view.controller?.detach(view)
        view.terminal.terminalDelegate = nil
    }
}

final class TerminalHostView: NSView, TerminalViewDelegate {
    fileprivate var terminal: NativeVTTerminalView!
    fileprivate weak var controller: TerminalSessionController?
    var onInput: ((String) -> Void)?
    var onResize: ((Int, Int) -> Void)?
    var onShortcut: ((TerminalShortcut) -> Void)?
    var isInteractive = false
    private var fontSize: CGFloat = 14
    private var theme = TerminalTheme.matrix
    private var lastSize = (0, 0)
    private var sizeScheduled = false
    private var reducedMotion: Bool?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        replaceTerminal()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    fileprivate func replaceTerminal() {
        terminal?.terminalDelegate = nil
        terminal?.removeFromSuperview()
        let view = NativeVTTerminalView(frame: bounds,
            font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular))
        terminal = view
        view.autoresizingMask = [.width, .height]
        view.terminalDelegate = self
        view.onShortcut = { [weak self] in self?.onShortcut?($0) }
        view.optionAsMetaKey = false
        view.setAccessibilityLabel("SSH terminal")
        addSubview(view)
        applyPalette()
        reducedMotion = nil
        applyCursorPreference()
        lastSize = (0, 0)
        publishSize()
    }

    fileprivate func apply(fontSize: CGFloat, theme: TerminalTheme) {
        let size = min(24, max(10, fontSize))
        if self.fontSize != size {
            self.fontSize = size
            terminal.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        if self.theme != theme { self.theme = theme; applyPalette() }
        applyCursorPreference()
    }

    private func applyCursorPreference() {
        let value = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reducedMotion != value {
            reducedMotion = value
            terminal.setCursorBlink(!value)
        }
    }

    private func applyPalette() {
        terminal.nativeBackgroundColor = TerminalTheme.color(theme.background)
        terminal.nativeForegroundColor = TerminalTheme.color(theme.foreground)
        terminal.caretColor = TerminalTheme.color(theme.cursor)
        terminal.caretTextColor = TerminalTheme.color(theme.background)
        terminal.selectedTextBackgroundColor = theme.selection.map(TerminalTheme.color)
            ?? TerminalTheme.color(theme.foreground).withAlphaComponent(0.3)
        terminal.installColors(theme.colors.map(TerminalTheme.ansi))
        terminal.needsDisplay = true
    }

    fileprivate func publishSize() {
        guard !sizeScheduled else { return }
        sizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sizeScheduled = false
            guard self.bounds.width >= 2, self.bounds.height >= 2 else { return }
            let engine = self.terminal.getTerminal()
            let size = (max(2, engine.cols), max(1, engine.rows))
            if self.lastSize != size {
                self.lastSize = size
                self.onResize?(size.0, size.1)
            }
        }
    }

    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        guard source === terminal else { return }
        controller?.resized()
        publishSize()
    }
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        guard source === terminal, isInteractive else { return }
        onInput?(String(decoding: data, as: UTF8.self))
    }
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
        guard source === terminal, let url = URL(string: link),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Keep AppKit text input and VT application-key modes; intercept only UI shortcuts.
final class NativeVTTerminalView: SwiftTerm.TerminalView {
    var onShortcut: ((TerminalShortcut) -> Void)?
    private var composition = ""
    private var compositionSelection = NSRange(location: 0, length: 0)

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let command = event.modifierFlags.contains(.command)
        if hasMarkedText() && !command { interpretKeyEvents([event]); return }
        if command && key == "f" { onShortcut?(.search); return }
        if command && ["+", "="].contains(key) { onShortcut?(.increaseFont); return }
        if command && key == "-" { onShortcut?(.decreaseFont); return }
        if event.keyCode == 103 { onShortcut?(.fullscreen); return }
        if key == "c", command || (event.modifierFlags.contains(.control) && !(getSelection() ?? "").isEmpty) {
            copy(self); return
        }
        if command && key == "v" { paste(self); return }
        if key == "v" && event.modifierFlags.contains([.control, .shift]) { paste(self); return }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        let payload = getTerminal().bracketedPasteMode
            ? "\u{001B}[200~" + normalized + "\u{001B}[201~" : normalized
        send(txt: payload)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        unmarkText()
        if !text.isEmpty { send(txt: text) }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        composition = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let length = (composition as NSString).length
        let start = min(selectedRange.location, length)
        compositionSelection = NSRange(location: start, length: min(selectedRange.length, length - start))
        needsDisplay = true
    }

    override func unmarkText() { composition = ""; needsDisplay = true }
    override func hasMarkedText() -> Bool { !composition.isEmpty }
    override func markedRange() -> NSRange {
        hasMarkedText() ? NSRange(location: 0, length: (composition as NSString).length)
            : NSRange(location: NSNotFound, length: 0)
    }
    override func selectedRange() -> NSRange { hasMarkedText() ? compositionSelection : super.selectedRange() }
    override func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.underlineStyle, .foregroundColor] }
    override func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard hasMarkedText(), range.location != NSNotFound else { return nil }
        let actual = NSIntersectionRange(range, markedRange())
        actualRange?.pointee = actual
        return NSAttributedString(string: (composition as NSString).substring(with: actual))
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hasMarkedText() else { return }
        let text = NSAttributedString(string: composition, attributes: [
            .font: font, .foregroundColor: nativeForegroundColor,
            .backgroundColor: nativeBackgroundColor, .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        text.draw(at: caretFrame.origin)
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
