import XCTest

final class ParityWorkspaceSidebarGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesSidebarSelectionTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadExtensionText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let sidebarModelText = try Self.appSourceText(named: "WorkspaceModelSidebar.swift")
        let threadMutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let selectionText = try Self.appSourceText(named: "WorkspaceSidebarSelectionEngine.swift")
        let bulkPlannerText = try Self.appSourceText(named: "WorkspaceSidebarBulkActionPlanner.swift")
        let bulkExecutorText = try Self.appSourceText(named: "WorkspaceSidebarBulkActionExecutor.swift")

        Self.assertSource(selectionText, contains: "public struct SidebarSelectionState")
        Self.assertSource(selectionText, contains: "struct WorkspaceSidebarSelectionEngine")
        Self.assertSource(selectionText, contains: "static func start")
        Self.assertSource(selectionText, contains: "static func selectAll")
        Self.assertSource(selectionText, contains: "static func toggle")
        Self.assertSource(selectionText, contains: "static func resolve")

        Self.assertSource(sidebarModelText, contains: "WorkspaceSidebarSelectionEngine.start")
        Self.assertSource(sidebarModelText, contains: "WorkspaceSidebarSelectionEngine.selectAll")
        Self.assertSource(sidebarModelText, contains: "WorkspaceSidebarSelectionEngine.toggle")
        Self.assertSource(sidebarModelText, contains: "setSidebarFilter")
        Self.assertSource(sidebarModelText, contains: "clearSidebarSelection()")

        Self.assertSource(threadMutationText, contains: "WorkspaceSidebarSelectionEngine.resolve")
        Self.assertSource(threadMutationText, contains: "func filteredSidebarItems")
        Self.assertSource(threadMutationText, contains: "sidebarFilter.includes")

        Self.assertSource(bulkPlannerText, contains: "struct WorkspaceSidebarBulkActionPlanner")
        Self.assertSource(bulkPlannerText, contains: "static func plan")
        Self.assertSource(bulkPlannerText, contains: "enum FollowUpSelection")
        Self.assertSource(sidebarModelText, contains: "WorkspaceSidebarBulkActionPlanner.plan")

        Self.assertSource(bulkExecutorText, contains: "struct WorkspaceSidebarBulkActionExecutor")
        Self.assertSource(bulkExecutorText, contains: "static func execute")
        Self.assertSource(sidebarModelText, contains: "WorkspaceSidebarBulkActionExecutor.execute")

        Self.assertSource(threadExtensionText, excludes: "public func startSidebarSelection")
        Self.assertSource(threadExtensionText, excludes: "public func performSidebarBulkAction")
        Self.assertSource(threadExtensionText, excludes: "setSidebarFilter")

        Self.assertSource(modelText, excludes: "public func startSidebarSelection")
        Self.assertSource(modelText, excludes: "public func performSidebarBulkAction")
        Self.assertSource(modelText, excludes: "public struct SidebarSelectionState")
        Self.assertSource(modelText, excludes: "selectedThreadIDs.insert")
        Self.assertSource(modelText, excludes: "selectedThreadIDs.remove")
        Self.assertSource(modelText, excludes: "selectedThreadIDs.intersection")
        Self.assertSource(modelText, excludes: "WorkspaceSidebarSelectionEngine.resolve")
        Self.assertSource(modelText, excludes: "let ids = selectedSidebarThreadIDs()")
        Self.assertSource(modelText, excludes: "case .pin(let ids):")
        Self.assertSource(modelText, excludes: "WorkspaceThreadLifecycleEngine.archiveThreads")
        Self.assertSource(modelText, excludes: "WorkspaceThreadLifecycleEngine.unarchiveThreads")
        Self.assertSource(modelText, excludes: "WorkspaceThreadLifecycleEngine.deleteThreads")
    }
}
