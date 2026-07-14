import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct ProjectRunHookExecutionFailure: Sendable, Equatable {
    var hook: ProjectRunHook
    var result: ToolResult
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
        onProgress: AgentRunProgressHandler?
    ) async throws -> ProjectRunHookExecutionFailure? {
        let matchingHooks = hooks.filter { $0.timing == timing }
        guard !matchingHooks.isEmpty else { return nil }

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
                    pluginDataBaseDirectory: pluginDataBaseDirectory
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

        var firstFailure: ProjectRunHookExecutionFailure?
        for outcome in outcomes.sorted(by: { $0.index < $1.index }) {
            WorkspaceToolEventRecorder.append(call: outcome.call, result: outcome.result, to: &thread)
            thread.updatedAt = Date()
            await onProgress?(thread)

            if !outcome.result.ok, firstFailure == nil {
                firstFailure = ProjectRunHookExecutionFailure(
                    hook: outcome.hook,
                    result: outcome.result
                )
            }
        }

        return firstFailure
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
}

private struct HookExecutionOutcome: Sendable {
    var index: Int
    var hook: ProjectRunHook
    var call: ToolCall
    var result: ToolResult
}
