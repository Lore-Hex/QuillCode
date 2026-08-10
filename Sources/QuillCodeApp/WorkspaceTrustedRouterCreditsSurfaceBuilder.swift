import Foundation
import QuillCodeCore

public enum ProviderAccountBalanceTone: String, Codable, Sendable, Hashable {
    case normal
    case updating
    case warning
}

public struct ProviderKeyLimitSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { periodLabel }
    public var periodLabel: String
    public var usageLabel: String
    public var remainingLabel: String?
    public var resetLabel: String?
    public var detailLabel: String

    public init(
        periodLabel: String,
        usageLabel: String,
        remainingLabel: String?,
        resetLabel: String?,
        detailLabel: String
    ) {
        self.periodLabel = periodLabel
        self.usageLabel = usageLabel
        self.remainingLabel = remainingLabel
        self.resetLabel = resetLabel
        self.detailLabel = detailLabel
    }
}

public struct ProviderAccountBalanceSurface: Codable, Sendable, Hashable {
    public var amountLabel: String?
    public var statusLabel: String
    public var detailLabel: String
    public var historyLabel: String?
    public var tone: ProviderAccountBalanceTone
    public var limits: [ProviderKeyLimitSurface]?

    public init(
        amountLabel: String?,
        statusLabel: String,
        detailLabel: String,
        historyLabel: String? = nil,
        tone: ProviderAccountBalanceTone,
        limits: [ProviderKeyLimitSurface] = []
    ) {
        self.amountLabel = amountLabel
        self.statusLabel = statusLabel
        self.detailLabel = detailLabel
        self.historyLabel = historyLabel
        self.tone = tone
        self.limits = limits.isEmpty ? nil : limits
    }

    public var compactLabel: String {
        amountLabel ?? statusLabel
    }

    public var visibleLimits: [ProviderKeyLimitSurface] {
        limits ?? []
    }

