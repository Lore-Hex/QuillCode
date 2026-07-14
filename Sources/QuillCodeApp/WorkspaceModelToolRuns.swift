import Foundation
import QuillCodeCore

@MainActor
public extension QuillCodeWorkspaceModel {
    @discardableResult
    func runToolCall(
        _ call: ToolCall,
        workspaceRoot: URL,
        managedWorktreeRoot: URL? = nil
    ) -> ToolResult {
        WorkspaceToolRunCoordinator(
            model: self,
            workspaceRoot: workspaceRoot,
            managedWorktreeRoot: managedWorktreeRoot
        ).run(call)
    }
}
