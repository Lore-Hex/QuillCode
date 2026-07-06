import Foundation

/// # Morning triage inbox (issue #877)
///
/// The morning ritual for unattended daily driving: overnight runs, reviewable before the coffee cools.
/// These files are the pure deterministic core, with no SwiftUI or persistence side effects, so the
/// native app and the E2E HTML harness can share exactly the same ranking, selection, and triage rules.
///
/// The pieces:
/// - `TriageStamp` — a thread's persistent verdict stamp, derived from its latest **persisted**
///   `RunIntegrityRecord` (the Run Integrity badge — never self-report). A thread with no run has no
///   stamp.
/// - `ThreadTriageState` + `ThreadTriageRecord` — the user's triage decision (pending / acknowledged /
///   dismissed), persisted onto the thread as a `.notice` event exactly like `RunIntegrityRecord`, so
///   it round-trips through the existing thread store with zero new plumbing and survives reload.
/// - `AttentionItem` — one row in the Attention section: verdict + title + unseen-turn count.
/// - `AttentionModel` — the ranking (severity order, ties by recency) and a selection cursor with
///   j/k clamping.

// MARK: - Verdict stamp

/// The severity of a thread's run-integrity verdict, for the triage stamp. This is a **projection** of
/// `RunIntegrityVerdict` with an explicit severity ordering so the Attention section can rank rows and
/// so `verified` is representable but known to be "does not need attention".
public enum TriageVerdict: String, Codable, Sendable, Hashable, CaseIterable {
    /// A test/verify command failed and was left standing — the loudest alarm.
    case red
    /// A success claim is not backed by a passing test, or a test was skipped — honest uncertainty.
    case unverified
    /// Nothing dishonest detected — a clean run. Never surfaced in Attention.
    case verified

    /// Higher = more urgent. Used to rank the Attention section (RED before UNVERIFIED).
    public var severity: Int {
        switch self {
        case .red: return 2
        case .unverified: return 1
        case .verified: return 0
        }
    }

    /// Whether a thread with this verdict belongs in the Attention section at all. A clean `verified`
    /// run does not need the morning triage.
    public var needsAttention: Bool { self != .verified }

    /// The equivalent run-integrity verdict — the single source for badge text, so "matches the Run
    /// Integrity badge exactly" is structural, not a hand-synced string table.
    public var runIntegrityVerdict: RunIntegrityVerdict {
        switch self {
        case .red: return .red
        case .unverified: return .unverified
        case .verified: return .verified
        }
    }

    /// The badge text, delegated to the Run Integrity badge so the two can never drift.
    public var badgeLabel: String { runIntegrityVerdict.badgeLabel }

    public init(_ verdict: RunIntegrityVerdict) {
        switch verdict {
        case .red: self = .red
        case .unverified: self = .unverified
        case .verified: self = .verified
        }
    }
}

/// A thread's persistent triage stamp: the verdict plus the one-line summary from the run-integrity
/// record. `nil` when the thread has never been scanned (no run → no stamp).
public struct TriageStamp: Sendable, Hashable {
    public var verdict: TriageVerdict
    public var summary: String

    public init(verdict: TriageVerdict, summary: String) {
        self.verdict = verdict
        self.summary = summary
    }

    /// Derive the stamp from a thread by reading its latest **persisted** `RunIntegrityRecord`. This is
    /// the verdict SOURCE — the record already written by the Run Integrity feature — not a re-derivation
    /// from the transcript / self-report. Returns `nil` when no record was ever written.
    public static func derive(from thread: ChatThread) -> TriageStamp? {
        guard let payload = RunIntegrityRecord.latest(in: thread) else { return nil }
        return TriageStamp(verdict: TriageVerdict(payload.verdict), summary: payload.summary)
    }
}