    public var accessibilityLabel: String {
        let limitDetails = visibleLimits.map(\.detailLabel).joined(separator: ". ")
        return [
            "TrustedRouter key usage: \(amountLabel ?? statusLabel).",
            detailLabel,
            limitDetails
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
}

struct WorkspaceTrustedRouterCreditsSurfaceBuilder: Sendable, Hashable {
    var state: TrustedRouterCreditsState
    var hasCredential: Bool
    var now: Date = Date()

    func surface() -> ProviderAccountBalanceSurface? {
        guard hasCredential else { return nil }

        switch state.phase {
        case .unavailable:
            return ProviderAccountBalanceSurface(
                amountLabel: nil,
                statusLabel: "Key limits not loaded",
                detailLabel: "Refresh to load usage and limits for this TrustedRouter key.",
                tone: .updating
            )
        case .refreshing:
            return ProviderAccountBalanceSurface(
                amountLabel: state.snapshot.map(primaryAmountLabel),
                statusLabel: "Refreshing key limits",
                detailLabel: refreshingDetail,
                tone: .updating,
                limits: state.snapshot.map(limitSurfaces) ?? []
            )
        case .current:
            guard let snapshot = state.snapshot else {
                return missingSnapshotSurface
            }
            let limits = limitSurfaces(snapshot)
            return ProviderAccountBalanceSurface(
                amountLabel: primaryAmountLabel(snapshot),
                statusLabel: currentStatusLabel(snapshot),
                detailLabel: detailWithHistory(currentDetail(snapshot)),
                historyLabel: historyLabel,
                tone: currentTone(snapshot),
                limits: limits
            )
        case .stale:
            guard let snapshot = state.snapshot else {
                return missingSnapshotSurface
            }
            return ProviderAccountBalanceSurface(
                amountLabel: primaryAmountLabel(snapshot),
                statusLabel: "Key limits may be stale",
                detailLabel: detailWithHistory(staleDetail(snapshot)),
                historyLabel: historyLabel,
                tone: .warning,
                limits: limitSurfaces(snapshot)
            )
        case .failed:
            return ProviderAccountBalanceSurface(
                amountLabel: nil,
                statusLabel: "Key limits unavailable",
                detailLabel: state.failureMessage ?? "TrustedRouter key usage could not be refreshed.",
                tone: .warning
            )
        }
    }

    private var missingSnapshotSurface: ProviderAccountBalanceSurface {
        ProviderAccountBalanceSurface(
            amountLabel: nil,
            statusLabel: "Key limits unavailable",
            detailLabel: "TrustedRouter did not return usable key usage and limits.",
            tone: .warning
        )
    }

    private var refreshingDetail: String {
        guard let snapshot = state.snapshot else {
            return "Loading usage and limits for this TrustedRouter key."
        }
        return "Refreshing TrustedRouter key usage and limits. "
            + "Last successful update \(ageLabel(snapshot.fetchedAt).lowercased())."
    }

    private func staleDetail(_ snapshot: TrustedRouterCreditsSnapshot) -> String {
        var parts = ["Last successful update \(ageLabel(snapshot.fetchedAt).lowercased())."]
        if let failureMessage = state.failureMessage {
            parts.append(failureMessage)
        }
        return parts.joined(separator: " ")
    }

    private func detailWithHistory(_ detail: String) -> String {
        let history = historyLabel.map { " \($0)" } ?? ""
        return "\(detail)\(history)"
    }

    private var historyLabel: String? {
        let entries = state.history.prefix(4).map { snapshot in
            "\(primaryAmountLabel(snapshot)) \(ageLabel(snapshot.fetchedAt).lowercased())"
        }
        guard !entries.isEmpty else { return nil }
        return "Recent key-limit history: \(entries.joined(separator: "; "))."
    }

    private func ageLabel(_ fetchedAt: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(fetchedAt))
        if elapsed < 60 {
            return "Updated just now"
        }
        if elapsed < 60 * 60 {
            return "Updated \(Int(elapsed / 60))m ago"
        }
        if elapsed < 24 * 60 * 60 {
            return "Updated \(Int(elapsed / (60 * 60)))h ago"
        }
        return "Updated \(Int(elapsed / (24 * 60 * 60)))d ago"
    }

    private func primaryAmountLabel(_ snapshot: TrustedRouterCreditsSnapshot) -> String {
        limitSurface(snapshot.primaryWindow, currency: snapshot.currency).map {
            "\($0.periodLabel) \($0.usageLabel)"
        } ?? "Total \(Self.money(snapshot.lifetime.usage, currency: snapshot.currency)) used"
    }

    private func currentDetail(_ snapshot: TrustedRouterCreditsSnapshot) -> String {
        let enforcement = snapshot.budgetAlertOnly
            ? "Limits send alerts without stopping requests."
            : "Requests stop when a limit is reached."
        return "\(ageLabel(snapshot.fetchedAt)). \(enforcement)"
    }

    private func limitSurfaces(_ snapshot: TrustedRouterCreditsSnapshot) -> [ProviderKeyLimitSurface] {
        snapshot.windows.compactMap { window in
            guard window.window == .lifetime || window.limit != nil || window.usage > 0 else { return nil }
            return limitSurface(window, currency: snapshot.currency)
        }
    }

    private func limitSurface(
        _ window: TrustedRouterCreditsWindowSnapshot,
        currency: String?
    ) -> ProviderKeyLimitSurface? {
        let usage = Self.money(window.usage, currency: currency)
        let usageLabel = window.limit.map { "\(usage) / \(Self.money($0, currency: currency))" }
            ?? "\(usage) used"
        let remainingLabel = window.remaining.map { "\(Self.money($0, currency: currency)) left" }
            ?? (window.window == .lifetime && window.limit == nil ? "No total cap" : nil)
        let resetLabel = window.resetsAt.map(resetLabel)
        var details = ["\(window.window.displayLabel): \(usageLabel)"]
        if let remainingLabel { details.append(remainingLabel) }
        if let resetLabel { details.append(resetLabel.lowercased()) }
        if let usedPercent = window.usedPercent { details.append("\(usedPercent)% used") }
        return ProviderKeyLimitSurface(
            periodLabel: window.window.displayLabel,
            usageLabel: usageLabel,
            remainingLabel: remainingLabel,
            resetLabel: resetLabel,
            detailLabel: details.joined(separator: " · ")
        )
    }

    private func currentStatusLabel(_ snapshot: TrustedRouterCreditsSnapshot) -> String {
        currentTone(snapshot) == .warning ? "Key limit nearly reached" : "Key limits current"
    }

    private func currentTone(_ snapshot: TrustedRouterCreditsSnapshot) -> ProviderAccountBalanceTone {
        snapshot.windows.contains { ($0.usedPercent ?? 0) >= 90 } ? .warning : .normal
    }

    private func resetLabel(_ date: Date) -> String {
        let elapsed = date.timeIntervalSince(now)
        guard elapsed > 0 else { return "Reset due" }
        if elapsed < 60 * 60 { return "Resets in \(max(1, Int(ceil(elapsed / 60))))m" }
        if elapsed < 24 * 60 * 60 { return "Resets in \(max(1, Int(ceil(elapsed / 3_600))))h" }
        return "Resets in \(max(1, Int(ceil(elapsed / 86_400))))d"
    }

    private static func money(_ value: Double, currency: String?) -> String {
        let amount = decimalLabel(value, fractionDigits: currency == "JPY" ? 0 : 2)
        switch currency {
        case "USD": return "$\(amount)"
        case "EUR": return "€\(amount)"
        case "GBP": return "£\(amount)"
        case "JPY": return "¥\(amount)"
        case let currency?: return "\(currency) \(amount)"
        case nil: return "\(amount) credits"
        }
    }

    private static func decimalLabel(_ value: Double, fractionDigits: Int) -> String {
        let roundingThreshold = 0.5 / pow(10, Double(fractionDigits))
        let normalized = abs(value) < roundingThreshold ? 0 : value
        return String(
            format: "%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            fractionDigits,
            normalized
        )
    }
}
