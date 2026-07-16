import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeHooks
import QuillCodeTools

struct ProjectPluginCompactionHookExecutor: Sendable {
    var hooks: [ProjectPluginHook]
    var pluginDataBaseDirectory: URL?
    var selectedProject: ProjectRef?
    var sshRemoteShellExecutor: SSHRemoteShellExecutor

    var preCompactHook: AgentCompactionHook? {
        guard hasExecutableHook(for: .preCompact) else { return nil }
        return { trigger, thread, workspaceRoot in
            await run(
                event: .preCompact,
                trigger: trigger,
                thread: thread,
                workspaceRoot: workspaceRoot
            )
        }
    }

    var postCompactHook: AgentCompactionHook? {
        guard hasExecutableHook(for: .postCompact) else { return nil }
        return { trigger, thread, workspaceRoot in
            await run(
                event: .postCompact,
                trigger: trigger,
                thread: thread,
                workspaceRoot: workspaceRoot
            )
        }
    }

    var hasExecutableHooks: Bool {
        hasExecutableHook(for: .preCompact) || hasExecutableHook(for: .postCompact)
    }

    func run(
        event: ProjectPluginCompactionHookEvent,
        trigger: AgentCompactionTrigger,
        thread: ChatThread,
        workspaceRoot: URL
    ) async -> AgentCompactionHookOutcome {
        let outcomes = await execute(
            event: event,
            trigger: trigger,
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        var continues = true
        var stopReason: String?
        var notices: [String] = []
        for outcome in outcomes {
            guard let semantic = outcome.semantic else {
                if let failure = outcome.failure {
                    notices.append(
                        "Hook warning from \(outcome.hook.pluginName): \(failure) Compaction continued."
                    )
                }
                continue
            }
            if let message = semantic.systemMessage {
                notices.append("Hook warning from \(outcome.hook.pluginName): \(message)")
            }
            if !semantic.continues {
                continues = false
                if stopReason == nil {
                    stopReason = semantic.stopReason
                        ?? "A compaction hook from \(outcome.hook.pluginName) stopped this operation."
                }
            }
        }
        return AgentCompactionHookOutcome(
            continues: continues,
            stopReason: stopReason,
            notices: notices
        )
    }

    private func execute(
        event: ProjectPluginCompactionHookEvent,
        trigger: AgentCompactionTrigger,
        thread: ChatThread,
        workspaceRoot: URL
    ) async -> [ProjectPluginCompactionHookExecutionOutcome] {
        let matching = hooks.filter {
            $0.isExecutable
                && $0.event == event.rawValue
                && ProjectPluginHookMatcher.matches($0.matcher, candidates: [trigger.rawValue])
        }
        guard !matching.isEmpty else { return [] }

        var immediate: [ProjectPluginCompactionHookExecutionOutcome] = []
        var invocations: [(Int, ProjectPluginCompactionHookInvocation)] = []
        for (index, hook) in matching.enumerated() {
            do {
                invocations.append((index, try ProjectPluginCompactionHookInvocationBuilder.build(
                    hook: hook,
                    event: event,
                    trigger: trigger,
                    thread: thread,
                    workspaceRoot: workspaceRoot,
                    pluginDataBaseDirectory: pluginDataBaseDirectory
                )))
            } catch {
                immediate.append(ProjectPluginCompactionHookExecutionOutcome(
                    index: index,
                    hook: hook,
                    semantic: nil,
                    failure: error.localizedDescription
                ))
            }
        }

        let completed = await withTaskGroup(of: ProjectPluginCompactionHookExecutionOutcome.self) { group in
            for (index, invocation) in invocations {
                group.addTask {
                    let executor = WorkspaceToolCallExecutor(
                        selectedProject: ProjectHookExecutionRouting.selectedProject(
                            for: invocation.hook.effectiveTrustScope,
                            selectedProject: selectedProject
                        ),
                        browser: BrowserState(),
                        browserDomainPolicy: .unrestricted,
                        router: ToolRouter(
                            workspaceRoot: workspaceRoot,
                            editGuard: .session(for: thread.id)
                        ),
                        sshRemoteShellExecutor: sshRemoteShellExecutor
                    )
                    let result = executor.executePrimary(invocation.call)
                    do {
                        guard result.ok else {
                            throw ProjectPluginCompactionHookExecutionError.commandFailed(
                                ProjectHookCommandFailureSummary.make(from: result)
                            )
                        }
                        return ProjectPluginCompactionHookExecutionOutcome(
                            index: index,
                            hook: invocation.hook,
                            semantic: try ProjectPluginCompactionHookOutputParser.parse(result),
                            failure: nil
                        )
                    } catch {
                        return ProjectPluginCompactionHookExecutionOutcome(
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

    private func hasExecutableHook(for event: ProjectPluginCompactionHookEvent) -> Bool {
        hooks.contains { $0.isExecutable && $0.event == event.rawValue }
    }
}

private struct ProjectPluginCompactionHookExecutionOutcome: Sendable {
    var index: Int
    var hook: ProjectPluginHook
    var semantic: ProjectPluginCompactionHookSemanticOutput?
    var failure: String?
}

private enum ProjectPluginCompactionHookExecutionError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        }
    }
}
