import AppKit
import SwiftUI
import Foundation
import SwiftTerm
@testable import OciStart

/// Offline checks against the actual bundled VT engine and SwiftUI/AppKit adapter.
/// Compile beside the QA executable, link OciStart + SwiftTerm production objects,
/// then call `let checks = try await TerminalFixture.run()` from its main-actor Task.
/// No entry point, process launch, network connection, preferences or clipboard writes.
enum TerminalFixture {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func run() async throws -> [String] {
        _ = NSApplication.shared
        var passed: [String] = []

        try fragmentedUTF8AndEscapeSequences()
        passed.append("terminal: split UTF-8 / CSI and actual ANSI cell color")
        try carriageReturnAndCursor()
        passed.append("terminal: CR overwrite and cursor addressing")
        try alternateScreenAndResize()
        passed.append("terminal: alternate-screen restoration and font/frame resize preservation")

        let mounted = MountedTerminal()
        defer { mounted.close() }
        try await waitFor("SwiftUI terminal mount") { mounted.native != nil && mounted.host != nil }

        try await incrementalController(mounted)
        passed.append("terminal: controller byte stream across 32 KiB parser batches")
        try await clearAndReset(mounted)
        passed.append("terminal: clear retains prompt/log; reset discards parser/queued work")
        try await searchAndInput(mounted)
        passed.append("terminal: previous/next search scroll, resize callback and disabled input")
        try await overflow(mounted)
        passed.append("terminal: complete-payload overflow rejection and reset recovery")
        return passed
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    @MainActor
    private static func freshNative() -> NativeVTTerminalView {
        let view = NativeVTTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 240),
                                        font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
        view.resize(cols: 40, rows: 8)
        return view
    }

    @MainActor
    private static func row(_ view: NativeVTTerminalView, _ index: Int) -> String {
        let rows = view.retainedBufferLines()
        return index < rows.count ? rows[index].text : ""
    }

    @MainActor
    private static func fragmentedUTF8AndEscapeSequences() throws {
        let view = freshNative()
        // Feed each fragment synchronously so neither SwiftUI nor queue coalescing
        // can accidentally turn this into a single, already-valid String input.
        let fragments: [[UInt8]] = [
            [0x41, 0xe2], [0x82], [0xac, 0xe4, 0xb8], [0xad, 0xf0, 0x9f],
            [0x99], [0x82, 0x42]
        ]
        for bytes in fragments { view.feed(byteArray: bytes[...]) }
        try require(row(view, 0) == "A€中🙂B", "Split UTF-8 rendered \(String(reflecting: row(view, 0))); expected A€中🙂B")
        let columns = freshNative()
        columns.resize(cols: 4, rows: 4)
        columns.feed(text: "ab中Z")
        try require(row(columns, 0) == "ab中" && row(columns, 1) == "Z",
                    "A wide glyph at the right edge must not swallow text on the wrapped next row")
        guard let edge = columns.getTerminal().getLine(row: 0) else { throw Failure(description: "Missing edge-glyph row") }
        try require(edge.translateToString(startCol: 3, endCol: 4).isEmpty,
                    "A column range containing only a wide continuation must not export NUL or a space")
        try require(edge.translateToString(startCol: 2, endCol: 4) == "中",
                    "A two-column range must contain the wide glyph exactly once")
        let suffix = freshNative()
        suffix.feed(text: "A中B")
        guard let suffixLine = suffix.getTerminal().getLine(row: 0) else { throw Failure(description: "Missing suffix row") }
        try require(suffixLine.translateToString(trimRight: true, startCol: 2, endCol: 4) == "B",
                    "A range beginning at a wide continuation must preserve the following ordinary character")

        let colors = freshNative()
        for fragment in ["\u{001B}", "[", "3", "1", "m", "R", "\u{001B}[0", "m", "D"] {
            colors.feed(byteArray: Array(fragment.utf8)[...])
        }
        try require(row(colors, 0) == "RD", "Split CSI must execute instead of leaking escape text")
        try require(colors.getTerminal().getCharData(col: 0, row: 0)?.attribute.fg == .ansi256(code: 1),
                    "SGR 31 must set the first cell's foreground to ANSI red")
        try require(colors.getTerminal().getCharData(col: 1, row: 0)?.attribute.fg == .defaultColor,
                    "SGR 0 must restore the following cell's default foreground")
    }

    @MainActor
    private static func carriageReturnAndCursor() throws {
        let view = freshNative()
        view.feed(text: "abcdef\rXY")
        try require(row(view, 0) == "XYcdef", "CR must overwrite the same row, not append a new log line")
        view.feed(text: "\u{001B}[2;3HZ")
        try require(row(view, 1) == "  Z", "CUP must place Z at row 2, column 3")
        let cursor = view.getTerminal().getCursorLocation()
        try require(cursor.x == 3 && cursor.y == 1, "Cursor must advance one cell after addressed output")
        view.feed(text: "\u{001B}[1;3H\u{001B}[K")
        try require(row(view, 0) == "XY", "Erase-to-end must remove overwritten text after the cursor")
    }

