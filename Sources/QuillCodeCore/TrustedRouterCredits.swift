import Foundation

public struct TrustedRouterCreditsSnapshot: Codable, Sendable, Hashable {
    public var balance: Double
    public var currency: String?
    public var fetchedAt: Date

    public init?(balance: Double, currency: String?, fetchedAt: Date = Date()) {
        guard balance.isFinite else { return nil }
        self.balance = balance
        self.currency = Self.normalizedCurrency(currency)
        self.fetchedAt = fetchedAt
    }

    private static func normalizedCurrency(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(12))
    }
}

public enum TrustedRouterCreditsPhase: String, Codable, Sendable, Hashable {
    case unavailable
    case refreshing
    case current
    case stale
    case failed
}

public struct TrustedRouterCreditsState: Codable, Sendable, Hashable {
    public var phase: TrustedRouterCreditsPhase
    public var snapshot: TrustedRouterCreditsSnapshot?
    public var lastAttemptAt: Date?
    public var failureMessage: String?

    public init(
        phase: TrustedRouterCreditsPhase = .unavailable,
        snapshot: TrustedRouterCreditsSnapshot? = nil,
        lastAttemptAt: Date? = nil,
        failureMessage: String? = nil
    ) {
        self.phase = phase
        self.snapshot = snapshot
        self.lastAttemptAt = lastAttemptAt
        self.failureMessage = Self.normalizedFailureMessage(failureMessage)
    }

    public static let unavailable = TrustedRouterCreditsState()

    public static func refreshing(
        previous: TrustedRouterCreditsState,
        attemptedAt: Date = Date()
    ) -> TrustedRouterCreditsState {
        TrustedRouterCreditsState(
            phase: .refreshing,
            snapshot: previous.snapshot,
            lastAttemptAt: attemptedAt
        )
    }

    public static func current(_ snapshot: TrustedRouterCreditsSnapshot) -> TrustedRouterCreditsState {
        TrustedRouterCreditsState(
            phase: .current,
            snapshot: snapshot,
            lastAttemptAt: snapshot.fetchedAt
        )
    }

    public static func failed(
        previous: TrustedRouterCreditsState,
        attemptedAt: Date = Date(),
        message: String
    ) -> TrustedRouterCreditsState {
        TrustedRouterCreditsState(
            phase: previous.snapshot == nil ? .failed : .stale,
            snapshot: previous.snapshot,
            lastAttemptAt: attemptedAt,
            failureMessage: message
        )
    }

    private static func normalizedFailureMessage(_ value: String?) -> String? {
        let normalized = value?
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(240))
    }
}

public enum TrustedRouterCreditsRefreshResult: Sendable, Hashable {
    case unavailable
    case success(TrustedRouterCreditsSnapshot)
    case failure(attemptedAt: Date, message: String)
}
