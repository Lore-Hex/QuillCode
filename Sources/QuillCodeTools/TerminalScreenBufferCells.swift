extension TerminalScreenBuffer {
    mutating func ensureColumn(_ target: Int) {
        let clamped = Swift.max(0, Swift.min(target, Self.maxCols))
        while lines[row].count <= clamped { lines[row].append(.blank) }
    }

    mutating func clearCellCluster(at column: Int) {
        guard column >= 0, column < lines[row].count else { return }
        if lines[row][column].isContinuation {
            lines[row][column] = .blank
            if column > 0 { lines[row][column - 1] = .blank }
            return
        }

        lines[row][column] = .blank
        if column + 1 < lines[row].count, lines[row][column + 1].isContinuation {
            lines[row][column + 1] = .blank
        }
    }

    mutating func appendCombiningCharacter(_ character: Character) {
        let target = combiningTargetColumn()
        ensureColumn(target)
        if lines[row][target].isBlank {
            lines[row][target] = .content(character, style: currentStyle)
        } else if !lines[row][target].isContinuation {
            lines[row][target].text += String(character)
        }
    }

    func combiningTargetColumn() -> Int {
        guard col > 0 else { return col }
        let previous = col - 1
        guard previous < lines[row].count else { return previous }
        if lines[row][previous].isContinuation, previous > 0 {
            return previous - 1
        }
        return previous
    }
}