    @MainActor
    private static func alternateScreenAndResize() throws {
        let view = freshNative()
        let engine = view.getTerminal()
        view.feed(text: "shell prompt")
        let savedCursor = engine.getCursorLocation()
        view.feed(text: "\u{001B}[?1049h\u{001B}[Hvim buffer")
        try require(row(view, 0) == "vim buffer", "Alternate screen must display its own content")
        let mainText = String(decoding: engine.getBufferAsData(kind: .normal), as: UTF8.self)
        try require(mainText.contains("shell prompt") && !mainText.contains("vim buffer"),
                    "The normal screen must remain separate while an alternate screen is active")

        // Both code paths used to risk resetting the terminal when the font changed.
        view.font = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 330)
        try require(view.getTerminal() === engine, "Font/frame resize must retain the engine instance")
        try require(view.retainedBufferLines().contains(where: { $0.text.contains("vim buffer") }),
                    "Font/frame resize must preserve the active alternate-screen content")
        view.feed(text: "\u{001B}[?1049l")
        try require(row(view, 0) == "shell prompt", "Leaving the alternate screen must restore the normal screen")
        let restored = engine.getCursorLocation()
        try require(restored.x == savedCursor.x && restored.y == savedCursor.y,
                    "Alternate-screen exit must restore the saved shell cursor")

