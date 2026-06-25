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
