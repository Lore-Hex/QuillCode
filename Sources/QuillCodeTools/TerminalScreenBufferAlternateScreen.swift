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
        savedCursor = nil
        scrollRegion = nil
    }

    mutating func leaveAlternateScreen() {
        guard let mainBuffer = savedMainBuffer else { return }
        let alternateFrame = text().trimmingCharacters(in: .newlines)
        restore(mainBuffer)
        savedMainBuffer = nil
        appendAlternateFrame(alternateFrame)
    }

    func snapshot() -> BufferSnapshot {
        BufferSnapshot(
            lines: lines,
            row: row,
            col: col,
            savedCursor: savedCursor,
            scrollRegion: scrollRegion
        )
    }

    mutating func restore(_ snapshot: BufferSnapshot) {
        lines = snapshot.lines
        row = snapshot.row
        col = snapshot.col
        savedCursor = snapshot.savedCursor
        scrollRegion = snapshot.scrollRegion
    }

    mutating func appendAlternateFrame(_ frame: String) {
        guard !frame.isEmpty else { return }
        setCursor(row: Swift.max(0, lines.count - 1), col: lines.last?.count ?? 0)
        if !(lines.last?.isEmpty ?? true) { lineFeed(); col = 0 }
        for scalar in frame.unicodeScalars {
            if scalar == "\n" {
                lineFeed()
                col = 0
            } else {
                put(Character(scalar))
            }
        }
    }
}
