import QuillCodeCore

enum WorkspaceActivityEventSurfaceBuilder {
    static func recentSteps(for thread: ChatThread) -> [ActivityItemSurface] {
        thread.events
            .filter { $0.kind != .messageFeedback }
            .suffix(8)
            .map { event in
                ActivityItemSurface(
                    id: event.id.uuidString,
                    title: eventKindLabel(event.kind),
                    detail: WorkspaceActivityText.boundedLine(event.summary, limit: 140),
                    kind: event.kind.rawValue,
                    statusLabel: eventStatusLabel(event.kind)
                )
            }
    }

    private static func eventKindLabel(_ kind: ThreadEventKind) -> String {
        switch kind {
        case .message:
            return "Message"
        case .toolQueued:
            return "Tool queued"
        case .toolRunning:
            return "Tool running"
        case .toolProgress:
            return "Tool progress"
        case .toolCompleted:
            return "Tool completed"
        case .toolFailed:
            return "Tool failed"
        case .approvalRequested:
            return "Safety check"
        case .approvalDecided:
            return "Safety decision"
        case .reviewComment:
            return "Review comment"
        case .notice:
            return "Notice"
        case .messageFeedback:
            return "Feedback"
        }
    }

    private static func eventStatusLabel(_ kind: ThreadEventKind) -> String {
        switch kind {
        case .toolQueued:
            return ActivityStatusLabel.queued
        case .toolRunning, .toolProgress:
            return ActivityStatusLabel.running
        case .toolCompleted:
            return ActivityStatusLabel.done
        case .toolFailed:
            return ActivityStatusLabel.failed
        case .approvalRequested:
            return ActivityStatusLabel.review
        case .approvalDecided:
            return ActivityStatusLabel.checked
        case .message, .reviewComment, .notice, .messageFeedback:
            return ActivityStatusLabel.logged
        }
    }
}
