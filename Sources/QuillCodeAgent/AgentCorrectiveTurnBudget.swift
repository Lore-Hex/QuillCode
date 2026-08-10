struct AgentCorrectiveTurnBudget: Sendable, Equatable {
    static let limit = 3

    private(set) var consecutiveTurns = 0

    mutating func beginCorrectiveTurn() -> Bool {
        guard consecutiveTurns < Self.limit else { return false }
        consecutiveTurns += 1
        return true
    }

    mutating func recordExecutedTool() {
        consecutiveTurns = 0
    }
}
