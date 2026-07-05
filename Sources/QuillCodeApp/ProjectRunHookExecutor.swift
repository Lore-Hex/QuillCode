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
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> ProjectRunHookExecutionFailure? {
        let matchingHooks = hooks.filter { $0.timing == timing }
        guard !matchingHooks.isEmpty else { return nil }

        let router = ToolRouter(
            workspaceRoot: workspaceRoot,
            editGuard: .session(for: thread.id)
        )

        for hook in matchingHooks {
            try Task.checkCancellation()
            thread.events.append(ThreadEvent(
                kind: .notice,
                summary: "Running \(displayName(for: timing)) hook: \(hook.title)"
            ))
            thread.updatedAt = Date()
            await onProgress?(thread)

            let call = WorkspaceShellToolCallPlanner.projectRunHook(hook)
            let result = router.execute(call)
            WorkspaceToolEventRecorder.append(call: call, result: result, to: &thread)
            thread.updatedAt = Date()
            await onProgress?(thread)

            guard result.ok else {
                return ProjectRunHookExecutionFailure(hook: hook, result: result)
            }
        }

        return nil
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
