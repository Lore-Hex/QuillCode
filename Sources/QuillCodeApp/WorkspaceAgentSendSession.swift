import Foundation
import QuillCodeAgent
import QuillCodeCore

struct WorkspaceAgentSendSessionResult: Sendable {
    var thread: ChatThread
    var savedMemory: Bool
}

struct WorkspaceAgentSendSession: Sendable {
    var prompt: String
    var thread: ChatThread
    var threadID: UUID
    var runner: AgentRunner
    var workspaceRoot: URL

    init(
        prompt: String,
        thread: ChatThread,
        runner: AgentRunner,
        workspaceRoot: URL
    ) {
        self.prompt = prompt
        self.thread = thread
        self.threadID = thread.id
        self.runner = runner
        self.workspaceRoot = workspaceRoot
    }

    func run(onProgress: AgentRunProgressHandler? = nil) async throws -> WorkspaceAgentSendSessionResult {
        try Task.checkCancellation()
        let result = try await runner.send(
            prompt,
            in: thread,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        )
        try Task.checkCancellation()
        return WorkspaceAgentSendSessionResult(
            thread: result.thread,
            savedMemory: WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: result.thread)
        )
    }
}
