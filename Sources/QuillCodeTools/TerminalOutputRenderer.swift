import Foundation

/// Renders raw terminal (PTY) output into clean display text by applying the line-discipline control
/// sequences that command output commonly relies on: SGR color/style stripping, carriage-return line
/// overwrite, backspace, cursor-addressed redraws, erase-line / erase-display, and bell removal.
/// Without this, raw PTY output shows literal escape codes (`^[[31m`) and progress bars / TUI panes
/// pile up across the transcript instead of repainting in place.
///
/// Scope: this is a stateless, single-page screen buffer. It models common cursor addressing,
/// bounded scroll regions, insert/delete line, and alternate-screen latest-frame preservation well
/// enough for status dashboards and simple full-screen redraws while still rendering to plain text.
/// It is not a full terminal emulator: attributes, mouse tracking, and complex wide-character cell
/// measurement remain out of scope. Unhandled CSI/OSC sequences are stripped rather than shown,
/// which keeps colored output, git output, build logs, and TUI status output readable.
public enum TerminalOutputRenderer {
    /// Processes a raw terminal buffer into the text a user should see. Pure and idempotent on
    /// already-clean text, so it is safe to re-run over a growing `stdout` buffer.
    public static func render(
        _ raw: String,
        ambiguousWidthPolicy: TerminalOutputAmbiguousWidthPolicy = .narrow
    ) -> String {
        guard raw.contains(where: { $0 == "\u{1B}" || $0 == "\r" || $0 == "\u{08}" || $0 == "\u{07}" }) else {
            // Fast path: no control characters that change the visible result. (A lone `\n` is already
            // a plain newline.) Avoids rebuilding the buffer for the common all-text case.
            return raw
        }
        var screen = TerminalScreenBuffer(ambiguousWidthPolicy: ambiguousWidthPolicy)
        screen.feed(raw)
        return screen.text()
    }
}
