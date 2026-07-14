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

        return try await runAgentTurn(
            prompt: prompt,
            thread: activeThread,
            stopHookActive: false,
            onProgress: onProgress
        )
    }

    private func runAgentTurn(
        prompt: String,
        thread: ChatThread,
        stopHookActive: Bool,
        onProgress: AgentRunProgressHandler?
    ) async throws -> WorkspaceAgentSendSessionResult {
        var activeThread = thread
        let beforeHooks = try await ProjectRunHookExecutor.run(
            timing: .beforeAgentRun,
            hooks: runHooks,
            thread: &activeThread,
            prompt: prompt,
            workspaceRoot: workspaceRoot,
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            onProgress: onProgress
        )
        if let failure = beforeHooks.firstFailure {
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

        if let control = beforeHooks.continueFalse ?? beforeHooks.block {
            appendAssistantMessage(
                "Prompt blocked by \(control.hook.title). \(control.reason)",
                to: &activeThread
            )
            await onProgress?(activeThread)
            return WorkspaceAgentSendSessionResult(thread: activeThread, savedMemory: false)
        }

        appendHookContexts(beforeHooks.contexts, to: &activeThread)

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

        return try await runAfterHooks(
            thread: activeThread,
            prompt: prompt,
            stopHookActive: stopHookActive,
            onProgress: onProgress
        )
    }

    func resumeApproved(
        _ pendingApproval: AgentPendingApproval,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> WorkspaceAgentSendSessionResult {
        let continuation = StopHookContinuationState.active(in: thread)
        let activePrompt = continuation?.prompt ?? prompt
        let result = try await runner.resumeApproved(
            pendingApproval,
            in: thread,
            workspaceRoot: workspaceRoot,
            userMessage: activePrompt,
            onProgress: onProgress
        )
        if let nextApproval = result.pendingApproval {
            return WorkspaceAgentSendSessionResult(
                thread: result.thread,
                savedMemory: false,
                pendingApproval: nextApproval
            )
        }
        return try await runAfterHooks(
            thread: result.thread,
            prompt: activePrompt,
            stopHookActive: continuation != nil,
            onProgress: onProgress
        )
    }

    private func runAfterHooks(
        thread: ChatThread,
        prompt: String,
        stopHookActive: Bool,
        onProgress: AgentRunProgressHandler?
    ) async throws -> WorkspaceAgentSendSessionResult {
        var activeThread = thread

        let afterHooks = try await ProjectRunHookExecutor.run(
            timing: .afterAgentRun,
            hooks: runHooks,
            thread: &activeThread,
            prompt: prompt,
            workspaceRoot: workspaceRoot,
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            stopHookActive: stopHookActive,
            onProgress: onProgress
        )
        if let failure = afterHooks.firstFailure {
            appendAssistantMessage(
                ProjectRunHookExecutor.failureMessage(timing: .afterAgentRun, failure: failure),
                to: &activeThread
            )
            await onProgress?(activeThread)
            return completed(thread: activeThread)
        }

        if let stopped = afterHooks.continueFalse {
            activeThread.events.append(ThreadEvent(
                kind: .notice,
                summary: "Stop hook ended the run: \(stopped.reason)"
            ))
            activeThread.updatedAt = Date()
            await onProgress?(activeThread)
            return completed(thread: activeThread)
        }

        if let continuation = afterHooks.block {
            guard !stopHookActive else {
                activeThread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Ignored another Stop-hook continuation from \(continuation.hook.title)."
                ))
                activeThread.updatedAt = Date()
                await onProgress?(activeThread)
                return completed(thread: activeThread)
            }

            appendUserTurn(continuation.reason, to: &activeThread)
            StopHookContinuationState.record(
                prompt: continuation.reason,
                in: &activeThread
            )
            await onProgress?(activeThread)
            return try await runAgentTurn(
                prompt: continuation.reason,
                thread: activeThread,
                stopHookActive: true,
                onProgress: onProgress
            )
        }

        return completed(thread: activeThread)
    }

    private func completed(thread: ChatThread) -> WorkspaceAgentSendSessionResult {
        WorkspaceAgentSendSessionResult(
            thread: thread,
            savedMemory: WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread)
        )
    }

    private func appendHookContexts(
        _ contexts: [ProjectRunHookContext],
        to thread: inout ChatThread
    ) {
        guard !contexts.isEmpty else { return }
        let content = contexts.map { context in
            "Standard plugin hook context from \(context.hook.title):\n\(context.content)"
        }.joined(separator: "\n\n")
        thread.messages.append(ChatMessage(role: .system, content: content))
        thread.updatedAt = Date()
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

private struct StopHookContinuationState: Codable, Sendable, Equatable {
    static let eventSummary = "Stop hook requested another agent turn"

    var turnID: UUID
    var prompt: String

    static func record(prompt: String, in thread: inout ChatThread) {
        guard let turnID = thread.messages.last(where: { $0.role == .user })?.id else { return }
        let state = StopHookContinuationState(turnID: turnID, prompt: prompt)
        thread.events.append(ThreadEvent(
            kind: .notice,
            summary: eventSummary,
            payloadJSON: try? JSONHelpers.encodePretty(state)
        ))
        thread.updatedAt = Date()
    }

    static func active(in thread: ChatThread) -> StopHookContinuationState? {
        guard let latestUserID = thread.messages.last(where: { $0.role == .user })?.id else {
            return nil
        }
        return thread.events.reversed().lazy.compactMap { event -> StopHookContinuationState? in
            guard event.kind == .notice,
                  event.summary == eventSummary,
                  let payload = event.payloadJSON,
                  let state = try? JSONHelpers.decode(StopHookContinuationState.self, from: payload),
                  state.turnID == latestUserID
            else { return nil }
            return state
        }.first
    }
}
