import Foundation

public enum ModelCatalogSource: String, Codable, Sendable, Hashable {
    case bundled
    case liveTrustedRouter
    case publicTrustedRouter
    case fallbackAfterFailure
}

public struct ModelCatalogStatus: Codable, Sendable, Hashable {
    public var source: ModelCatalogSource
    public var fetchedAt: Date?
    public var failureMessage: String?

    public init(
        source: ModelCatalogSource = .bundled,
        fetchedAt: Date? = nil,
        failureMessage: String? = nil
    ) {
        self.source = source
        self.fetchedAt = fetchedAt
        self.failureMessage = Self.normalizedFailureMessage(failureMessage)
    }

    public static let bundled = ModelCatalogStatus()

    public static func liveTrustedRouter(fetchedAt: Date = Date()) -> ModelCatalogStatus {
        ModelCatalogStatus(source: .liveTrustedRouter, fetchedAt: fetchedAt)
    }

    public static func publicTrustedRouter(
        fetchedAt: Date = Date(),
        note: String? = nil
    ) -> ModelCatalogStatus {
        ModelCatalogStatus(source: .publicTrustedRouter, fetchedAt: fetchedAt, failureMessage: note)
    }

    public static func fallbackAfterFailure(
        _ failureMessage: String?,
        fetchedAt: Date = Date()
    ) -> ModelCatalogStatus {
        ModelCatalogStatus(
            source: .fallbackAfterFailure,
            fetchedAt: fetchedAt,
            failureMessage: failureMessage
        )
    }

    public func statusLabel(now: Date = Date(), staleAfter: TimeInterval = 60 * 60) -> String {
        switch source {
        case .bundled:
            return "Bundled catalog"
        case .liveTrustedRouter:
            return "Live TrustedRouter catalog · \(freshnessLabel(now: now, staleAfter: staleAfter))"
        case .publicTrustedRouter:
            return "Public TrustedRouter catalog · \(freshnessLabel(now: now, staleAfter: staleAfter))"
        case .fallbackAfterFailure:
            return "Bundled fallback · refresh failed"
        }
    }

    public func detailLabel(now: Date = Date(), staleAfter: TimeInterval = 60 * 60) -> String? {
        switch source {
        case .bundled:
            return "Using QuillCode's built-in recommended models until TrustedRouter sign-in refreshes the catalog."
        case .liveTrustedRouter:
            return "Provider, pricing, modality, and health metadata last refreshed \(freshnessLabel(now: now, staleAfter: staleAfter))."
        case .publicTrustedRouter:
            let suffix = failureMessage.map { " \($0)" } ?? ""
            return "Loaded the public TrustedRouter model catalog \(freshnessLabel(now: now, staleAfter: staleAfter)).\(suffix)"
        case .fallbackAfterFailure:
            let suffix = failureMessage.map { ": \($0)" } ?? "."
            return "The latest TrustedRouter model refresh failed\(suffix)"
        }
    }

    private func freshnessLabel(now: Date, staleAfter: TimeInterval) -> String {
        guard let fetchedAt else { return "unknown age" }
        let elapsed = max(0, now.timeIntervalSince(fetchedAt))
        guard elapsed >= 60 else { return "just now" }
        let age = Self.ageLabel(elapsed)
        return elapsed > staleAfter ? "stale \(age) ago" : "\(age) ago"
    }

    /// Formats an elapsed interval as an age. The sole caller (`freshnessLabel`) has already handled
    /// sub-minute intervals with its own "just now", so this is only ever called with `interval >= 60`.
    private static func ageLabel(_ interval: TimeInterval) -> String {
        switch interval {
        case ..<3_600:
            return "\(Int(interval / 60))m"
        case 3_600..<86_400:
            return "\(Int(interval / 3_600))h"
        default:
            return "\(Int(interval / 86_400))d"
        }
    }

    private static func normalizedFailureMessage(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let singleLine = trimmed
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return String(singleLine.prefix(240))
    }
}
