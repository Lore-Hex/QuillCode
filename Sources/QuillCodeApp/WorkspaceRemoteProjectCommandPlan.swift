import Foundation
import QuillCodeCore

struct WorkspaceRemoteProjectCommandPlan: Sendable {
    var command: String
    var connection: ProjectConnection
    var timeoutSeconds: TimeInterval
    private let transform: @Sendable (ToolResult) -> ToolResult

    init(
        command: String,
        connection: ProjectConnection,
        timeoutSeconds: TimeInterval = 60,
        transform: @escaping @Sendable (ToolResult) -> ToolResult = { $0 }
    ) {
        self.command = command
        self.connection = connection
        self.timeoutSeconds = timeoutSeconds
        self.transform = transform
    }

    func finalize(_ result: ToolResult) -> ToolResult {
        transform(result)
    }
}
