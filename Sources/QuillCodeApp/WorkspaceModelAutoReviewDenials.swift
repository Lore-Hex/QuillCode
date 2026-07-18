import Foundation
import QuillCodeAgent
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func retryAutoReviewDenial(requestID: String, workspaceRoot: URL) async {
        guard autoReviewDenialRetryingRequestID == nil,
              let thread = selectedThread,
              thread.mode == .auto,
              let intent = thread.messages.last(where: { $0.role == .user })?.content
        else {
            setLastError("Auto-review retries require the original Auto-mode task context.")
            return
        }

        autoReviewDenialRetryingRequestID = requestID
        setLastError(nil)
        defer { autoReviewDenialRetryingRequestID = nil }

        let runProject = thread.projectID.flatMap(project(id:))
        let configuredRunner = agentSendSessionFactory(
            workspaceRoot: workspaceRoot,
            runProject: runProject
        ).configuredRunner(
            modelID: thread.model,
            threadID: thread.id,
            // A denial retry from a confidential chat is still a confidential run: without the flag
            // it would skip the E2E model clamp AND attach plugin tool hooks (external processes
            // that commonly log) to the private transcript.
            threadIsConfidential: thread.runtimeContext.isConfidential
        )

        do {
            let result = try await configuredRunner.retryAutoReviewDenial(
                requestID: requestID,
                in: thread,
                workspaceRoot: workspaceRoot,
                userMessage: intent
            ) { [weak self] progress in
                await self?.persistAutoReviewRetryProgress(progress, expectedThreadID: thread.id)
            }
            updateThreadFromAgentRun(result.thread)
            try threadPersistence.saveOrThrow(result.thread)
            refreshTopBar(agentStatus: root.topBar.agentStatus)
        } catch {
            setLastError(error.localizedDescription)
        }
    }

    private func persistAutoReviewRetryProgress(_ thread: ChatThread, expectedThreadID: UUID) {
        guard thread.id == expectedThreadID else { return }
        updateThreadFromAgentRun(thread)
        threadPersistence.save(thread)
    }
}
