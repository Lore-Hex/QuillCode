import QuillCodeCore

/// Persists crash-relevant tool boundaries without writing every coalesced streaming snapshot.
enum WorkspaceAgentProgressPersistencePolicy {
    static func shouldPersist(
        previousLastEvent: ThreadEvent?,
        currentLastEvent: ThreadEvent?
    ) -> Bool {
        guard let currentLastEvent, currentLastEvent != previousLastEvent else { return false }
        switch currentLastEvent.kind {
        case .toolQueued, .toolRunning, .toolCompleted, .toolFailed,
             .approvalRequested, .approvalDecided:
            return true
        case .toolProgress:
            return previousLastEvent?.kind != .toolProgress
        case .message, .messageFeedback, .reviewComment, .notice:
            return false
        }
    }
}
