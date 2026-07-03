import XCTest

final class ParityWorkspaceSidebarRowActionGateTests: QuillCodeParityTestCase {
    func testSidebarRowActionsUseSharedPlannerAndExecutor() throws {
        let workspaceViewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSidebarRowActionPlanner.swift")
        let desktopControllerText = try Self.desktopControllerSourceText()
        let desktopNavigationText = try Self.desktopSourceText(
            named: "QuillCodeDesktopNavigationCoordinator.swift"
        )

        Self.assertSource(plannerText, contains: "enum WorkspaceThreadRowMutation")
        Self.assertSource(plannerText, contains: "enum WorkspaceProjectRowMutation")
        Self.assertSource(plannerText, contains: "struct WorkspaceSidebarRowActionPlanner")
        Self.assertSource(plannerText, contains: "struct WorkspaceSidebarRowMutationExecutor")
        Self.assertSource(workspaceViewText, contains: "WorkspaceSidebarRowActionPlanner(")
        Self.assertSource(workspaceViewText, contains: "handleSidebarRowAction")
        Self.assertSource(desktopNavigationText, contains: "WorkspaceSidebarRowMutationExecutor.execute")

        Self.assertSource(workspaceViewText, excludes: "action.kind == .rename")
        Self.assertSource(workspaceViewText, excludes: "surface.sidebar.items.first(where:")
        Self.assertSource(workspaceViewText, excludes: "surface.projects.items.first(where:")
        Self.assertSource(desktopControllerText, excludes: "WorkspaceSidebarRowMutationExecutor.execute")
        Self.assertSource(desktopControllerText, excludes: "switch action.kind")
    }
}
