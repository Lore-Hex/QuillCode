import Foundation
import QuillCodeCore

@MainActor
public extension QuillCodeWorkspaceModel {
    @discardableResult
    func runToolCall(_ call: ToolCall, workspaceRoot: URL) -> ToolResult {
        WorkspaceToolRunCoordinator(model: self, workspaceRoot: workspaceRoot).run(call)
    }
}
