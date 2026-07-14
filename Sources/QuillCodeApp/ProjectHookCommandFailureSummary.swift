import Foundation
import QuillCodeCore

enum ProjectHookCommandFailureSummary {
    static func make(from result: ToolResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        if let error = result.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            return error
        }
        if let exitCode = result.exitCode { return "Exit code \(exitCode)." }
        return "Command failed."
    }
}
