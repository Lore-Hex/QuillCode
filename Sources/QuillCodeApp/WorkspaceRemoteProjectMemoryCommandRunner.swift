import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteProjectMemoryCommandRunner {
    static func run(
        _ command: String,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor,
        failure: (String) -> WorkspaceRemoteProjectMemoryUpdateError
    ) throws {
        guard let request = executor.request(command: command, connection: connection) else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidConnection
        }

        let result = ShellToolExecutor().run(request)
        guard result.ok else {
            throw failure(errorMessage(from: result))
        }
    }

    private static func errorMessage(from result: ToolResult) -> String {
        result.error
            ?? [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
            ?? "Remote project memory command failed."
    }
}
