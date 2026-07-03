import Foundation
import QuillCodeAgent
import QuillCodeCore

struct WorkspaceAgentSendCancellation: Equatable {
    var userPrompt: String
    var threadID: UUID
}

enum WorkspaceAgentSendTaskOutcome {
    case completed(WorkspaceAgentSendSessionResult)
    case cancelled(WorkspaceAgentSendCancellation)
    case failed(any Error)

    /// True only for a normally-finished turn. The follow-up drain uses this to decide whether
    /// to run the next queued item: a cancelled (Stop) or failed turn halts the wave and keeps
    /// the remaining queue intact.
    var didComplete: Bool {
        if case .completed = self { return true }
        return false
    }
}

struct WorkspaceAgentSendTaskCoordinator {
    var start: WorkspaceAgentSendStartPlan
    var session: WorkspaceAgentSendSession

    func run(onProgress: AgentRunProgressHandler? = nil) async -> WorkspaceAgentSendTaskOutcome {
        do {
            try Task.checkCancellation()
            return .completed(try await session.run(onProgress: onProgress))
        } catch is CancellationError {
            return .cancelled(WorkspaceAgentSendCancellation(
                userPrompt: start.prompt,
                threadID: start.threadID
            ))
        } catch {
            return .failed(error)
        }
    }
}
