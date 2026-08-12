struct AgentCorrectiveTurnBudget: Sendable, Equatable {
    /// Repeated misses for one correction are still stopped quickly.
    static let limit = 3
    /// Distinct bounded gates may legitimately hand work to one another before a tool executes.
    /// Keep a larger aggregate cap so those phase transitions cannot make the run unbounded.
    static let aggregateLimit = 8

    private(set) var consecutiveTurns = 0
    private(set) var aggregateTurns = 0
    private var activeCorrectionID: String?

    mutating func beginCorrectiveTurn(correctionID: String) -> Bool {
        if activeCorrectionID != correctionID {
            activeCorrectionID = correctionID
            consecutiveTurns = 0
        }
        guard consecutiveTurns < Self.limit,
              aggregateTurns < Self.aggregateLimit
        else { return false }
        consecutiveTurns += 1
        aggregateTurns += 1
        return true
    }

    mutating func recordExecutedTool() {
        reset()
    }

    mutating func recordRoutePromotion() {
        reset()
    }

    private mutating func reset() {
        consecutiveTurns = 0
        aggregateTurns = 0
        activeCorrectionID = nil
    }
}
