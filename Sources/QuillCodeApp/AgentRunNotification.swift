import Foundation

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
        /// The run produced a final answer with nothing pending.
        case finished
    }

    public var kind: Kind
    public var title: String
    public var body: String
    public var threadID: UUID

    public var id: String { "\(threadID.uuidString)-\(kind.rawValue)" }

    public init(kind: Kind, title: String, body: String, threadID: UUID) {
        self.kind = kind
        self.title = title
        self.body = body
        self.threadID = threadID
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
        finalAnswer: String?
    ) -> AgentRunNotification? {
        let title = displayTitle(rawTitle)
        if let approval = trimmedNonEmpty(pendingApprovalSummary) {
            return AgentRunNotification(
                kind: .needsApproval,
                title: "QuillCode needs your approval",
                body: "\(title): approve \(approval) to continue.",
                threadID: threadID
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
        if let answer = trimmedNonEmpty(finalAnswer) {
            return AgentRunNotification(
                kind: .finished,
                title: "QuillCode finished",
                body: summaryLine(title: title, answer: answer),
                threadID: threadID
            )
        }
        return nil
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
