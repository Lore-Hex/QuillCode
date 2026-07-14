import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct WorkspaceAgentSendSessionResult: Sendable {
    var thread: ChatThread
    var savedMemory: Bool
    var pendingApproval: AgentPendingApproval?

    var pendingApprovalToolCall: ToolCall? { pendingApproval?.heldToolCall }

    init(
        thread: ChatThread,
        savedMemory: Bool,
        pendingApproval: AgentPendingApproval? = nil
    ) {
        self.thread = thread
        self.savedMemory = savedMemory
        self.pendingApproval = pendingApproval
    }
}

struct WorkspaceAgentSendSession: Sendable {
    var prompt: String
    var thread: ChatThread
    var threadID: UUID
    var runner: AgentRunner
    var workspaceRoot: URL
    var recordsUserMessage: Bool
    var runHooks: [ProjectRunHook]
    var pluginDataBaseDirectory: URL?
    var selectedProject: ProjectRef?
    var sshRemoteShellExecutor: SSHRemoteShellExecutor

    init(
        prompt: String,
        thread: ChatThread,
        runner: AgentRunner,
        workspaceRoot: URL,
        recordsUserMessage: Bool = true,
        runHooks: [ProjectRunHook] = [],
        pluginDataBaseDirectory: URL? = nil,
        selectedProject: ProjectRef? = nil,
        sshRemoteShellExecutor: SSHRemoteShellExecutor = SSHRemoteShellExecutor()
    ) {
        self.prompt = prompt
        self.thread = thread
        self.threadID = thread.id
        self.runner = runner
        self.workspaceRoot = workspaceRoot
        self.recordsUserMessage = recordsUserMessage
        self.runHooks = runHooks
        self.pluginDataBaseDirectory = pluginDataBaseDirectory
        self.selectedProject = selectedProject
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
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
            prompt: prompt,
            workspaceRoot: workspaceRoot,
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            onProgress: onProgress
        ) {
            appendAssistantMessage(
                ProjectRunHookExecutor.failureMessage(timing: .beforeAgentRun, failure: failure),
                to: &activeThread
            )
            await onProgress?(activeThread)
            return WorkspaceAgentSendSessionResult(
                thread: activeThread,
                savedMemory: false
            )
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

        if let pendingApproval = result.pendingApproval {
            return WorkspaceAgentSendSessionResult(
                thread: activeThread,
                savedMemory: false,
                pendingApproval: pendingApproval
            )
        }

        return try await runAfterHooks(thread: activeThread, onProgress: onProgress)
    }

    func resumeApproved(
        _ pendingApproval: AgentPendingApproval,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> WorkspaceAgentSendSessionResult {
        let result = try await runner.resumeApproved(
            pendingApproval,
            in: thread,
            workspaceRoot: workspaceRoot,
            userMessage: prompt,
            onProgress: onProgress
        )
        if let nextApproval = result.pendingApproval {
            return WorkspaceAgentSendSessionResult(
                thread: result.thread,
                savedMemory: false,
                pendingApproval: nextApproval
            )
        }
        return try await runAfterHooks(thread: result.thread, onProgress: onProgress)
    }

    private func runAfterHooks(
        thread: ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> WorkspaceAgentSendSessionResult {
        var activeThread = thread

        if let failure = try await ProjectRunHookExecutor.run(
            timing: .afterAgentRun,
            hooks: runHooks,
            thread: &activeThread,
            prompt: prompt,
            workspaceRoot: workspaceRoot,
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor,
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
