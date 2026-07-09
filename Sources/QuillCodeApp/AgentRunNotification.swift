import Foundation
import QuillCodeCore

/// A "come back and look" notification for an agent run that finished while the user was away.
///
/// The whole point of daily-driving an agent on a loop is that you do NOT watch it. So when a run
/// ends, the app should ping the user when it actually needs them — it is blocked on an approval gate
/// (the agent is waiting on YOU), it errored, or it finished. This type is the pure decision of
/// WHETHER to notify and WHAT to say; the desktop layer gates delivery on the app being unfocused and
/// posts the OS notification.
public struct AgentRunNotification: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        /// The run stopped at an approval gate — the highest priority: the agent is blocked on the user.
        case needsApproval
        /// The run hit an error and stopped.
        case failed
        /// An edit-bearing run whose verification command passed — a CHECKED green, not just a claim.
        case verifiedGreen
        /// An edit-bearing run whose verification command failed (or timed out).
        case checksFailing
        /// An edit-bearing run that was not verified (edits made, but no verification check ran) —
        /// an honest absence of a green claim.
        case unverified
        /// The run produced a final answer with nothing pending.
        case finished
    }

    public var kind: Kind
    public var title: String
    public var body: String
    public var threadID: UUID
    /// The blocked approval's request id, set only for `.needsApproval`, so the notification's
    /// Approve/Skip actions can decide the exact gate without opening the app.
    public var approvalRequestID: String?
    /// The run-integrity badge (VERIFIED / UNVERIFIED / RED) from the post-run transcript scan, when one
    /// was computed. Independent of `kind`: `kind` reports the run's outcome and the project verify gate;
    /// `integrity` is the honesty stamp on the transcript itself (unbacked "tests pass" claims, standing
    /// failures). Surfaced in the title so the user sees the stamp without opening the app.
    public var integrity: RunIntegrityVerdict?

    public var id: String { "\(threadID.uuidString)-\(kind.rawValue)" }

    public init(
        kind: Kind,
        title: String,
        body: String,
        threadID: UUID,
        approvalRequestID: String? = nil,
        integrity: RunIntegrityVerdict? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.threadID = threadID
        self.approvalRequestID = approvalRequestID
        self.integrity = integrity
    }
}

public enum AgentRunNotificationPlanner {
    /// Decides the notification for a just-finished run, ordered by urgency for unattended driving: an
    /// approval gate (blocked on the user) beats a failure beats a normal finish. Returns nil when
    /// there is nothing worth interrupting the user for (e.g. an empty run, or one the user cancelled
    /// — they were clearly watching).
    public static func notification(
        threadTitle rawTitle: String,
        threadID: UUID,
        didFail: Bool,
        pendingApprovalSummary: String?,
        finalAnswer: String?,
        pendingApprovalRequestID: String? = nil,
        didEditFiles: Bool = false,
        hasVerificationAction: Bool = false,
        verification: VerificationVerdict? = nil,
        integrity: RunIntegrityVerdict? = nil
    ) -> AgentRunNotification? {
        let title = displayTitle(rawTitle)
        if let approval = trimmedNonEmpty(pendingApprovalSummary) {
            let approvalLabel = WorkspaceToolDisplayNameBuilder.displayName(for: approval)
            return AgentRunNotification(
                kind: .needsApproval,
                title: "QuillCode needs your approval",
                body: "\(title): approve \(approvalLabel) to continue.",
                threadID: threadID,
                approvalRequestID: trimmedNonEmpty(pendingApprovalRequestID)
            )
        }
        if didFail {
            return AgentRunNotification(
                kind: .failed,
                title: "QuillCode run failed",
                body: "\(title) — the run hit an error and stopped.",
                threadID: threadID
            )
        }
        // For an edit-bearing run, "finished" should be a CHECKED fact, not a claim: report the
        // verification verdict (green / failing), or an honest "unverified" when a verify action exists
        // but no result is in hand. A run that made no edits — or has no verify action to run — falls
        // through to the unchanged plain "finished".
        if didEditFiles, let verificationNotification = verificationNotification(
            title: title,
            threadID: threadID,
            hasVerificationAction: hasVerificationAction,
            verification: verification
        ) {
            return stamped(verificationNotification, integrity: integrity)
        }
        if let answer = trimmedNonEmpty(finalAnswer) {
            return stamped(
                AgentRunNotification(
                    kind: .finished,
                    title: "QuillCode finished",
                    body: summaryLine(title: title, answer: answer),
                    threadID: threadID
                ),
                integrity: integrity
            )
        }
        // Even a run with no final answer text gets a badge if the scanner flagged a problem, so a
        // silent RED/UNVERIFIED run is never suppressed entirely.
        if let integrity, integrity != .verified {
            return stamped(
                AgentRunNotification(
                    kind: .finished,
                    title: "QuillCode finished",
                    body: title,
                    threadID: threadID
                ),
                integrity: integrity
            )
        }
        return nil
    }

    /// Attaches the run-integrity badge to a notification: records it on the `integrity` field and, for
    /// a non-`verified` stamp, prefixes the title with the badge so the honesty verdict is visible at a
    /// glance. A `verified` stamp is recorded but does not shout in the title (the run is already fine).
    static func stamped(_ notification: AgentRunNotification, integrity: RunIntegrityVerdict?) -> AgentRunNotification {
        guard let integrity else { return notification }
        var stamped = notification
        stamped.integrity = integrity
        if integrity != .verified {
            stamped.title = "[\(integrity.badgeLabel)] \(notification.title)"
        }
        return stamped
    }

    private static func verificationNotification(
        title: String,
        threadID: UUID,
        hasVerificationAction: Bool,
        verification: VerificationVerdict?
    ) -> AgentRunNotification? {
        switch verification {
        case .passed:
            return AgentRunNotification(
                kind: .verifiedGreen,
                title: "QuillCode verified",
                body: "\(title) — verification passed.",
                threadID: threadID
            )
        case .failed(let count):
            let checks = count.map { "\($0) check\($0 == 1 ? "" : "s")" } ?? "checks"
            return AgentRunNotification(
                kind: .checksFailing,
                title: "QuillCode verification failed",
                body: "\(title) — \(checks) failing.",
                threadID: threadID
            )
        case .timedOut:
            return AgentRunNotification(
                kind: .checksFailing,
                title: "QuillCode verification failed",
                body: "\(title) — verification timed out.",
                threadID: threadID
            )
        case .commandNotFound, .none:
            // The command could not run, or none is wired yet: only surface "unverified" when the user
            // actually configured a verify action (so a project without one is unchanged).
            guard hasVerificationAction else { return nil }
            return AgentRunNotification(
                kind: .unverified,
                title: "QuillCode finished (unverified)",
                body: "\(title) — edits made, no verification check ran.",
                threadID: threadID
            )
        }
    }

    private static func summaryLine(title: String, answer: String) -> String {
        let snippet = firstLine(answer, limit: 100)
        return snippet.isEmpty ? title : "\(title): \(snippet)"
    }

    private static func firstLine(_ text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cut = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<cut]).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func displayTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your task" : trimmed
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
