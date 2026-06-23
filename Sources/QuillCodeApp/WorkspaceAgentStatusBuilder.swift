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
            return TopBarAgentStatusLabel.queued
        case .toolRunning:
            return TopBarAgentStatusLabel.running
        case .approvalRequested:
            return TopBarAgentStatusLabel.review
        case .notice where event?.summary == AgentRunner.streamingNotice:
            return TopBarAgentStatusLabel.streaming
        case .toolCompleted:
            return TopBarAgentStatusLabel.finishing
        case .toolFailed:
            return TopBarAgentStatusLabel.failed
        case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice, .none:
            return TopBarAgentStatusLabel.running
        }
    }
}
