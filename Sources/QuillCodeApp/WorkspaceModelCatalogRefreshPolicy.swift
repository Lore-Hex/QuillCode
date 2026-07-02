import Foundation
import QuillCodeCore

public struct WorkspaceModelCatalogRefreshPolicy: Sendable, Hashable {
    public var staleAfter: TimeInterval
    public var retryAfterFailure: TimeInterval

    public init(
        staleAfter: TimeInterval = 60 * 60,
        retryAfterFailure: TimeInterval = 5 * 60
    ) {
        self.staleAfter = staleAfter
        self.retryAfterFailure = retryAfterFailure
    }

    public func shouldRefresh(
        status: ModelCatalogStatus,
        hasTrustedRouterAPIKey: Bool,
        now: Date = Date()
    ) -> Bool {
        guard hasTrustedRouterAPIKey else { return false }
        switch status.source {
        case .bundled:
            return true
        case .liveTrustedRouter:
            return isStale(status.fetchedAt, now: now, threshold: staleAfter)
        case .fallbackAfterFailure:
            return isStale(status.fetchedAt, now: now, threshold: retryAfterFailure)
        }
    }

    private func isStale(_ fetchedAt: Date?, now: Date, threshold: TimeInterval) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= normalizedThreshold(threshold)
    }

    private func normalizedThreshold(_ threshold: TimeInterval) -> TimeInterval {
        guard threshold.isFinite else { return 0 }
        return max(0, threshold)
    }
}
