# SwiftTerm 1.2.5

Source: https://github.com/migueldeicaza/SwiftTerm/tree/1.2.5
Commit: `e2b431dbf73f775fb4807a33e4572ffd3dc6933a`
License: MIT, retained in LICENSE and copied into the Swift package resource bundle.

This local package pins the upstream source for reproducible Xcode 13.2.1 / Swift 5.5.2 builds. The upstream 1.2.5 manifest says Swift 5.1 but its source uses Swift 5.7 optional-binding shorthand. Changes:

- Expand shorthand optional bindings and remove unavailable visionOS compilation conditions; exclude iOS sources from the macOS target.
- Build only the SwiftTerm library, without upstream sample or test targets. No external dependencies.
- Retain 5000 scrollback lines, matching the Web terminal.
- Preserve terminal state when font changes resize its grid; upstream `TerminalView.resize` unconditionally reset the parser and screen.
- Use the same effective width for font and frame resizing, and clamp transient zero-sized layouts to a valid grid. Keep native draw/keyDown overridable for the application input-method adapter.
- Add `OciTerminalSupport.swift` for retained buffer lines, scroll positioning, cursor preference, and local clear while preserving the current line and parser modes.
- Export physical empty cells as spaces and omit the NUL continuation cell of wide characters, including column ranges beginning on a continuation. This preserves Chinese/emoji text in search, selection and logs.

The app adapter handles bounded incremental output, reconnection by replacing the native view, bracketed paste, search and theme colors. SSH transport remains the existing application WebSocket API.
