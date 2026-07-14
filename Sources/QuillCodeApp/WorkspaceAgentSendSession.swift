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
    var pluginLifecycleHooks: ProjectPluginLifecycleHookExecutor
    var lifecycle: WorkspaceAgentSessionLifecycle
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
        pluginLifecycleHooks: ProjectPluginLifecycleHookExecutor = ProjectPluginLifecycleHookExecutor(
            hooks: [],
            pluginDataBaseDirectory: nil,
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ),
        lifecycle: WorkspaceAgentSessionLifecycle = .primary(WorkspaceSessionStartHookCoordinator()),
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
        self.pluginLifecycleHooks = pluginLifecycleHooks
        self.lifecycle = lifecycle
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
        let preparation = await prepareLifecycle(thread: activeThread, onProgress: onProgress)
        activeThread = preparation.thread
        if preparation.stopped {
            return completed(thread: activeThread)
        }

        return try await runAgentTurn(
            prompt: prompt,
            thread: activeThread,
            stopHookActive: false,
            subagentStopHookActive: false,
            onProgress: onProgress
        )
    }

    func runAgentTurn(
        prompt: String,
        thread: ChatThread,
        stopHookActive: Bool,
        subagentStopHookActive: Bool,
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
            subagentStopHookActive: subagentStopHookActive,
            onProgress: onProgress
        )
    }

    func resumeApproved(
        _ pendingApproval: AgentPendingApproval,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> WorkspaceAgentSendSessionResult {
        let preparation = await prepareLifecycle(thread: thread, onProgress: onProgress)
        guard !preparation.stopped else { return completed(thread: preparation.thread) }
        let stopContinuation = HookContinuationState.active(
            eventSummary: HookContinuationState.stopEventSummary,
            in: preparation.thread
        )
        let subagentContinuation = HookContinuationState.active(
            eventSummary: HookContinuationState.subagentStopEventSummary,
            in: preparation.thread
        )
        let activePrompt = subagentContinuation?.prompt ?? stopContinuation?.prompt ?? prompt
        let result = try await runner.resumeApproved(
            pendingApproval,
            in: preparation.thread,
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
            stopHookActive: stopContinuation != nil,
            subagentStopHookActive: subagentContinuation != nil,
            onProgress: onProgress
        )
    }

    private func runAfterHooks(
        thread: ChatThread,
        prompt: String,
        stopHookActive: Bool,
        subagentStopHookActive: Bool,
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
            HookContinuationState.record(
                prompt: continuation.reason,
                eventSummary: HookContinuationState.stopEventSummary,
                in: &activeThread
            )
            await onProgress?(activeThread)
            return try await runAgentTurn(
                prompt: continuation.reason,
                thread: activeThread,
                stopHookActive: true,
                subagentStopHookActive: subagentStopHookActive,
                onProgress: onProgress
            )
        }

        return try await runSubagentStopHooks(
            thread: activeThread,
            stopHookActive: subagentStopHookActive,
            onProgress: onProgress
        )
    }

}
