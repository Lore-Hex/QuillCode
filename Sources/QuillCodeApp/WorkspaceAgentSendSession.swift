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
    var recordsUserMessage: Bool
    var runHooks: [ProjectRunHook]

    init(
        prompt: String,
        thread: ChatThread,
        runner: AgentRunner,
        workspaceRoot: URL,
        recordsUserMessage: Bool = true,
        runHooks: [ProjectRunHook] = []
    ) {
        self.prompt = prompt
        self.thread = thread
        self.threadID = thread.id
        self.runner = runner
        self.workspaceRoot = workspaceRoot
        self.recordsUserMessage = recordsUserMessage
        self.runHooks = runHooks
    }

    func run(onProgress: AgentRunProgressHandler? = nil) async throws -> WorkspaceAgentSendSessionResult {
        try Task.checkCancellation()
        var activeThread = thread
        if recordsUserMessage {
            appendUserTurn(prompt, to: &activeThread)
            await onProgress?(activeThread)
        }

        if let failure = try await ProjectRunHookExecutor.run(
            timing: .beforeAgentRun,
            hooks: runHooks,
            thread: &activeThread,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        ) {
            appendAssistantMessage(
                ProjectRunHookExecutor.failureMessage(timing: .beforeAgentRun, failure: failure),
                to: &activeThread
            )
            await onProgress?(activeThread)
            return WorkspaceAgentSendSessionResult(thread: activeThread, savedMemory: false)
        }

        let result = try await runner.send(
            prompt,
            in: activeThread,
            workspaceRoot: workspaceRoot,
            recordUserMessage: false,
            onProgress: onProgress
        )
        try Task.checkCancellation()
        activeThread = result.thread

        if let failure = try await ProjectRunHookExecutor.run(
            timing: .afterAgentRun,
            hooks: runHooks,
            thread: &activeThread,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        ) {
            appendAssistantMessage(
                ProjectRunHookExecutor.failureMessage(timing: .afterAgentRun, failure: failure),
                to: &activeThread
            )
            await onProgress?(activeThread)
        }

        return WorkspaceAgentSendSessionResult(
            thread: activeThread,
            savedMemory: WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: activeThread)
        )
    }

    private func appendUserTurn(_ prompt: String, to thread: inout ChatThread) {
        thread.messages.append(ChatMessage(role: .user, content: prompt))
        thread.events.append(ThreadEvent(kind: .message, summary: prompt))
        thread.updatedAt = Date()
        if thread.title == "New chat" {
            thread.title = WorkspaceThreadSeedBuilder.title(fromUserPrompt: prompt)
        }
    }

    private func appendAssistantMessage(_ message: String, to thread: inout ChatThread) {
        thread.messages.append(ChatMessage(role: .assistant, content: message))
        thread.events.append(ThreadEvent(kind: .message, summary: message))
        thread.updatedAt = Date()
    }
}
