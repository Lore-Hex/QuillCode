extension TerminalScreenBuffer {
    mutating func ensureColumn(_ target: Int) {
        let clamped = Swift.max(0, Swift.min(target, Self.maxCols))
        while lines[row].count <= clamped { lines[row].append(.blank) }
    }

    mutating func insertCharacters(count requestedCount: Int) {
        let count = boundedCharacterMutationCount(requestedCount)
        guard count > 0 else { return }

        ensureColumn(col)
        clearContinuationBoundary(at: col)
        let blanks = Array(repeating: TerminalScreenCell.blank(style: currentStyle), count: count)
        lines[row].insert(contentsOf: blanks, at: col)
        trimCurrentLineToScreenWidth()
    }

    mutating func deleteCharacters(count requestedCount: Int) {
        let count = boundedCharacterMutationCount(requestedCount)
        guard count > 0, col < lines[row].count else { return }

        clearContinuationBoundary(at: col)
        let end = Swift.min(lines[row].count, col + count)
        if end < lines[row].count {
            clearContinuationBoundary(at: end)
        }
        lines[row].removeSubrange(col..<end)
        lines[row].append(contentsOf: Array(repeating: .blank(style: currentStyle), count: end - col))
        trimCurrentLineToScreenWidth()
    }

    mutating func eraseCharacters(count requestedCount: Int) {
        let count = boundedCharacterMutationCount(requestedCount)
        guard count > 0 else { return }

        let end = Swift.min(Self.maxCols + 1, col + count)
        ensureColumn(end - 1)

        for targetCol in col..<end {
            clearCellCluster(at: targetCol)
            lines[row][targetCol] = .blank(style: currentStyle)
        }
    }

    mutating func repeatPreviousCharacter(count requestedCount: Int) {
        let count = boundedCharacterMutationCount(requestedCount)
        guard count > 0, let character = previousGraphicCharacter() else { return }

        for _ in 0..<count {
            put(character)
        }
    }

    private func boundedCharacterMutationCount(_ requestedCount: Int) -> Int {
        Swift.max(0, Swift.min(requestedCount, Self.maxCols - col + 1))
    }

    private func previousGraphicCharacter() -> Character? {
        guard col > 0 else { return nil }

        var previousCol = Swift.min(col - 1, lines[row].count - 1)
        if previousCol < 0 { return nil }
        if lines[row][previousCol].isContinuation {
            previousCol -= 1
        }
        guard previousCol >= 0, previousCol < lines[row].count else { return nil }

        let text = lines[row][previousCol].text
        guard !text.isEmpty, let character = text.first, String(character) == text else { return nil }
        return character
    }

    private mutating func trimCurrentLineToScreenWidth() {
        guard lines[row].count > Self.maxCols + 1 else { return }
        if Self.maxCols + 1 < lines[row].count {
            clearCellCluster(at: Self.maxCols)
        }
        lines[row].removeSubrange((Self.maxCols + 1)..<lines[row].count)
    }

    private mutating func clearContinuationBoundary(at column: Int) {
        guard column >= 0, column < lines[row].count, lines[row][column].isContinuation else { return }
        clearCellCluster(at: column)
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
