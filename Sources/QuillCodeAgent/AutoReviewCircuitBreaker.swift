import QuillCodeCore

struct AutoReviewCircuitBreaker: Sendable {
    static let consecutiveDenialLimit = 3
    static let rollingReviewWindow = 50
    static let denialLimitInWindow = 10

    private(set) var consecutiveDenials = 0
    private(set) var recentOutcomes: [ApprovalReviewOutcome] = []

    mutating func record(_ outcome: ApprovalReviewOutcome) -> AutoReviewCircuitBreakReason? {
        recentOutcomes.append(outcome)
        if recentOutcomes.count > Self.rollingReviewWindow {
            recentOutcomes.removeFirst(recentOutcomes.count - Self.rollingReviewWindow)
        }

        if outcome.countsAsDenial {
            consecutiveDenials += 1
        } else {
            consecutiveDenials = 0
        }

        if consecutiveDenials >= Self.consecutiveDenialLimit {
            return .consecutiveDenials(count: consecutiveDenials)
        }
        let denialCount = recentOutcomes.lazy.filter(\.countsAsDenial).count
        if denialCount >= Self.denialLimitInWindow {
            return .rollingDenials(count: denialCount, reviews: recentOutcomes.count)
        }
        return nil
    }
}

enum AutoReviewCircuitBreakReason: Sendable, Hashable {
    case consecutiveDenials(count: Int)
    case rollingDenials(count: Int, reviews: Int)

    var message: String {
        switch self {
        case .consecutiveDenials(let count):
            return "Auto review denied \(count) consecutive actions in this turn."
        case .rollingDenials(let count, let reviews):
            return "Auto review denied \(count) of the last \(reviews) reviewed actions in this turn."
        }
    }
}
