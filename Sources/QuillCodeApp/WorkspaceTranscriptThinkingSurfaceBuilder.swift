import Foundation
import QuillCodeCore

struct WorkspaceTranscriptThinkingSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread?
    var composer: ComposerState
    var agentStatus: String

    func surface() -> TranscriptThinkingSurface? {
        guard composer.isSending, let thread else { return nil }
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
        let summary = displaySummary(for: event)
        switch event.kind {
        case .message, .messageFeedback, .reviewComment:
            return nil
        case .notice:
            return summary
        case .toolQueued:
            return "Queued: \(summary)"
        case .toolRunning:
            return "Running: \(summary)"
        case .toolProgress:
            return progressTraceLine(for: event)
        case .toolCompleted:
            return "Completed: \(summary)"
        case .toolFailed:
            return "Failed: \(summary)"
        case .approvalRequested:
            return "Safety check: \(summary)"
        case .approvalDecided:
            return "Safety decision: \(summary)"
        }
    }

    private static func progressTraceLine(for event: ThreadEvent) -> String {
        guard let payloadJSON = event.payloadJSON,
              let payload = try? JSONHelpers.decode(ToolProgressEventPayload.self, from: payloadJSON) else {
            return "Running: \(event.summary)"
        }
        let message = payload.progress.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fraction = payload.progress.fractionCompleted {
            let percent = Int((fraction * 100).rounded())
            return message.map { "Running: \($0) (\(percent)%)" } ?? "Running: \(percent)%"
        }
        return message.map { "Running: \($0)" } ?? "Running: \(event.summary)"
    }

    private static func displaySummary(for event: ThreadEvent) -> String {
        if let payloadName = toolName(from: event.payloadJSON) {
            return WorkspaceToolDisplayNameBuilder.displayName(for: payloadName)
        }

        guard let match = knownToolName(in: event.summary) else {
            return event.summary
        }

        let displayName = WorkspaceToolDisplayNameBuilder.displayName(for: match)
        let remainder = event.summary.dropFirst(match.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? displayName : "\(displayName) \(remainder)"
    }

    private static func toolName(from payloadJSON: String?) -> String? {
        guard let payloadJSON, let data = payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ToolCall.self, from: data).name
    }

    private static func knownToolName(in summary: String) -> String? {
        WorkspaceToolDisplayNameBuilder.knownToolNames
            .filter { summary == $0 || summary.hasPrefix("\($0) ") }
            .max(by: { $0.count < $1.count })
    }
}
