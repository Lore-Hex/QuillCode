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
    static let fallbackViewportRows = 24
    static let fallbackViewportCols = 80
    static let tabStopInterval = 8
    static let defaultTabStops = Set(stride(from: tabStopInterval, through: maxCols, by: tabStopInterval))

    let ambiguousWidthPolicy: TerminalOutputAmbiguousWidthPolicy
    var lines: [[TerminalScreenCell]] = [[]]
    var row = 0
    var col = 0
    var currentStyle = TerminalTextStyle.plain
    var savedCursor: CursorSnapshot?
    var scrollRegion: (top: Int, bottom: Int)?
    var originMode = false
    var savedMainBuffer: BufferSnapshot?
    var mouseModeState = TerminalMouseModeState()
    var tabStops = Self.defaultTabStops

    struct BufferSnapshot {
        var lines: [[TerminalScreenCell]]
        var row: Int
        var col: Int
        var currentStyle: TerminalTextStyle
        var savedCursor: CursorSnapshot?
        var scrollRegion: (top: Int, bottom: Int)?
        var originMode: Bool
    }

    struct CursorSnapshot {
        var row: Int
        var col: Int
        var style: TerminalTextStyle
    }

    init(ambiguousWidthPolicy: TerminalOutputAmbiguousWidthPolicy = .narrow) {
        self.ambiguousWidthPolicy = ambiguousWidthPolicy
    }

    mutating func feed(_ raw: String) {
        let scalars = Array(raw.unicodeScalars)
        let graphemeStarts = TerminalScreenGraphemeClusters.indexed(in: raw, scalarCount: scalars.count)
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if scalar.value == 0x09 {
                horizontalTab(count: 1)
                i += 1
                continue
            }

            switch scalar {
            case "\u{1B}":  // ESC: start of an escape sequence
                i = handleEscape(scalars, from: i)
            case "\u{9B}":  // C1 CSI: single-scalar Control Sequence Introducer
                i = handleCSI(scalars, paramsStart: i + 1)
            case "\u{84}":  // C1 IND: index
                lineFeed()
                i += 1
            case "\u{85}":  // C1 NEL: next line
                lineFeed()
                col = 0
                i += 1
            case "\u{8D}":  // C1 RI: reverse index
                reverseIndex()
                i += 1
            case "\u{9D}":  // C1 OSC: Operating System Command
                i = consumeStringControl(scalars, bodyStart: i + 1)
            case "\u{90}", "\u{98}", "\u{9E}", "\u{9F}":  // C1 DCS/SOS/PM/APC string controls
                i = consumeStringControl(scalars, bodyStart: i + 1)
            case "\r":  // carriage return: back to column 0, overwrite from here
                col = 0
                i += 1
            case "\n", "\u{0B}", "\u{0C}":  // line feed, vertical tab, form feed
                lineFeed()
                col = 0
                i += 1
            case "\u{08}":  // backspace
                if col > 0 { col -= 1 }
                i += 1
            case let control where control.value < 0x20 || control.value == 0x7F:
                i += 1
            default:
                if let grapheme = graphemeStarts[i] {
                    put(grapheme.character)
                    i += grapheme.scalarCount
                } else {
                    put(Character(scalar))
                    i += 1
                }
            }
        }
    }

    mutating func put(_ character: Character) {
        let width = TerminalScreenCellWidth.width(of: character, ambiguousPolicy: ambiguousWidthPolicy)
        guard width > 0 else {
            appendCombiningCharacter(character)
            return
        }

        ensureColumn(col)
        clearCellCluster(at: col)
        lines[row][col] = .content(character, style: currentStyle)
        if width == 2, col < Self.maxCols {
            ensureColumn(col + 1)
            clearCellCluster(at: col + 1)
            lines[row][col + 1] = .continuation(style: currentStyle)
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
            return consumeStringControl(scalars, bodyStart: next + 1)
        case "P", "X", "^", "_":  // DCS/SOS/PM/APC: string controls terminated by ST
            return consumeStringControl(scalars, bodyStart: next + 1)
        case "#":
            guard next + 1 < scalars.count else { return scalars.count }
            if scalars[next + 1] == "8" {
                screenAlignmentPattern()
            }
            return next + 2
        case "7":
            saveCursor()
            return next + 1
        case "8":
            restoreCursor()
            return next + 1
        case "H":  // HTS: set a horizontal tab stop at the current column
            setHorizontalTabStop()
            return next + 1
        case "D":  // IND: index
            lineFeed()
            return next + 1
        case "E":  // NEL: next line
            lineFeed()
            col = 0
            return next + 1
        case "M":  // RI: reverse index
            reverseIndex()
            return next + 1
        case "c":  // RIS: reset to initial terminal state
            reset()
            return next + 1
        default:
            return consumePlainEscape(scalars, next: next)
        }
    }

    mutating func reset() {
        lines = [[]]
        row = 0
        col = 0
        currentStyle = .plain
        savedCursor = nil
        scrollRegion = nil
        originMode = false
        savedMainBuffer = nil
        mouseModeState = TerminalMouseModeState()
        tabStops = Self.defaultTabStops
    }

    func consumeStringControl(_ scalars: [Unicode.Scalar], bodyStart: Int) -> Int {
        var i = bodyStart
        while i < scalars.count {
            if scalars[i] == "\u{07}" { return i + 1 }
            if scalars[i] == "\u{9C}" { return i + 1 }
            if scalars[i] == "\u{1B}", i + 1 < scalars.count, scalars[i + 1] == "\\" { return i + 2 }
            i += 1
        }
        return scalars.count
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
        styledFrame().text
    }

    func styledFrame() -> TerminalRenderedFrame {
        var frame = TerminalScreenStyledText.render(lines)
        frame.mouseReporting = mouseReporting
        return frame
    }
}
