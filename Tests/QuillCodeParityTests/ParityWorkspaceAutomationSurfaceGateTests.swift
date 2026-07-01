import XCTest

final class ParityWorkspaceAutomationSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesAutomationsSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAutomationsSurfaceBuilder.swift")

        Self.assertSource(builderText, containsAll: [
            "struct WorkspaceAutomationsSurfaceBuilder",
            "func surface() -> WorkspaceAutomationsSurface",
            "hasSelectedThread",
            "hasSelectedProject"
        ])
        Self.assertSource(surfaceText, contains: "WorkspaceAutomationsSurfaceBuilder(")
        Self.assertSource(surfaceText, excludesAll: [
            "automationCreateThreadFollowUp",
            "automationCreateWorkspaceSchedule",
            "automationScheduleThreadFollowUpCommands",
            "automationScheduleWorkspaceScheduleCommands"
        ])
    }
}
