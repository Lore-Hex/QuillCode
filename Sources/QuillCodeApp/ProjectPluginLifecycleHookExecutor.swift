import Foundation
import QuillCodeCore
import QuillCodeTools

struct ProjectPluginLifecycleHookExecutor: Sendable {
    var hooks: [ProjectPluginHook]
    var pluginDataBaseDirectory: URL?
    var selectedProject: ProjectRef?
    var sshRemoteShellExecutor: SSHRemoteShellExecutor

    var hasExecutableHooks: Bool {
        hooks.contains { hook in
            hook.isExecutable && Self.supportedEvents.contains(hook.event)
        }
    }

    func run(
        event: ProjectPluginLifecycleHookEvent,
        sessionThread: ChatThread,
        workspaceRoot: URL
    ) async -> ProjectPluginLifecycleHookReport {
        let outcomes = await execute(
            event: event,
            sessionThread: sessionThread,
            workspaceRoot: workspaceRoot
        )
        var report = ProjectPluginLifecycleHookReport()
        var contextCharacters = 0
        for outcome in outcomes {
            guard let semantic = outcome.semantic else {
                if let failure = outcome.failure {
                    report.notices.append(
                        "Hook warning from \(outcome.hook.pluginName): \(failure) The session continued."
                    )
                }
                continue
            }
            if let message = semantic.systemMessage {
                report.notices.append("Hook warning from \(outcome.hook.pluginName): \(message)")
            }
            if let context = semantic.additionalContext,
               contextCharacters < Self.maximumAggregateContextCharacters {
                let remaining = Self.maximumAggregateContextCharacters - contextCharacters
                let bounded = String(context.prefix(remaining))
                if !bounded.isEmpty {
                    report.contexts.append(ProjectPluginLifecycleHookContext(
                        hook: outcome.hook,
                        content: bounded
                    ))
                    contextCharacters += bounded.count
                }
            }
            if !event.ignoresContinueFalse, !semantic.continues {
                report.continues = false
                if report.stopReason == nil {
                    report.stopReason = semantic.stopReason
                        ?? "A lifecycle hook from \(outcome.hook.pluginName) stopped this run."
                }
            }
            if report.continuationReason == nil {
                report.continuationReason = semantic.continuationReason
            }
        }
        if !report.continues {
            report.continuationReason = nil
        }
        return report
    }

    private func execute(
        event: ProjectPluginLifecycleHookEvent,
        sessionThread: ChatThread,
        workspaceRoot: URL
    ) async -> [ProjectPluginLifecycleHookExecutionOutcome] {
        let matching = hooks.filter {
            $0.isExecutable
                && $0.event == event.name
                && ProjectPluginHookMatcher.matches($0.matcher, candidates: [event.matcherCandidate])
        }
        guard !matching.isEmpty else { return [] }

        var immediate: [ProjectPluginLifecycleHookExecutionOutcome] = []
        var invocations: [(Int, ProjectPluginLifecycleHookInvocation)] = []
        for (index, hook) in matching.enumerated() {
            do {
                invocations.append((index, try ProjectPluginLifecycleHookInvocationBuilder.build(
                    hook: hook,
                    event: event,
                    sessionThread: sessionThread,
                    workspaceRoot: workspaceRoot,
                    pluginDataBaseDirectory: pluginDataBaseDirectory
                )))
            } catch {
                immediate.append(ProjectPluginLifecycleHookExecutionOutcome(
                    index: index,
                    hook: hook,
                    semantic: nil,
                    failure: error.localizedDescription
                ))
            }
        }

        let completed = await withTaskGroup(of: ProjectPluginLifecycleHookExecutionOutcome.self) { group in
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
                            editGuard: .session(for: sessionThread.id)
                        ),
                        sshRemoteShellExecutor: sshRemoteShellExecutor
                    )
                    let result = executor.executePrimary(invocation.call)
                    do {
                        let acceptsExitTwo: Bool
                        if case .subagentStop = event {
                            acceptsExitTwo = result.exitCode == 2
                        } else {
                            acceptsExitTwo = false
                        }
                        guard result.ok || acceptsExitTwo else {
                            throw ProjectPluginLifecycleHookExecutionError.commandFailed(
                                ProjectHookCommandFailureSummary.make(from: result)
                            )
                        }
                        return ProjectPluginLifecycleHookExecutionOutcome(
                            index: index,
                            hook: invocation.hook,
                            semantic: try ProjectPluginLifecycleHookOutputParser.parse(
                                event: event,
                                result: result
                            ),
                            failure: nil
                        )
                    } catch {
                        return ProjectPluginLifecycleHookExecutionOutcome(
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

    private static let supportedEvents: Set<String> = [
        "SessionStart", "SubagentStart", "SubagentStop"
    ]
    private static let maximumAggregateContextCharacters = 65_536
}

private struct ProjectPluginLifecycleHookExecutionOutcome: Sendable {
    var index: Int
    var hook: ProjectPluginHook
    var semantic: ProjectPluginLifecycleHookSemanticOutput?
    var failure: String?
}

private enum ProjectPluginLifecycleHookExecutionError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message
        }
    }
}
