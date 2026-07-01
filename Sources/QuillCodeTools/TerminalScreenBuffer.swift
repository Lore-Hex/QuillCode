import Foundation

/// Internal screen buffer used by `TerminalOutputRenderer`.
/// It intentionally stays independent of UI state: every render rebuilds the final visible frame from
/// raw terminal bytes so persisted transcripts keep their original output.
struct TerminalScreenBuffer {
    /// Hard caps on how far the cursor can move, and therefore how much padding it can force into
    /// the backing buffer. Normal printed output can still create long lines; these caps only bound
    /// cursor addressing from garbled or hostile escape sequences.
    static let maxRows = 1_000
    static let maxCols = 1_000
    static let maxCursorParameter = 1_001

    var lines: [[TerminalScreenCell]] = [[]]
    var row = 0
    var col = 0
    var savedCursor: (row: Int, col: Int)?
    var scrollRegion: (top: Int, bottom: Int)?
    var savedMainBuffer: BufferSnapshot?

    struct BufferSnapshot {
        var lines: [[TerminalScreenCell]]
        var row: Int
        var col: Int
        var savedCursor: (row: Int, col: Int)?
        var scrollRegion: (top: Int, bottom: Int)?
    }

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
                lineFeed()
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

    mutating func put(_ character: Character) {
        let width = TerminalScreenCellWidth.width(of: character)
        guard width > 0 else {
            appendCombiningCharacter(character)
            return
        }

        ensureColumn(col)
        clearCellCluster(at: col)
        lines[row][col] = .content(character)
        if width == 2, col < Self.maxCols {
            ensureColumn(col + 1)
            clearCellCluster(at: col + 1)
            lines[row][col + 1] = .continuation
        }
        col = clampCol(col + width)
    }

    /// Handles an escape sequence beginning at `start` (where `scalars[start] == ESC`). Applies the
    /// effects we model and returns the index of the first scalar after the sequence. A sequence
    /// that is incomplete at the end of the buffer is dropped; it will arrive complete on the next
    /// render of the growing buffer.
    mutating func handleEscape(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
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
        case "M":  // RI: reverse index
            reverseIndex()
            return next + 1
        default:
            return consumePlainEscape(scalars, next: next)
        }
    }

    /// Parses a CSI sequence `ESC [ <params> <final>` and applies the ones we model. `paramsStart`
    /// points just past the `[`. Returns the index after the final byte, or `scalars.count` if the
    /// sequence is incomplete.
    mutating func handleCSI(_ scalars: [Unicode.Scalar], paramsStart: Int) -> Int {
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

    func consumePlainEscape(_ scalars: [Unicode.Scalar], next: Int) -> Int {
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
        // Plain two-character escape (e.g. ESC =, ESC >): strip both bytes.
        return next + 1
    }

    func text() -> String {
        lines.map(TerminalScreenLineText.render).joined(separator: "\n")
    }
}
