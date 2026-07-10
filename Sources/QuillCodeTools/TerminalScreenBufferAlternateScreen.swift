import Foundation

extension TerminalScreenBuffer {
    mutating func applyPrivateMode(final: Unicode.Scalar, params: String) {
        let modes = params.split(separator: ";", omittingEmptySubsequences: false)
        guard modes.contains(where: { ["?47", "?1047", "?1049"].contains(String($0)) }) else { return }
        if final == "h" {
            enterAlternateScreen()
        } else {
            leaveAlternateScreen()
        }
    }

    mutating func enterAlternateScreen() {
        if savedMainBuffer == nil { savedMainBuffer = snapshot() }
        lines = [[]]
        row = 0
        col = 0
        currentStyle = .plain
        savedCursor = nil
        scrollRegion = nil
    }

    mutating func leaveAlternateScreen() {
        guard let mainBuffer = savedMainBuffer else { return }
        let alternateLines = trimmedAlternateLines(lines)
        restore(mainBuffer)
        savedMainBuffer = nil
        appendAlternateFrame(alternateLines)
    }

    func snapshot() -> BufferSnapshot {
        BufferSnapshot(
            lines: lines,
            row: row,
            col: col,
            currentStyle: currentStyle,
            savedCursor: savedCursor,
            scrollRegion: scrollRegion
        )
    }

    mutating func restore(_ snapshot: BufferSnapshot) {
        lines = snapshot.lines
        row = snapshot.row
        col = snapshot.col
        currentStyle = snapshot.currentStyle
        savedCursor = snapshot.savedCursor
        scrollRegion = snapshot.scrollRegion
    }

    mutating func appendAlternateFrame(_ frameLines: [[TerminalScreenCell]]) {
        guard !frameLines.isEmpty else { return }
        setCursor(row: Swift.max(0, lines.count - 1), col: lines.last?.count ?? 0)
        if !(lines.last?.isEmpty ?? true) { lineFeed(); col = 0 }
        for (lineIndex, line) in frameLines.enumerated() {
            if lineIndex > 0 {
                lineFeed()
                col = 0
            }
            lines[row] = line
            col = clampCol(line.count)
        }
    }

    func trimmedAlternateLines(_ source: [[TerminalScreenCell]]) -> [[TerminalScreenCell]] {
        guard let first = source.firstIndex(where: { !$0.isEmpty }),
              let last = source.lastIndex(where: { !$0.isEmpty }) else {
            return []
        }
        return Array(source[first...last])
    }
}