        view.resize(cols: 32, rows: 10)
        try require(engine.cols == 32 && engine.rows == 10, "Explicit terminal resize must update grid dimensions")
        try require(row(view, 0) == "shell prompt", "Explicit resize must preserve normal-screen text")
    }

    @MainActor
    private static func incrementalController(_ mounted: MountedTerminal) async throws {
        mounted.controller.reset(clearLog: true)
        // The euro sign starts at the final byte of the adapter's first 32 KiB
        // batch. This catches per-batch String decoding and parser resets.
        let text = String(repeating: "x", count: 32767) + "€中🙂END_OF_BATCH"
        mounted.controller.write(Data(text.utf8))
        try await waitFor("incremental controller output") { mounted.controller.exportText().contains("END_OF_BATCH") }
        try require(mounted.controller.exportText() == text,
                    "Controller batches must preserve all UTF-8 and wrapped text without replaying output")
        mounted.controller.write("\r\nSECOND_WRITE")
        try await waitFor("second controller output") { mounted.controller.exportText().hasSuffix("SECOND_WRITE") }
        let rendered = mounted.controller.exportText()
        try require(rendered.components(separatedBy: "END_OF_BATCH").count == 2,
                    "A subsequent update must feed only new output, not replay the accumulated transcript")
    }

    @MainActor
    private static func clearAndReset(_ mounted: MountedTerminal) async throws {
        mounted.controller.reset(clearLog: true)
        mounted.controller.write("history line\r\nprompt> ")
        try await waitFor("clear setup") { mounted.controller.exportText().contains("prompt>") }
        mounted.controller.clear()
        guard let native = mounted.native else { throw Failure(description: "Missing native view after clear") }
        let retainedPrompt = row(native, 0)
        print("Terminal clear retained row 0: \(String(reflecting: retainedPrompt))")
        try require(retainedPrompt == "prompt> ",
                    "Clear must preserve explicitly printed trailing spaces; actual row: \(String(reflecting: retainedPrompt))")
        try require(!native.retainedBufferLines().contains(where: { $0.text.contains("history line") }),
                    "Clear must remove preceding rendered history")
        try require(mounted.controller.exportText().contains("history line"),
                    "Clearing the display must not discard the separately retained export log")

        // Let an incomplete OSC enter the real parser before replacing it.
        mounted.controller.write("\u{001B}]0;unfinished-title")
        try await pauseFrames()
        let old = mounted.native
        mounted.controller.reset(clearLog: true)
        try require(mounted.native !== old, "Reset must replace the native engine, including decoder/parser state")
        mounted.controller.write("AFTER_OSC_RESET")
        try await waitFor("OSC reset output") { mounted.controller.exportText() == "AFTER_OSC_RESET" }

        mounted.controller.write(Data([0xf0, 0x9f]))
        try await pauseFrames()
        mounted.controller.reset(clearLog: true)
        mounted.controller.write("AFTER_UTF8_RESET")
        try await waitFor("UTF-8 reset output") { mounted.controller.exportText() == "AFTER_UTF8_RESET" }

        // Also invalidate work which was queued but has not reached the parser.
        mounted.controller.write("STALE_QUEUED_OUTPUT")
        mounted.controller.reset(clearLog: true)
        mounted.controller.write("NEW_CONNECTION")
        try await waitFor("generation reset output") { mounted.controller.exportText() == "NEW_CONNECTION" }
        try await pauseFrames()
        try require(mounted.controller.exportText() == "NEW_CONNECTION", "An old scheduled drain must not leak across reset")
    }

    @MainActor
    private static func searchAndInput(_ mounted: MountedTerminal) async throws {
        mounted.controller.reset(clearLog: true)
        var lines = (0..<120).map { "line \($0)" }
        lines[10] = "needle first"
        lines[80] = "needle second"
        lines.append("SEARCH_READY")
        mounted.controller.write(lines.joined(separator: "\r\n"))
        try await waitFor("search setup") { mounted.controller.exportText().contains("SEARCH_READY") }
        guard let native = mounted.native, let host = mounted.host else { throw Failure(description: "Missing mounted terminal") }
        var result = (0, 0)
        mounted.controller.onSearchResult = { result = ($0, $1) }
        mounted.controller.search("needle")
        try require(result == (1, 2), "Search must report the first of two matching rendered lines")
        let firstRow = native.getTerminal().buffer.yDisp
        mounted.controller.search("needle", direction: 1)
        try require(result == (2, 2) && native.getTerminal().buffer.yDisp > firstRow,
                    "Next search must scroll to the later match")
        mounted.controller.search("needle", direction: -1)
        try require(result == (1, 2) && native.getTerminal().buffer.yDisp == firstRow,
                    "Previous search must scroll back to the earlier match")
        mounted.controller.search("needle", direction: -1)
        try require(result == (2, 2), "Previous at the first match must wrap to the final match")

        mounted.probes.inputs.removeAll()
        host.isInteractive = false
        native.insertText("blocked", replacementRange: NSRange(location: NSNotFound, length: 0))
        try require(mounted.probes.inputs.isEmpty, "Disconnected terminal input must not reach the transport callback")
        host.isInteractive = true
        native.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        try require(mounted.probes.inputs.isEmpty && native.hasMarkedText(), "IME composition must remain local until committed")
        native.insertText("中", replacementRange: NSRange(location: NSNotFound, length: 0))
        try require(mounted.probes.inputs == ["中"] && !native.hasMarkedText(), "IME commit must send exactly one UTF-8 text input")

        let oldColumns = native.getTerminal().cols
        native.frame.size.width += 160
        try await waitFor("native resize callback") {
            guard let last = mounted.probes.sizes.last else { return false }
            return last.0 == native.getTerminal().cols && last.0 != oldColumns
        }
        try require(native.retainedBufferLines().contains(where: { $0.text == "needle first" }),
                    "Resizing while searching must retain the terminal buffer")
    }

    @MainActor
    private static func overflow(_ mounted: MountedTerminal) async throws {
        mounted.controller.reset(clearLog: true)
        var overflowCount = 0
        mounted.controller.onOverflow = { overflowCount += 1 }
        mounted.controller.write(Data(repeating: 0x78, count: 8 * 1024 * 1024 + 1))
        mounted.controller.write("MUST_NOT_APPEAR")
        try await pauseFrames()
        try require(overflowCount == 1 && mounted.controller.exportText().isEmpty,
                    "Overflow must reject the entire payload and stop accepting fragments until reset")
        mounted.controller.reset(clearLog: true)
        mounted.controller.write("RECOVERED")
        try await waitFor("overflow recovery") { mounted.controller.exportText() == "RECOVERED" }
    }

    @MainActor
    private static func waitFor(_ label: String, timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { throw Failure(description: "Timed out: \(label)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    private static func pauseFrames() async throws {
        // Allow an incomplete parser fragment (which has no visible completion
        // predicate) to cross the adapter's 60 Hz drain before the next action.
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    private final class Probes {
        var inputs: [String] = []
        var sizes: [(Int, Int)] = []
    }

    @MainActor
    private final class MountedTerminal {
        let controller: TerminalSessionController
        let probes: Probes
        let window: NSWindow
        let hosting: NSHostingView<TerminalEmulatorView>

        init() {
            let controller = TerminalSessionController()
            let probes = Probes()
            self.controller = controller
            self.probes = probes
            hosting = NSHostingView(rootView: TerminalEmulatorView(
                controller: controller, isInteractive: false,
                onInput: { probes.inputs.append($0) }, fontSize: 14, theme: .matrix,
                onResize: { probes.sizes.append(($0, $1)) }, onShortcut: nil))
            window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
        }

        var native: NativeVTTerminalView? { descendant(in: hosting, type: NativeVTTerminalView.self) }
        var host: TerminalHostView? { descendant(in: hosting, type: TerminalHostView.self) }

        private func descendant<T: NSView>(in view: NSView, type: T.Type) -> T? {
            if let result = view as? T { return result }
            for child in view.subviews {
                if let result = descendant(in: child, type: type) { return result }
            }
            return nil
        }

        func close() {
            controller.reset(clearLog: true)
            window.contentView = nil
            window.close()
        }
    }
}
