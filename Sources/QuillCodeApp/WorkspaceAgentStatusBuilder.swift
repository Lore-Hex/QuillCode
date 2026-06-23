import QuillCodeAgent
import QuillCodeCore

struct WorkspaceAgentStatusBuilder: Sendable, Hashable {
    private init() {}

    static func status(for thread: ChatThread) -> String {
        status(for: thread.events.last)
    }

    static func status(for event: ThreadEvent?) -> String {
        switch event?.kind {
        case .toolQueued:
            return "Queued"
        case .toolRunning:
            return "Running"
        case .approvalRequested:
            return "Review"
        case .notice where event?.summary == AgentRunner.streamingNotice:
            return "Streaming"
        case .toolCompleted:
            return "Finishing"
        case .toolFailed:
            return "Failed"
        case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice, .none:
            return "Running"
        }
    }
}
