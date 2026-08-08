import Foundation

public enum TrustedRouterCreditsWindow: String, Codable, Sendable, Hashable, CaseIterable {
    case daily
    case weekly
    case monthly
    case lifetime

    public var displayLabel: String {
        switch self {
        case .daily: "Today"
        case .weekly: "Week"
        case .monthly: "Month"
        case .lifetime: "Total"
        }
    }
}

public struct TrustedRouterCreditsWindowSnapshot: Codable, Sendable, Hashable {
    public var window: TrustedRouterCreditsWindow
    public var usage: Double
    public var limit: Double?
    public var remaining: Double?
    public var resetsAt: Date?

    public init?(
        window: TrustedRouterCreditsWindow,
        usage: Double,
        limit: Double? = nil,
        remaining: Double? = nil,
        resetsAt: Date? = nil
    ) {
        guard usage.isFinite, usage >= 0 else { return nil }
        guard limit.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
        guard remaining.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }

        self.window = window
        self.usage = usage
        self.limit = limit
        self.remaining = remaining ?? limit.map { max(0, $0 - usage) }
        self.resetsAt = resetsAt
    }

    public var usedPercent: Int? {
        guard let limit, limit > 0 else { return nil }
        return max(0, Int((usage / limit * 100).rounded()))
    }
}

public struct TrustedRouterCreditsSnapshot: Codable, Sendable, Hashable {
    public var lifetime: TrustedRouterCreditsWindowSnapshot
    public var daily: TrustedRouterCreditsWindowSnapshot
    public var weekly: TrustedRouterCreditsWindowSnapshot
    public var monthly: TrustedRouterCreditsWindowSnapshot
    public var currency: String?
    public var fetchedAt: Date
    public var budgetAlertOnly: Bool

    public init?(
        lifetime: TrustedRouterCreditsWindowSnapshot,
        daily: TrustedRouterCreditsWindowSnapshot,
        weekly: TrustedRouterCreditsWindowSnapshot,
        monthly: TrustedRouterCreditsWindowSnapshot,
        currency: String?,
        fetchedAt: Date = Date(),
        budgetAlertOnly: Bool = false
    ) {
        guard lifetime.window == .lifetime,
              daily.window == .daily,
              weekly.window == .weekly,
              monthly.window == .monthly else {
            return nil
        }
        self.lifetime = lifetime
        self.daily = daily
        self.weekly = weekly
        self.monthly = monthly
        self.currency = Self.normalizedCurrency(currency)
        self.fetchedAt = fetchedAt
        self.budgetAlertOnly = budgetAlertOnly
    }

    public var windows: [TrustedRouterCreditsWindowSnapshot] {
        [daily, weekly, monthly, lifetime]
    }

    public var primaryWindow: TrustedRouterCreditsWindowSnapshot {
        windows.first(where: { $0.limit != nil }) ?? lifetime
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
    public static let maxHistoryCount = 24

    public var phase: TrustedRouterCreditsPhase
    public var snapshot: TrustedRouterCreditsSnapshot?
    /// Most-recent-first successful TrustedRouter key-usage snapshots observed by this client.
    /// This is local observation history, not a provider-side ledger.
    public var history: [TrustedRouterCreditsSnapshot]
    public var lastAttemptAt: Date?
    public var failureMessage: String?

    public init(
        phase: TrustedRouterCreditsPhase = .unavailable,
        snapshot: TrustedRouterCreditsSnapshot? = nil,
        history: [TrustedRouterCreditsSnapshot] = [],
        lastAttemptAt: Date? = nil,
        failureMessage: String? = nil
    ) {
        self.phase = phase
        self.snapshot = snapshot
        self.history = Self.normalizedHistory(history, snapshot: snapshot)
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
            history: previous.history,
            lastAttemptAt: attemptedAt
        )
    }

    public static func current(
        _ snapshot: TrustedRouterCreditsSnapshot,
        previous: TrustedRouterCreditsState = .unavailable
    ) -> TrustedRouterCreditsState {
        TrustedRouterCreditsState(
            phase: .current,
            snapshot: snapshot,
            history: appendedHistory(snapshot, to: previous.history),
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
            history: previous.history,
            lastAttemptAt: attemptedAt,
            failureMessage: message
        )
    }

    private enum CodingKeys: String, CodingKey {
        case phase
        case snapshot
        case history
        case lastAttemptAt
        case failureMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let snapshot = try container.decodeIfPresent(TrustedRouterCreditsSnapshot.self, forKey: .snapshot)
        self.phase = try container.decodeIfPresent(TrustedRouterCreditsPhase.self, forKey: .phase) ?? .unavailable
        self.snapshot = snapshot
        self.history = Self.normalizedHistory(
            try container.decodeIfPresent([TrustedRouterCreditsSnapshot].self, forKey: .history) ?? [],
            snapshot: snapshot
        )
        self.lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        self.failureMessage = Self.normalizedFailureMessage(
            try container.decodeIfPresent(String.self, forKey: .failureMessage)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
        try container.encode(history, forKey: .history)
        try container.encodeIfPresent(lastAttemptAt, forKey: .lastAttemptAt)
        try container.encodeIfPresent(failureMessage, forKey: .failureMessage)
    }

    private static func appendedHistory(
        _ snapshot: TrustedRouterCreditsSnapshot,
        to history: [TrustedRouterCreditsSnapshot]
    ) -> [TrustedRouterCreditsSnapshot] {
        normalizedHistory([snapshot] + history, snapshot: nil)
    }

    private static func normalizedHistory(
        _ history: [TrustedRouterCreditsSnapshot],
        snapshot: TrustedRouterCreditsSnapshot?
    ) -> [TrustedRouterCreditsSnapshot] {
        var result: [TrustedRouterCreditsSnapshot] = []
        for entry in [snapshot].compactMap({ $0 }) + history {
            guard !result.contains(entry) else { continue }
            result.append(entry)
            if result.count == maxHistoryCount { break }
        }
        return result
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
