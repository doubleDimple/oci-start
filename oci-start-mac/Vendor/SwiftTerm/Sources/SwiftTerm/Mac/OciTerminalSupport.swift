#if os(macOS)
import AppKit

extension TerminalView {
    /// Retained rendered lines, including whether they continue the preceding line.
    public func retainedBufferLines() -> [(text: String, isWrapped: Bool)] {
        let buffer = terminal.buffer
        return (0..<buffer.lines.count).map {
            let line = buffer.lines[$0]
            return (line.translateToString(trimRight: true), line.isWrapped)
        }
    }

    public func scrollToBufferRow(_ row: Int) {
        scrollTo(row: max(0, min(row, terminal.buffer.lines.count - terminal.rows)))
    }

    public func setCursorBlink(_ blink: Bool) {
        terminal.options.cursorStyle = blink ? .blinkBlock : .steadyBlock
        caretView.updateCursorStyle()
    }

    /// Equivalent to xterm.clear(): retain the current line and active parser modes.
    public func clearVisibleBuffer() {
        let buffer = terminal.buffer
        let current = buffer.lines[buffer.yBase + buffer.y]
        current.isWrapped = false
        buffer.lines.count = 1
        buffer.lines[0] = current
        buffer.yBase = 0
        buffer.yDisp = 0
        buffer.y = 0
        buffer.linesTop = 0
        if terminal.rows > 1 {
            for _ in 1..<terminal.rows {
                buffer.lines.push(buffer.getBlankLine(attribute: CharData.defaultAttr))
            }
        }
        selection.active = false
        terminal.refresh(startRow: 0, endRow: terminal.rows - 1)
        terminal.syncScrollArea()
        updateScroller()
        updateCursorPosition()
        queuePendingDisplay()
    }
}
#endif
