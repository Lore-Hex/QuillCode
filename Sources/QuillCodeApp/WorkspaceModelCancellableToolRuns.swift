import Foundation
import QuillCodeCore

@MainActor
public extension QuillCodeWorkspaceModel {
    var activeCancellableToolRunCount: Int {
        activeCancellableToolRunThreadIDs.count
    }

    var activeCancellableToolRunIDs: Set<UUID> {
        activeCancellableToolRunThreadIDs
    }

    func isCancellableToolRunActive(for threadID: UUID?) -> Bool {
        threadID.map(activeCancellableToolRunThreadIDs.contains) ?? false
    }

    @discardableResult
    func runCancellableToolCall(
        _ call: ToolCall,
        workspaceRoot: URL,
        threadID: UUID? = nil,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async -> ToolResult? {
        await WorkspaceCancellableToolRunCoordinator(model: self).run(
            call,
            workspaceRoot: workspaceRoot,
            threadID: threadID,
            onProgressUpdated: onProgressUpdated
        )
    }
}
