import Foundation
import QuillCodeCore

public struct WorkspaceTrustedRouterCreditsRefreshPolicy: Sendable, Hashable {
    public var staleAfter: TimeInterval
    public var retryAfterFailure: TimeInterval

    public init(
        staleAfter: TimeInterval = 5 * 60,
        retryAfterFailure: TimeInterval = 60
    ) {
        self.staleAfter = Self.normalized(staleAfter)
        self.retryAfterFailure = Self.normalized(retryAfterFailure)
    }

    public func shouldRefresh(
        state: TrustedRouterCreditsState,
        hasTrustedRouterAPIKey: Bool,
        now: Date = Date()
    ) -> Bool {
        guard hasTrustedRouterAPIKey else { return false }
        switch state.phase {
        case .unavailable:
            return true
        case .refreshing:
            return false
        case .current:
            guard let fetchedAt = state.snapshot?.fetchedAt else { return true }
            return now.timeIntervalSince(fetchedAt) >= staleAfter
        case .stale, .failed:
            guard let lastAttemptAt = state.lastAttemptAt else { return true }
            return now.timeIntervalSince(lastAttemptAt) >= retryAfterFailure
        }
    }

    private static func normalized(_ interval: TimeInterval) -> TimeInterval {
        interval.isFinite ? max(0, interval) : 0
    }
}
