import Foundation
import QuillCodeCore

struct WorkspaceTranscriptThinkingSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread?
    var composer: ComposerState
    var agentStatus: String

    func surface() -> TranscriptThinkingSurface? {
        guard composer.isSending, let thread else { return nil }
        if thread.messages.last(where: { $0.role != .tool })?.role == .assistant {
            return nil
        }
        let traceLines = Self.traceLines(from: thread.events)
        return TranscriptThinkingSurface(
            id: "thinking-\(thread.id.uuidString)",
            title: title,
            subtitle: subtitle(traceLines: traceLines),
            traceLines: traceLines
        )
    }

    private var title: String {
        switch agentStatus {
        case TopBarAgentStatusLabel.queued:
            return "Queued"
        case TopBarAgentStatusLabel.streaming:
            return "Streaming"
        case TopBarAgentStatusLabel.review:
            return "Reviewing"
        case TopBarAgentStatusLabel.finishing:
            return "Finishing"
        default:
            return "Thinking"
        }
    }

    private func subtitle(traceLines: [String]) -> String {
        traceLines.last ?? "Preparing the next step"
    }

    private static func traceLines(from events: [ThreadEvent]) -> [String] {
        events.compactMap(traceLine).suffix(6).map { $0 }
    }

    private static func traceLine(for event: ThreadEvent) -> String? {
        switch event.kind {
        case .message, .messageFeedback, .reviewComment:
            return nil
        case .notice:
            return event.summary
        case .toolQueued:
            return "Queued: \(event.summary)"
        case .toolRunning:
            return "Running: \(event.summary)"
        case .toolCompleted:
            return "Completed: \(event.summary)"
        case .toolFailed:
            return "Failed: \(event.summary)"
        case .approvalRequested:
            return "Safety check: \(event.summary)"
        case .approvalDecided:
            return "Safety decision: \(event.summary)"
        }
    }
}
