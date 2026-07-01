enum TerminalScreenScrollDirection {
    case up
    case down
}

enum TerminalScreenLineMutation {
    case insert
    case delete
}

extension TerminalScreenBuffer {
    func boundedMutationCount(_ requestedCount: Int, in bounds: (top: Int, bottom: Int)) -> Int {
        Swift.min(Swift.max(0, requestedCount), bounds.bottom - bounds.top + 1)
    }
}
