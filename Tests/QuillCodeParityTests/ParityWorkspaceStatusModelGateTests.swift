import XCTest

final class ParityWorkspaceStatusModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesStatusTextAndLabels() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceStatusTextBuilder.swift")
        let contextBuilderText = try Self.appSourceText(named: "WorkspaceStatusContextBuilder.swift")
        let topBarBuilderText = try Self.appSourceText(named: "WorkspaceTopBarSurfaceBuilder.swift")
        let topBarStateBuilderText = try Self.appSourceText(named: "WorkspaceTopBarStateBuilder.swift")
        let slashTranscriptText = try Self.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")

        Self.assertSource(builderText, containsAll: [
            "struct WorkspaceStatusTextBuilder",
            "static func statusText",
            "static func topBarSubtitle",
            "static func instructionLabel",
            "static func memoryLabel",
            "static func modeLabel"
        ])
        Self.assertSource(contextBuilderText, containsAll: [
            "enum WorkspaceStatusContextBuilder",
            "static func context"
        ])
        Self.assertSource(composerText, containsAll: [
            "WorkspaceStatusTextBuilder.statusText",
            "WorkspaceStatusContextBuilder.context"
        ])
        Self.assertSource(slashTranscriptText, contains: "WorkspaceStatusTextBuilder.modeLabel")
        Self.assertSource(topBarBuilderText, containsAll: [
            "WorkspaceStatusTextBuilder.topBarSubtitle",
            "WorkspaceStatusTextBuilder.instructionLabel",
            "WorkspaceStatusTextBuilder.memoryLabel"
        ])
        Self.assertSource(topBarStateBuilderText, contains: "enum WorkspaceTopBarStateBuilder")
        Self.assertSource(modelText, contains: "WorkspaceTopBarStateBuilder.state")
        Self.assertSource(modelText, excludesAll: [
            "root.topBar = TopBarState(",
            "WorkspaceStatusContext(",
            "WorkspaceStatusTextBuilder.statusText",
            "No project instructions",
            "No memories",
            "static func instructionStatusLabel",
            "static func memoryStatusLabel"
        ])
        Self.assertSource(surfaceText, excludesAll: [
            "WorkspaceStatusTextBuilder.topBarSubtitle",
            "WorkspaceStatusTextBuilder.instructionLabel",
            "WorkspaceStatusTextBuilder.memoryLabel",
            "static func modeLabel"
        ])
    }
}
