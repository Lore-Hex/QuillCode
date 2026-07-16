import Foundation
import QuillCodeCore

public enum ProviderAccountBalanceTone: String, Codable, Sendable, Hashable {
    case normal
    case updating
    case warning
}

public struct ProviderAccountBalanceSurface: Codable, Sendable, Hashable {
    public var amountLabel: String?
    public var statusLabel: String
    public var detailLabel: String
    public var tone: ProviderAccountBalanceTone

    public init(
        amountLabel: String?,
        statusLabel: String,
        detailLabel: String,
        tone: ProviderAccountBalanceTone
    ) {
        self.amountLabel = amountLabel
        self.statusLabel = statusLabel
        self.detailLabel = detailLabel
        self.tone = tone
    }

    public var compactLabel: String {
        amountLabel.map { "Balance \($0)" } ?? statusLabel
    }

    public var accessibilityLabel: String {
        "TrustedRouter account balance: \(amountLabel ?? statusLabel). \(detailLabel)"
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
                statusLabel: "Balance not loaded",
                detailLabel: "Refresh to load the current TrustedRouter account balance.",
                tone: .updating
            )
        case .refreshing:
            return ProviderAccountBalanceSurface(
                amountLabel: state.snapshot.map(Self.amountLabel),
                statusLabel: "Refreshing balance",
                detailLabel: refreshingDetail,
                tone: .updating
            )
        case .current:
            guard let snapshot = state.snapshot else {
                return missingSnapshotSurface
            }
            return ProviderAccountBalanceSurface(
                amountLabel: Self.amountLabel(snapshot),
                statusLabel: "Balance current",
                detailLabel: "Current TrustedRouter account balance. \(ageLabel(snapshot.fetchedAt)).",
                tone: .normal
            )
        case .stale:
            guard let snapshot = state.snapshot else {
                return missingSnapshotSurface
            }
            return ProviderAccountBalanceSurface(
                amountLabel: Self.amountLabel(snapshot),
                statusLabel: "Balance may be stale",
                detailLabel: staleDetail(snapshot),
                tone: .warning
            )
        case .failed:
            return ProviderAccountBalanceSurface(
                amountLabel: nil,
                statusLabel: "Balance unavailable",
                detailLabel: state.failureMessage ?? "TrustedRouter account balance could not be refreshed.",
                tone: .warning
            )
        }
    }

    private var missingSnapshotSurface: ProviderAccountBalanceSurface {
        ProviderAccountBalanceSurface(
            amountLabel: nil,
            statusLabel: "Balance unavailable",
            detailLabel: "TrustedRouter did not return a usable account balance.",
            tone: .warning
        )
    }

    private var refreshingDetail: String {
        guard let snapshot = state.snapshot else {
            return "Loading the current TrustedRouter account balance."
        }
        return "Refreshing the TrustedRouter account balance. "
            + "Last successful update \(ageLabel(snapshot.fetchedAt).lowercased())."
    }

    private func staleDetail(_ snapshot: TrustedRouterCreditsSnapshot) -> String {
        var parts = ["Last successful update \(ageLabel(snapshot.fetchedAt).lowercased())."]
        if let failureMessage = state.failureMessage {
            parts.append(failureMessage)
        }
        return parts.joined(separator: " ")
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

    private static func amountLabel(_ snapshot: TrustedRouterCreditsSnapshot) -> String {
        let amount = decimalLabel(snapshot.balance)
        switch snapshot.currency {
        case "USD": return "$\(amount)"
        case "EUR": return "€\(amount)"
        case "GBP": return "£\(amount)"
        case "JPY": return "¥\(amount)"
        case let currency?: return "\(currency) \(amount)"
        case nil: return "\(amount) credits"
        }
    }

    private static func decimalLabel(_ value: Double) -> String {
        let normalized = abs(value) < 0.00005 ? 0 : value
        var label = String(
            format: "%.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            normalized
        )
        while label.last == "0", label.split(separator: ".").last?.count ?? 0 > 2 {
            label.removeLast()
        }
        return label
    }
}
