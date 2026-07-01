extension TerminalScreenBuffer {
    mutating func insertLines(count: Int) {
        mutateLines(count: count, mutation: .insert)
    }

    mutating func deleteLines(count: Int) {
        mutateLines(count: count, mutation: .delete)
    }

    mutating func mutateLines(count requestedCount: Int, mutation: TerminalScreenLineMutation) {
        guard let bounds = mutationBounds() else { return }
        let count = boundedMutationCount(requestedCount, in: bounds)
        guard count > 0 else { return }

        ensureRow(bounds.bottom)
        for _ in 0..<count {
            mutateLine(in: bounds, mutation: mutation)
        }
    }

    mutating func mutationBounds() -> (top: Int, bottom: Int)? {
        var bounds = scrollBounds()
        bounds.top = Swift.max(bounds.top, row)
        return bounds.top <= bounds.bottom ? bounds : nil
    }

    mutating func mutateLine(
        in bounds: (top: Int, bottom: Int),
        mutation: TerminalScreenLineMutation
    ) {
        switch mutation {
        case .insert:
            lines.insert([], at: bounds.top)
            lines.remove(at: bounds.bottom + 1)
        case .delete:
            lines.remove(at: bounds.top)
            lines.insert([], at: bounds.bottom)
        }
    }
}
