import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct ProjectRunHookExecutionFailure: Sendable, Equatable {
    var hook: ProjectRunHook
    var result: ToolResult
}

struct ProjectRunHookControl: Sendable, Equatable {
    var hook: ProjectRunHook
    var reason: String
}

struct ProjectRunHookContext: Sendable, Equatable {
    var hook: ProjectRunHook
    var content: String
}

struct ProjectRunHookExecutionReport: Sendable, Equatable {
    var firstFailure: ProjectRunHookExecutionFailure?
    var contexts: [ProjectRunHookContext] = []
    var continueFalse: ProjectRunHookControl?
    var block: ProjectRunHookControl?
}

enum ProjectRunHookExecutor {
    static func run(
        timing: ProjectRunHookTiming,
        hooks: [ProjectRunHook],
        thread: inout ChatThread,
        prompt: String,
        workspaceRoot: URL,
        pluginDataBaseDirectory: URL?,
        selectedProject: ProjectRef?,
        sshRemoteShellExecutor: SSHRemoteShellExecutor,
        stopHookActive: Bool = false,
        onProgress: AgentRunProgressHandler?
    ) async throws -> ProjectRunHookExecutionReport {
        let matchingHooks = hooks.filter { $0.timing == timing }
        guard !matchingHooks.isEmpty else { return ProjectRunHookExecutionReport() }

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

        for hook in matchingHooks {
            try Task.checkCancellation()
            thread.events.append(ThreadEvent(
                kind: .notice,
                summary: "Running \(displayName(for: timing)) hook: \(hook.title)"
            ))
            thread.updatedAt = Date()
        }
        await onProgress?(thread)

        var outcomes: [HookExecutionOutcome] = []
        var invocations: [(Int, ProjectRunHookInvocation)] = []
        for (index, hook) in matchingHooks.enumerated() {
            do {
                invocations.append((index, try ProjectRunHookInvocationBuilder.build(
                    hook: hook,
                    thread: thread,
                    prompt: prompt,
                    workspaceRoot: workspaceRoot,
                    pluginDataBaseDirectory: pluginDataBaseDirectory,
                    stopHookActive: stopHookActive
                )))
            } catch {
                let call = WorkspaceShellToolCallPlanner.projectRunHook(
                    hook,
                    environment: hook.environment ?? [:],
                    standardInput: "{}\n"
                )
                outcomes.append(HookExecutionOutcome(
                    index: index,
                    hook: hook,
                    call: call,
                    result: ToolResult(ok: false, error: error.localizedDescription)
                ))
            }
        }

        let completed = await withTaskGroup(of: HookExecutionOutcome.self) { group in
            for (index, invocation) in invocations {
                group.addTask {
                    HookExecutionOutcome(
                        index: index,
                        hook: invocation.hook,
                        call: invocation.call,
                        result: executor.executePrimary(invocation.call)
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        outcomes.append(contentsOf: completed)

        var report = ProjectRunHookExecutionReport()
        var contextCharacters = 0
        for outcome in outcomes.sorted(by: { $0.index < $1.index }) {
            var recordedResult = outcome.result
            var semanticOutput: ProjectRunHookSemanticOutput?
            if outcome.hook.pluginID != nil,
               outcome.result.ok || outcome.result.exitCode == 2 {
                do {
                    semanticOutput = try ProjectRunHookOutputParser.parse(
                        timing: timing,
                        result: outcome.result
                    )
                    if outcome.result.exitCode == 2 {
                        recordedResult.ok = true
                        recordedResult.error = nil
                    }
                } catch {
                    recordedResult.ok = false
                    recordedResult.error = error.localizedDescription
                }
            }

            WorkspaceToolEventRecorder.append(call: outcome.call, result: recordedResult, to: &thread)
            thread.updatedAt = Date()
            if !recordedResult.ok, report.firstFailure == nil {
                report.firstFailure = ProjectRunHookExecutionFailure(
                    hook: outcome.hook,
                    result: recordedResult
                )
            }

            if let semanticOutput {
                if let message = semanticOutput.systemMessage {
                    thread.events.append(ThreadEvent(
                        kind: .notice,
                        summary: "Hook warning from \(outcome.hook.title): \(message)"
                    ))
                }
                if let context = semanticOutput.additionalContext,
                   contextCharacters < maximumAggregateContextCharacters {
                    let remaining = maximumAggregateContextCharacters - contextCharacters
                    let bounded = String(context.prefix(remaining))
                    if !bounded.isEmpty {
                        report.contexts.append(ProjectRunHookContext(
                            hook: outcome.hook,
                            content: bounded
                        ))
                        contextCharacters += bounded.count
                    }
                }
                if !semanticOutput.continues, report.continueFalse == nil {
                    report.continueFalse = ProjectRunHookControl(
                        hook: outcome.hook,
                        reason: semanticOutput.stopReason ?? "The hook stopped this run."
                    )
                }
                if let reason = semanticOutput.blockReason, report.block == nil {
                    report.block = ProjectRunHookControl(hook: outcome.hook, reason: reason)
                }
            }
            await onProgress?(thread)
        }

        return report
    }

    static func failureMessage(
        timing: ProjectRunHookTiming,
        failure: ProjectRunHookExecutionFailure
    ) -> String {
        let stage = timing == .beforeAgentRun ? "Before-run" : "After-run"
        let reason = failureSummary(from: failure.result)
        return "\(stage) hook failed: \(failure.hook.title). \(reason)"
    }

    private static func displayName(for timing: ProjectRunHookTiming) -> String {
        switch timing {
        case .beforeAgentRun:
            return "before-run"
        case .afterAgentRun:
            return "after-run"
        }
    }

    private static func failureSummary(from result: ToolResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        if let error = result.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return error
        }
        if let exitCode = result.exitCode {
            return "Exit code \(exitCode)."
        }
        return "Command failed."
    }

    private static let maximumAggregateContextCharacters = 65_536
}

private struct HookExecutionOutcome: Sendable {
    var index: Int
    var hook: ProjectRunHook
    var call: ToolCall
    var result: ToolResult
}
