import Foundation
import QuillCodeCore

/// Cline learning #2 (docs/CLINE_TOOL_LEARNINGS.md): graded loop detection. Cline warns at three
/// identical calls and stops at five; QuillCode used to finalize on the very first repeat, turning
/// a recoverable moment into a terminal answer — the F25 incident was exactly that shape.
///
/// The nudge hands the model the result it already has, so a repeat caused by "I didn't see the
/// output" resolves immediately, and names the two legitimate ways forward.
enum AgentRepeatedCallGuard {
    /// Keeps the echoed result small: the point is to remind, not to re-dump a large payload.
    static let resultEchoLimit = 1024

    static func softWarning(call: ToolCall, previousResult: ToolResult) -> String {
        let output = [previousResult.stdout, previousResult.stderr, previousResult.error ?? ""]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let echoed = output.count > resultEchoLimit
            ? String(output.prefix(resultEchoLimit)) + "\n[truncated]"
            : output
        return """
        You just requested \(call.name) with exactly the same arguments as the previous step. Here \
        is the result you already have:

        \(echoed.isEmpty ? "(the call produced no output)" : echoed)

        Do not repeat that call. Either take a DIFFERENT next step that moves the task forward, or, \
        if the task is complete, give your final answer now. If the previous call failed and you \
        believe retrying will help, change something about it first and say what you changed.
        """
    }
}
