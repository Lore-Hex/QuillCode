import Foundation

/// Renders raw terminal (PTY) output into clean display text by applying the line-discipline control
/// sequences that the overwhelming majority of command output relies on: SGR color/style stripping,
/// carriage-return line overwrite, backspace, erase-line / erase-display, and bell removal. Without
/// this, raw PTY output shows literal escape codes (`^[[31m`) and progress bars / spinners that use
/// `\r` to redraw a line pile up across the transcript instead of overwriting in place.
///
/// Scope: this is a stateless, full-buffer line discipline. It deliberately does NOT implement full
/// two-dimensional cursor addressing (the `ESC[<row>;<col>H` / `ESC[<n>A|B|C|D` family) — faithful
/// redraw of full-screen TUIs like vim or htop is a larger follow-up that needs a real screen buffer.
/// Unhandled CSI/OSC sequences are stripped rather than shown, which keeps normal colored output, git
/// output, build logs, and `\r` progress indicators readable.
public enum TerminalOutputRenderer {
    /// Processes a raw terminal buffer into the text a user should see. Pure and idempotent on
    /// already-clean text, so it is safe to re-run over a growing `stdout` buffer.
    public static func render(_ raw: String) -> String {
        guard raw.contains(where: { $0 == "\u{1B}" || $0 == "\r" || $0 == "\u{08}" || $0 == "\u{07}" }) else {
            // Fast path: no control characters that change the visible result. (A lone `\n` is already
            // a plain newline.) Avoids rebuilding the buffer for the common all-text case.
            return raw
        }
        var screen = Screen()
        screen.feed(raw)
        return screen.text()
    }

    /// A single-page, line-addressed buffer. The cursor only moves horizontally (column) plus down on
    /// line feed; vertical addressing is out of scope (see type docs).
    private struct Screen {
        private var lines: [[Character]] = [[]]
        private var row = 0
        private var col = 0

        mutating func feed(_ raw: String) {
            let scalars = Array(raw.unicodeScalars)
            var i = 0
            while i < scalars.count {
                let scalar = scalars[i]
                switch scalar {
                case "\u{1B}":  // ESC — start of an escape sequence
                    i = handleEscape(scalars, from: i)
                case "\r":  // carriage return — back to column 0, overwrite from here
                    col = 0
                    i += 1
                case "\n":  // line feed — next line, column 0 (output relies on NL acting as CR+LF)
                    row += 1
                    if row >= lines.count { lines.append([]) }
                    col = 0
                    i += 1
                case "\u{08}":  // backspace
                    if col > 0 { col -= 1 }
                    i += 1
                case "\u{07}":  // bell — non-printing
                    i += 1
                default:
                    put(Character(scalar))
                    i += 1
                }
            }
        }

        /// Writes one character at the cursor (overwriting within the line or extending it), advancing
        /// the column.
        private mutating func put(_ character: Character) {
            if col < lines[row].count {
                lines[row][col] = character
            } else {
                while lines[row].count < col { lines[row].append(" ") }
                lines[row].append(character)
            }
            col += 1
        }

