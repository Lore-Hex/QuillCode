import Foundation

/// The post-run integrity verdict for a completed agent run: was "finished" honest?
///
/// This mechanizes the never-skip-tests rule so a human (or the morning-triage inbox) does not have to
/// read the transcript to trust the run. It is deliberately a three-state badge with a high-precision
/// bias: `unverified` and `red` are only raised on positive evidence of a problem, never on the mere
/// absence of tests. When in doubt the scanner prefers `verified` over a false alarm, because a badge
/// that cries wolf is a badge nobody reads.
public enum RunIntegrityVerdict: String, Codable, Sendable, Hashable {
    /// Nothing dishonest was detected: any success claim is backed by a real successful test/command
    /// result, and no test/verify command was left failing. This is also the verdict for a benign run
    /// that made no success claims and left no failing tests standing.
    case verified

    /// A success claim ("tests pass", "all green", "verified") has no successful test/command result
    /// backing it, or a test that was started/expected was silently skipped. An honest "we cannot vouch
    /// for this": not necessarily a failure, but not a checked green either.
    case unverified

    /// A test/verify command exited nonzero and the failure was left standing.
    case red

    /// Badge text surfaced in Activity and the finish notification.
    public var badgeLabel: String {
        switch self {
        case .verified: return "VERIFIED"
        case .unverified: return "UNVERIFIED"
        case .red: return "RED"
        }
    }
}

/// A single reason the scanner reached its verdict, kept for inspectability in badge tooltips,
/// notification bodies, and false-positive debugging.
public struct RunIntegrityReason: Sendable, Hashable {
    public enum Rule: String, Sendable, Hashable {
        /// A test/verify command failed and was never re-run successfully.
        case standingTestFailure
        /// The model claimed success but no successful test/command result backs it.
        case unbackedSuccessClaim
        /// The model reported a specific QUANTITATIVE result (a benchmark pass rate, "N/M passed", a
        /// score/reward) whose figures appear in NO tool output of the run — a fabricated result.
        case unbackedResultFigure
        /// A test command was queued/started but produced no completed result.
        case skippedTest
        /// A success claim is backed by an actual successful test/command result.
        case backedSuccessClaim
        /// A test/verify command failed but a later run of it, or another test command, passed.
        case failureThenRerunGreen
    }

    public var rule: Rule
    public var detail: String

    public init(rule: Rule, detail: String) {
        self.rule = rule
        self.detail = detail
    }
}

/// The full result of a run-integrity scan: the badge verdict plus the reasons behind it.
public struct RunIntegrityReport: Sendable, Hashable {
    public var verdict: RunIntegrityVerdict
    public var reasons: [RunIntegrityReason]

    public init(verdict: RunIntegrityVerdict, reasons: [RunIntegrityReason] = []) {
        self.verdict = verdict
        self.reasons = reasons
    }

    /// A one-line, human-readable summary for the notification body / badge tooltip. Never empty.
    public var summaryLine: String {
        switch verdict {
        case .verified:
            if let backed = reasons.first(where: {
                $0.rule == .backedSuccessClaim || $0.rule == .failureThenRerunGreen
            }) {
                return backed.detail
            }
            return "No standing test failures or unbacked claims."
        case .unverified:
            return reasons.first(where: {
                $0.rule == .unbackedResultFigure || $0.rule == .unbackedSuccessClaim || $0.rule == .skippedTest
            })?.detail ?? "A success claim is not backed by a passing test."
        case .red:
            return reasons.first(where: { $0.rule == .standingTestFailure })?.detail
                ?? "A test failure was left standing."
        }
    }
}
