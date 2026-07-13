import Foundation
import QuillCodeCore

@MainActor
public extension QuillCodeWorkspaceModel {
    @discardableResult
    func runToolCall(_ call: ToolCall, workspaceRoot: URL) -> ToolResult {
        WorkspaceToolRunCoordinator(model: self, workspaceRoot: workspaceRoot).run(call)
    }

    @discardableResult
    func runToolCall(
        _ call: ToolCall,
        workspaceRoot: URL,
        primaryExecution: @escaping () -> ToolResult
    ) -> ToolResult {
        WorkspaceToolRunCoordinator(model: self, workspaceRoot: workspaceRoot).run(
            call,
            primaryExecution: primaryExecution
        )
    }
}
