extension TerminalScreenBuffer {
    mutating func scrollUp(count: Int) {
        scroll(count: count, in: scrollBounds(), direction: .up)
    }

    mutating func scrollUp(count: Int, in bounds: (top: Int, bottom: Int)) {
        scroll(count: count, in: bounds, direction: .up)
    }

    mutating func scrollDown(count: Int) {
        scroll(count: count, in: scrollBounds(), direction: .down)
    }

    mutating func scrollDown(count: Int, in bounds: (top: Int, bottom: Int)) {
        scroll(count: count, in: bounds, direction: .down)
    }

    mutating func scroll(
        count requestedCount: Int,
        in bounds: (top: Int, bottom: Int),
        direction: TerminalScreenScrollDirection
    ) {
        let count = boundedMutationCount(requestedCount, in: bounds)
        guard count > 0 else { return }

        ensureRow(bounds.bottom)
        for _ in 0..<count {
            shiftLine(in: bounds, direction: direction)
        }
        row = Swift.min(Swift.max(row, bounds.top), bounds.bottom)
    }

    mutating func shiftLine(
        in bounds: (top: Int, bottom: Int),
        direction: TerminalScreenScrollDirection
    ) {
        switch direction {
        case .up:
            lines.remove(at: bounds.top)
            lines.insert([], at: bounds.bottom)
        case .down:
            lines.remove(at: bounds.bottom)
            lines.insert([], at: bounds.top)
        }
    }
}