        /// Handles an escape sequence beginning at `start` (where `scalars[start] == ESC`). Applies the
        /// effects we model and returns the index of the first scalar after the sequence. A sequence
        /// that is incomplete at the end of the buffer is dropped (it will arrive complete on the next
        /// render of the growing buffer).
        private mutating func handleEscape(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
            let next = start + 1
            guard next < scalars.count else { return scalars.count }  // lone trailing ESC: drop

            switch scalars[next] {
            case "[":  // CSI — Control Sequence Introducer
                return handleCSI(scalars, escIndex: start, paramsStart: next + 1)
            case "]":  // OSC — terminated by BEL or ST (ESC \); strip the whole thing
                var i = next + 1
                while i < scalars.count {
                    if scalars[i] == "\u{07}" { return i + 1 }
                    if scalars[i] == "\u{1B}", i + 1 < scalars.count, scalars[i + 1] == "\\" { return i + 2 }
                    i += 1
                }
                return scalars.count  // unterminated OSC: drop the rest
            default:
                let value = scalars[next].value
                if value == 0x1B || value < 0x20 {
                    // ESC ESC (cancel-and-restart) or ESC followed by a C0 control: drop only this ESC
                    // and let the next scalar be processed normally — so a second ESC restarts a fresh
                    // sequence (instead of swallowing it and leaking the following CSI as text) and a
                    // control such as newline is not eaten.
                    return next
                }
                if value >= 0x20 && value <= 0x2F {
                    // Escape with intermediate bytes — the charset-designation family ESC ( B, ESC ) 0,
                    // ESC * ..., ESC + ... (emitted by tput sgr0, line-drawing). These are 3+ bytes:
                    // consume intermediate bytes through the final byte (0x30..0x7E) and drop the whole
                    // run, instead of leaking the final byte (a stray `B`/`0`) into the output.
                    var i = next
                    while i < scalars.count {
                        let byte = scalars[i].value
                        if byte >= 0x30 && byte <= 0x7E { return i + 1 }  // final byte
                        if byte < 0x20 || byte == 0x1B { return i }       // control/ESC aborts: re-dispatch
                        i += 1
                    }
                    return scalars.count  // incomplete intermediate escape at end of buffer: drop
                }
                // Plain two-character escape (e.g. ESC =, ESC >, ESC M, ESC 7): strip both bytes.
                return next + 1
            }
        }

        /// Parses a CSI sequence `ESC [ <params> <final>` and applies the ones we model (SGR, erase
        /// line, erase display). `paramsStart` points just past the `[`. Returns the index after the
        /// final byte, or `scalars.count` if the sequence is incomplete (dropped).
        private mutating func handleCSI(_ scalars: [Unicode.Scalar], escIndex: Int, paramsStart: Int) -> Int {
            var i = paramsStart
            var paramDigits: [Unicode.Scalar] = []
            // Parameter and intermediate bytes precede a final byte in 0x40...0x7E.
            while i < scalars.count {
                let value = scalars[i].value
                if value >= 0x40 && value <= 0x7E {
                    let final = scalars[i]
                    applyCSI(final: final, params: String(String.UnicodeScalarView(paramDigits)))
                    return i + 1
                }
                paramDigits.append(scalars[i])
                i += 1
            }
            return scalars.count  // incomplete CSI at end of buffer: drop
        }

        private mutating func applyCSI(final: Unicode.Scalar, params: String) {
            switch final {
            case "m":
                break  // SGR (color/style): strip — text-only rendering
            case "K":  // EL — erase in line
                switch params {
                case "", "0":  // cursor to end of line
                    if col < lines[row].count { lines[row].removeSubrange(col..<lines[row].count) }
                case "1":  // start of line to cursor (inclusive) -> spaces
                    for c in 0...min(col, max(lines[row].count - 1, 0)) where c < lines[row].count {
                        lines[row][c] = " "
                    }
                case "2":  // whole line
                    lines[row].removeAll()
                default:
                    break
                }
            case "J":  // ED — erase in display
                switch params {
                case "2", "3":  // whole screen (+ scrollback) -> reset
                    lines = [[]]
                    row = 0
                    col = 0
                case "", "0":  // cursor to end of screen
                    if col < lines[row].count { lines[row].removeSubrange(col..<lines[row].count) }
                    if row + 1 < lines.count { lines.removeSubrange((row + 1)..<lines.count) }
                case "1":  // start of screen to cursor
                    for r in 0..<row where r < lines.count { lines[r].removeAll() }
                default:
                    break
                }
            default:
                break  // cursor movement and everything else: ignored (out of scope)
            }
        }

        func text() -> String {
            lines.map { String($0) }.joined(separator: "\n")
        }
    }
}
