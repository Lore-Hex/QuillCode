extension TerminalScreenBuffer {
    mutating func eraseLine(_ params: String) {
        switch params {
        case "", "0":  // cursor to end of line
            eraseLineFromCursor()
        case "1":  // start of line to cursor inclusive
            blankCurrentLinePrefix()
        case "2":  // whole line
            lines[row].removeAll()
        default:
            break
        }
    }

    mutating func eraseDisplay(_ params: String) {
        switch params {
        case "2", "3":  // whole screen (+ scrollback) -> reset
            lines = [[]]
            row = 0
            col = 0
        case "", "0":  // cursor to end of screen
            eraseLineFromCursor()
            if row + 1 < lines.count { lines.removeSubrange((row + 1)..<lines.count) }
        case "1":  // start of screen to cursor inclusive
            for r in 0..<row where r < lines.count { lines[r].removeAll() }
            blankCurrentLinePrefix()
        default:
            break
        }
    }

    mutating func blankCurrentLinePrefix() {
        guard !lines[row].isEmpty else { return }
        let end = min(col, lines[row].count - 1)
        for c in 0...end { clearCellCluster(at: c) }
    }

    mutating func eraseLineFromCursor() {
        guard col < lines[row].count else { return }
        if lines[row][col].isContinuation, col > 0 {
            lines[row][col - 1] = .blank
        }
        lines[row].removeSubrange(col..<lines[row].count)
    }
}
