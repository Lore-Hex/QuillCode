import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct ProjectPluginToolHookExecutor: Sendable {
    static let maximumAggregateContextCharacters = 65_536

    var hooks: [ProjectPluginHook]
    var pluginDataBaseDirectory: URL?
    var selectedProject: ProjectRef?
    var sshRemoteShellExecutor: SSHRemoteShellExecutor

    var preToolUseHook: AgentPreToolUseHook? {
        guard hasExecutableHook(for: .preToolUse) else { return nil }
        return { call, thread, workspaceRoot in
            try await runPreToolUse(call: call, thread: thread, workspaceRoot: workspaceRoot)
        }
    }

    var postToolUseHook: AgentPostToolUseHook? {
        guard hasExecutableHook(for: .postToolUse) else { return nil }
        return { call, result, thread, workspaceRoot in
            try await runPostToolUse(
                call: call,
                result: result,
                thread: thread,
                workspaceRoot: workspaceRoot
            )
        }
    }

    var permissionRequestHook: AgentPermissionRequestHook? {
        guard hasExecutableHook(for: .permissionRequest) else { return nil }
        return { call, approvalReason, thread, workspaceRoot in
            try await runPermissionRequest(
                call: call,
                approvalReason: approvalReason,
                thread: thread,
                workspaceRoot: workspaceRoot
            )
        }
    }

    func runPreToolUse(
        call: ToolCall,
        thread: ChatThread,
        workspaceRoot: URL
    ) async throws -> AgentPreToolUseHookOutcome {
        guard let adapter = ProjectPluginToolCallAdapter.make(for: call) else {
            return AgentPreToolUseHookOutcome(call: call)
        }
        let outcomes = await execute(
            event: .preToolUse,
            adapter: adapter,
            result: nil,
            thread: thread,
            workspaceRoot: workspaceRoot
        )

        var effectiveCall = call
        var blockedReason: String?
        var contexts: [String] = []
        var notices: [String] = []
        var contextCharacters = 0
        var acceptedRewrite = false

        for outcome in outcomes {
            guard let semantic = outcome.semantic else {
                if let failure = outcome.failure {
                    notices.append(failureNotice(outcome.hook, event: .preToolUse, failure: failure))
                }
                continue
            }
            appendCommonEffects(
                semantic,
                hook: outcome.hook,
                contexts: &contexts,
                notices: &notices,
                contextCharacters: &contextCharacters
            )
            if semantic.decision == .deny, blockedReason == nil {
                blockedReason = semantic.decisionReason ?? "The hook blocked this tool call."
            }
            if let updatedInputJSON = semantic.updatedInputJSON {
                guard !acceptedRewrite else {
                    notices.append("Ignored another tool rewrite from \(outcome.hook.pluginName).")
                    continue
                }
                do {
                    effectiveCall = try adapter.replacingToolInput(with: updatedInputJSON)
                    acceptedRewrite = true
                } catch {
                    notices.append(failureNotice(
                        outcome.hook,
                        event: .preToolUse,
                        failure: error.localizedDescription
                    ))
                }
            }
        }

        return AgentPreToolUseHookOutcome(
            call: effectiveCall,
            blockedReason: blockedReason,
            additionalContexts: contexts,
            notices: notices
        )
    }

    func runPostToolUse(
        call: ToolCall,
        result: ToolResult,
        thread: ChatThread,
        workspaceRoot: URL
    ) async throws -> AgentPostToolUseHookOutcome {
        guard let adapter = ProjectPluginToolCallAdapter.make(for: call) else {
            return AgentPostToolUseHookOutcome(result: result)
        }
        let outcomes = await execute(
            event: .postToolUse,
            adapter: adapter,
            result: result,
            thread: thread,
            workspaceRoot: workspaceRoot
        )

        var effectiveResult = result
        var contexts: [String] = []
        var notices: [String] = []
        var contextCharacters = 0
        var replacedFeedback = false

        for outcome in outcomes {
            guard let semantic = outcome.semantic else {
                if let failure = outcome.failure {
                    notices.append(failureNotice(outcome.hook, event: .postToolUse, failure: failure))
                }
                continue
            }
            appendCommonEffects(
                semantic,
                hook: outcome.hook,
                contexts: &contexts,
                notices: &notices,
                contextCharacters: &contextCharacters
            )
            if let feedback = semantic.replacementFeedback, !replacedFeedback {
                effectiveResult.stdout = feedback
                effectiveResult.stderr = ""
                effectiveResult.error = result.ok ? nil : feedback
                replacedFeedback = true
            }
        }

        return AgentPostToolUseHookOutcome(
            result: effectiveResult,
            additionalContexts: contexts,
            notices: notices
        )
    }

    func runPermissionRequest(
        call: ToolCall,
        approvalReason: String,
        thread: ChatThread,
        workspaceRoot: URL
    ) async throws -> AgentPermissionRequestHookOutcome {
        guard let adapter = ProjectPluginToolCallAdapter.make(for: call) else {
            return AgentPermissionRequestHookOutcome()
        }
        let outcomes = await execute(
            event: .permissionRequest,
            adapter: adapter,
            result: nil,
            approvalReason: approvalReason,
            thread: thread,
            workspaceRoot: workspaceRoot
        )

        var allowed = false
        var denialReason: String?
        var notices: [String] = []
        for outcome in outcomes {
            guard let semantic = outcome.semantic else {
                if let failure = outcome.failure {
                    notices.append(failureNotice(
                        outcome.hook,
                        event: .permissionRequest,
                        failure: failure
                    ))
                }
                continue
            }
            if let message = semantic.systemMessage {
                notices.append("Hook warning from \(outcome.hook.pluginName): \(message)")
            }
            switch semantic.decision {
            case .allow:
                allowed = true
                notices.append(
                    "Permission hook from \(outcome.hook.pluginName) allowed \(adapter.canonicalName)."
                )
            case .deny:
                notices.append(
                    "Permission hook from \(outcome.hook.pluginName) denied \(adapter.canonicalName)."
                )
                if denialReason == nil {
                    denialReason = semantic.decisionReason
                        ?? "The permission hook denied this tool call."
                }
            case nil:
                break
            }
        }

        let decision: AgentPermissionRequestDecision
        if let denialReason {
            decision = .deny(reason: denialReason)
        } else if allowed {
            decision = .allow
        } else {
            decision = .noDecision
        }
        return AgentPermissionRequestHookOutcome(decision: decision, notices: notices)
    }

    private func execute(
        event: ProjectPluginToolHookEvent,
        adapter: ProjectPluginToolCallAdapter,
        result: ToolResult?,
        approvalReason: String? = nil,
        thread: ChatThread,
        workspaceRoot: URL
    ) async -> [ProjectPluginToolHookOutcome] {
        let matching = hooks.filter {
            $0.isExecutable && $0.event == event.rawValue && adapter.matches($0.matcher)
        }
        guard !matching.isEmpty else { return [] }

        let executor = WorkspaceToolCallExecutor(
            selectedProject: selectedProject,
            browser: BrowserState(),
            browserDomainPolicy: .unrestricted,
            router: ToolRouter(
                workspaceRoot: workspaceRoot,
                editGuard: .session(for: thread.id)
            ),
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
        var immediate: [ProjectPluginToolHookOutcome] = []
        var invocations: [(Int, ProjectPluginToolHookInvocation)] = []
        for (index, hook) in matching.enumerated() {
            do {
                invocations.append((index, try ProjectPluginToolHookInvocationBuilder.build(
                    hook: hook,
                    event: event,
                    adapter: adapter,
                    toolResult: result,
                    approvalReason: approvalReason,
                    thread: thread,
                    workspaceRoot: workspaceRoot,
                    pluginDataBaseDirectory: pluginDataBaseDirectory
                )))
            } catch {
                immediate.append(ProjectPluginToolHookOutcome(
                    index: index,
                    hook: hook,
                    semantic: nil,
                    failure: error.localizedDescription
                ))
            }
        }

        let completed = await withTaskGroup(of: ProjectPluginToolHookOutcome.self) { group in
            for (index, invocation) in invocations {
                group.addTask {
                    let result = executor.executePrimary(invocation.call)
                    do {
                        if !result.ok && !(event.treatsExitTwoAsDecision && result.exitCode == 2) {
                            throw ProjectPluginToolHookExecutionError.commandFailed(
                                ProjectHookCommandFailureSummary.make(from: result)
                            )
                        }
                        let semantic = try ProjectPluginToolHookOutputParser.parse(
                            event: event,
                            result: result
                        )
                        return ProjectPluginToolHookOutcome(
                            index: index,
                            hook: invocation.hook,
                            semantic: semantic,
                            failure: nil
                        )
                    } catch {
                        return ProjectPluginToolHookOutcome(
                            index: index,
                            hook: invocation.hook,
                            semantic: nil,
                            failure: error.localizedDescription
                        )
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        return (immediate + completed).sorted { $0.index < $1.index }
    }

    private func hasExecutableHook(for event: ProjectPluginToolHookEvent) -> Bool {
        hooks.contains { $0.isExecutable && $0.event == event.rawValue }
    }

    private func appendCommonEffects(
        _ semantic: ProjectPluginToolHookSemanticOutput,
        hook: ProjectPluginHook,
        contexts: inout [String],
        notices: inout [String],
        contextCharacters: inout Int
    ) {
        if let message = semantic.systemMessage {
            notices.append("Hook warning from \(hook.pluginName): \(message)")
        }
        guard let context = semantic.additionalContext,
              contextCharacters < Self.maximumAggregateContextCharacters
        else { return }
        let heading = "Standard plugin hook context from \(hook.pluginName):\n"
        let remaining = max(0, Self.maximumAggregateContextCharacters - contextCharacters - heading.count)
        let bounded = String(context.prefix(remaining))
        guard !bounded.isEmpty else { return }
        let entry = heading + bounded
        contexts.append(entry)
        contextCharacters += entry.count
    }

    private func failureNotice(
        _ hook: ProjectPluginHook,
        event: ProjectPluginToolHookEvent,
        failure: String
    ) -> String {
        let fallback = event == .permissionRequest
            ? "Normal approval is still required."
            : "The original tool call continued."
        return "Hook warning from \(hook.pluginName): \(failure) \(fallback)"
    }

}

private struct ProjectPluginToolHookOutcome: Sendable {
    var index: Int
    var hook: ProjectPluginHook
    var semantic: ProjectPluginToolHookSemanticOutput?
    var failure: String?
}

private enum ProjectPluginToolHookExecutionError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        }
    }
}
