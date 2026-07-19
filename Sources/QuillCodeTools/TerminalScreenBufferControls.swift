extension TerminalScreenBuffer {
    mutating func applyCSI(final: Unicode.Scalar, params: String) {
        switch final {
        case "m":
            applySGR(params)
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
        case "I":  // CHT: cursor forward to following tab stop
            horizontalTab(count: firstParam(params))
        case "Z":  // CBT: cursor backward to previous tab stop
            backwardHorizontalTab(count: firstParam(params))
        case "g":  // TBC: clear tab stop
            clearHorizontalTabStop(params)
        case "d":  // VPA: cursor to absolute row (1-based)
            setRow(firstParam(params) - 1)
        case "s":
            saveCursor()
        case "u":
            restoreCursor()
        case "r":  // DECSTBM: set/reset scroll region
            setScrollRegion(params)
        case "S":  // SU: scroll up
            scrollUp(count: firstParam(params))
        case "T":  // SD: scroll down
            scrollDown(count: firstParam(params))
        case "L":  // IL: insert lines
            insertLines(count: firstParam(params))
        case "M":  // DL: delete lines
            deleteLines(count: firstParam(params))
        case "@":  // ICH: insert blank characters at cursor
            insertCharacters(count: firstParam(params))
        case "P":  // DCH: delete characters at cursor
            deleteCharacters(count: firstParam(params))
        case "X":  // ECH: erase characters at cursor without shifting the suffix
            eraseCharacters(count: firstParam(params))
        case "b":  // REP: repeat the preceding graphic character
            repeatPreviousCharacter(count: firstParam(params))
        case "K":
            eraseLine(params)
        case "J":
            eraseDisplay(params)
        case "h", "l":
            applyPrivateMode(final: final, params: params)
        default:
            break
        }
    }

    /// Parses CSI numeric parameters split on `;`. Empty or non-numeric fields become 0. Each field
    /// is capped before caller arithmetic so huge cursor parameters cannot overflow `row + value` or
    /// `col + value`; values above the address caps are meaningless after clamping anyway.
    /// `maxCursorParameter` is one greater than the zero-based address cap because absolute
    /// positions are 1-based before `H`/`G`/`d` subtract 1.
    func csiParams(_ params: String) -> [Int] {
        if params.isEmpty { return [0] }
        return params.split(separator: ";", omittingEmptySubsequences: false).map { field in
            guard let first = field.first, first != "?", first != ">", first != "=" else { return 0 }
            guard let value = Int(field) else { return 0 }
            return Swift.max(0, Swift.min(value, Self.maxCursorParameter))
        }
    }

    /// The first parameter as a positive count (default/zero -> 1), for the single-argument cursor
    /// moves where `ESC[A` == `ESC[1A`.
    func firstParam(_ params: String) -> Int {
        max(1, csiParams(params).first ?? 1)
    }

    func clampCol(_ value: Int) -> Int {
        max(0, min(value, Self.maxCols))
    }

    mutating func lineFeed() {
        if let region = boundedScrollRegion(), row == region.bottom {
            scrollUp(count: 1, in: region)
        } else {
            moveRow(by: 1)
        }
    }

    mutating func reverseIndex() {
        if let region = boundedScrollRegion(), row == region.top {
            scrollDown(count: 1, in: region)
        } else {
            moveRow(by: -1)
        }
    }

    mutating func moveRow(by delta: Int) {
        setRow(row + delta)
    }

    mutating func setRow(_ target: Int) {
        let clamped = max(0, min(target, Self.maxRows))
        while lines.count <= clamped { lines.append([]) }
        row = clamped
    }

    mutating func setCursor(row targetRow: Int, col targetCol: Int) {
        setRow(targetRow)
        col = clampCol(targetCol)
    }

    mutating func saveCursor() {
        savedCursor = CursorSnapshot(row: row, col: col, style: currentStyle)
    }

    mutating func restoreCursor() {
        guard let savedCursor else { return }
        setCursor(row: savedCursor.row, col: savedCursor.col)
        currentStyle = savedCursor.style
    }

    mutating func ensureRow(_ target: Int) {
        let clamped = Swift.max(0, Swift.min(target, Self.maxRows))
        while lines.count <= clamped { lines.append([]) }
    }

    mutating func horizontalTab(count requestedCount: Int) {
        let count = boundedTabMovementCount(requestedCount)
        guard count > 0 else { return }

        for _ in 0..<count {
            col = nextTabStop(after: col)
        }
    }

    mutating func backwardHorizontalTab(count requestedCount: Int) {
        let count = boundedTabMovementCount(requestedCount)
        guard count > 0 else { return }

        for _ in 0..<count {
            col = previousTabStop(before: col)
        }
    }

    mutating func setHorizontalTabStop() {
        tabStops.insert(clampCol(col))
    }

    mutating func clearHorizontalTabStop(_ params: String) {
        let parts = csiParams(params)
        switch parts.first ?? 0 {
        case 0:
            tabStops.remove(clampCol(col))
        case 3:
            tabStops.removeAll()
        default:
            break
        }
    }

    func nextTabStop(after column: Int) -> Int {
        tabStops.reduce(Self.maxCols) { next, stop in
            stop > column && stop < next ? stop : next
        }
    }

    func previousTabStop(before column: Int) -> Int {
        tabStops.reduce(0) { previous, stop in
            stop < column && stop > previous ? stop : previous
        }
    }

    private func boundedTabMovementCount(_ requestedCount: Int) -> Int {
        Swift.max(0, Swift.min(requestedCount, tabStops.count + 2))
    }
}
