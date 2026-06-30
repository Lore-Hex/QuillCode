import Foundation

/// Renders raw terminal (PTY) output into clean display text by applying the line-discipline control
/// sequences that command output commonly relies on: SGR color/style stripping, carriage-return line
/// overwrite, backspace, cursor-addressed redraws, erase-line / erase-display, and bell removal.
/// Without this, raw PTY output shows literal escape codes (`^[[31m`) and progress bars / TUI panes
/// pile up across the transcript instead of repainting in place.
///
/// Scope: this is a stateless, single-page screen buffer. It models common cursor addressing well
/// enough for status dashboards and simple full-screen redraws (`ESC[H`, `ESC[<row>;<col>H`,
/// `ESC[<n>A|B|C|D`, `ESC[<n>G`, save/restore cursor) while still rendering to plain text. It is not
/// a full terminal emulator: alternate-screen scrollback, scroll regions, insert/delete line,
/// attributes, and complex wide-character cell measurement remain out of scope. Unhandled CSI/OSC
/// sequences are stripped rather than shown, which keeps colored output, git output, build logs, and
/// TUI status output readable.
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

    /// A single-page, line-addressed buffer. The cursor tracks rows and columns in terminal-cell-ish
    /// units, then exports the visible page as plain text.
    private struct Screen {
        /// Hard caps on how far the cursor can move, and therefore how much padding it can force into
        /// the backing buffer. Normal printed output can still create long lines; these caps only bound
        /// cursor addressing from garbled or hostile escape sequences.
        private static let maxRows = 1_000
        private static let maxCols = 1_000
        private static let maxCursorParameter = 1_001

        private var lines: [[Character]] = [[]]
        private var row = 0
        private var col = 0
        private var savedCursor: (row: Int, col: Int)?

        mutating func feed(_ raw: String) {
            let scalars = Array(raw.unicodeScalars)
            var i = 0
            while i < scalars.count {
                let scalar = scalars[i]
                switch scalar {
                case "\u{1B}":  // ESC: start of an escape sequence
                    i = handleEscape(scalars, from: i)
                case "\r":  // carriage return: back to column 0, overwrite from here
                    col = 0
                    i += 1
                case "\n":  // line feed: next line, column 0
                    moveRow(by: 1)
                    col = 0
                    i += 1
                case "\u{08}":  // backspace
                    if col > 0 { col -= 1 }
                    i += 1
                case "\u{07}":  // bell: non-printing
                    i += 1
                default:
                    put(Character(scalar))
                    i += 1
                }
            }
        }

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
        /// that is incomplete at the end of the buffer is dropped; it will arrive complete on the next
        /// render of the growing buffer.
        private mutating func handleEscape(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
            let next = start + 1
            guard next < scalars.count else { return scalars.count }

            switch scalars[next] {
            case "[":  // CSI: Control Sequence Introducer
                return handleCSI(scalars, paramsStart: next + 1)
            case "]":  // OSC: terminated by BEL or ST (ESC \); strip the whole thing
                var i = next + 1
                while i < scalars.count {
                    if scalars[i] == "\u{07}" { return i + 1 }
                    if scalars[i] == "\u{1B}", i + 1 < scalars.count, scalars[i + 1] == "\\" { return i + 2 }
                    i += 1
                }
                return scalars.count
            case "7":
                saveCursor()
                return next + 1
            case "8":
                restoreCursor()
                return next + 1
            default:
                let value = scalars[next].value
                if value == 0x1B || value < 0x20 {
                    // ESC ESC or ESC followed by a C0 control: drop only this ESC and re-dispatch the
                    // following scalar normally.
                    return next
                }
                if value >= 0x20 && value <= 0x2F {
                    // Escape with intermediate bytes, e.g. charset designation ESC ( B. Consume
                    // intermediates through the final byte so the final byte does not leak as text.
                    var i = next
                    while i < scalars.count {
                        let byte = scalars[i].value
                        if byte >= 0x30 && byte <= 0x7E { return i + 1 }
                        if byte < 0x20 || byte == 0x1B { return i }
                        i += 1
                    }
                    return scalars.count
                }
                // Plain two-character escape (e.g. ESC =, ESC >, ESC M): strip both bytes.
                return next + 1
            }
        }

        /// Parses a CSI sequence `ESC [ <params> <final>` and applies the ones we model. `paramsStart`
        /// points just past the `[`. Returns the index after the final byte, or `scalars.count` if the
        /// sequence is incomplete.
        private mutating func handleCSI(_ scalars: [Unicode.Scalar], paramsStart: Int) -> Int {
            var i = paramsStart
            var paramDigits: [Unicode.Scalar] = []
            while i < scalars.count {
                let value = scalars[i].value
                if value >= 0x40 && value <= 0x7E {
                    applyCSI(final: scalars[i], params: String(String.UnicodeScalarView(paramDigits)))
                    return i + 1
                }
                paramDigits.append(scalars[i])
                i += 1
            }
            return scalars.count
        }

        private mutating func applyCSI(final: Unicode.Scalar, params: String) {
            switch final {
            case "m":
                break  // SGR (color/style): strip for text-only rendering
            case "H", "f":  // CUP / HVP: 1-based row;column, default 1;1
                let parts = csiParams(params)
                let targetRow = (parts.count > 0 ? max(1, parts[0]) : 1) - 1
                let targetCol = (parts.count > 1 ? max(1, parts[1]) : 1) - 1
                setCursor(row: targetRow, col: targetCol)
            case "A":  // CUU: cursor up
                moveRow(by: -firstParam(params))
            case "B":  // CUD: cursor down
                moveRow(by: firstParam(params))
            case "C":  // CUF: cursor forward
                col = clampCol(col + firstParam(params))
            case "D":  // CUB: cursor back
                col = clampCol(col - firstParam(params))
            case "E":  // CNL: cursor next line, column 0
                moveRow(by: firstParam(params))
                col = 0
            case "F":  // CPL: cursor previous line, column 0
                moveRow(by: -firstParam(params))
                col = 0
            case "G", "`":  // CHA / HPA: cursor to absolute column (1-based)
                col = clampCol(firstParam(params) - 1)
            case "d":  // VPA: cursor to absolute row (1-based)
                setRow(firstParam(params) - 1)
            case "s":
                saveCursor()
            case "u":
                restoreCursor()
            case "K":  // EL: erase in line
                switch params {
                case "", "0":  // cursor to end of line
                    if col < lines[row].count { lines[row].removeSubrange(col..<lines[row].count) }
                case "1":  // start of line to cursor inclusive
                    if !lines[row].isEmpty {
                        let end = min(col, lines[row].count - 1)
                        for c in 0...end { lines[row][c] = " " }
                    }
                case "2":  // whole line
                    lines[row].removeAll()
                default:
                    break
                }
            case "J":  // ED: erase in display
                switch params {
                case "2", "3":  // whole screen (+ scrollback) -> reset
                    lines = [[]]
                    row = 0
                    col = 0
                case "", "0":  // cursor to end of screen
                    if col < lines[row].count { lines[row].removeSubrange(col..<lines[row].count) }
                    if row + 1 < lines.count { lines.removeSubrange((row + 1)..<lines.count) }
                case "1":  // start of screen to cursor inclusive
                    for r in 0..<row where r < lines.count { lines[r].removeAll() }
                    if !lines[row].isEmpty {
                        let end = min(col, lines[row].count - 1)
                        for c in 0...end { lines[row][c] = " " }
                    }
                default:
                    break
                }
            default:
                break
            }
        }

        /// Parses CSI numeric parameters split on `;`. Empty or non-numeric fields become 0. Each field
        /// is capped before caller arithmetic so huge cursor parameters cannot overflow `row + value` or
        /// `col + value`; values above the address caps are meaningless after clamping anyway.
        /// `maxCursorParameter` is one greater than the zero-based address cap because absolute
        /// positions are 1-based before `H`/`G`/`d` subtract 1.
        private func csiParams(_ params: String) -> [Int] {
            if params.isEmpty { return [0] }
            return params.split(separator: ";", omittingEmptySubsequences: false).map { field in
                guard let first = field.first, first != "?", first != ">", first != "=" else { return 0 }
                guard let value = Int(field) else { return 0 }
                return Swift.max(0, Swift.min(value, Self.maxCursorParameter))
            }
        }

        /// The first parameter as a positive count (default/zero -> 1), for the single-argument cursor
        /// moves where `ESC[A` == `ESC[1A`.
        private func firstParam(_ params: String) -> Int {
            max(1, csiParams(params).first ?? 1)
        }

        private func clampCol(_ value: Int) -> Int {
            max(0, min(value, Self.maxCols))
        }

        private mutating func moveRow(by delta: Int) {
            setRow(row + delta)
        }

        private mutating func setRow(_ target: Int) {
            let clamped = max(0, min(target, Self.maxRows))
            while lines.count <= clamped { lines.append([]) }
            row = clamped
        }

        private mutating func setCursor(row targetRow: Int, col targetCol: Int) {
            setRow(targetRow)
            col = clampCol(targetCol)
        }

        private mutating func saveCursor() {
            savedCursor = (row, col)
        }

        private mutating func restoreCursor() {
            guard let savedCursor else { return }
            setCursor(row: savedCursor.row, col: savedCursor.col)
        }

        func text() -> String {
            lines.map { String($0) }.joined(separator: "\n")
        }
    }
}
