import XCTest

final class ParityWorkspaceStatusModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesStatusTextAndLabels() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceStatusTextBuilder.swift")
        let contextText = try Self.appSourceText(named: "WorkspaceStatusContextBuilder.swift")
        let topBarText = try Self.appSourceText(named: "WorkspaceTopBarSurfaceBuilder.swift")
        let topBarStateText = try Self.appSourceText(named: "WorkspaceTopBarStateBuilder.swift")
        let slashTranscriptText = try Self.appSourceText(
            named: "WorkspaceSlashCommandTranscriptPlanner.swift"
        )

        Self.assertSource(builderText, containsAll: [
            "struct WorkspaceStatusTextBuilder",
            "static func statusText",
            "static func topBarSubtitle",
            "static func instructionLabel",
            "static func memoryLabel",
            "static func modeLabel"
        ])
        Self.assertSource(contextText, containsAll: [
            "enum WorkspaceStatusContextBuilder",
            "static func context"
        ])
        Self.assertSource(topBarText, containsAll: [
            "WorkspaceStatusTextBuilder.topBarSubtitle",
            "WorkspaceStatusTextBuilder.instructionLabel",
            "WorkspaceStatusTextBuilder.memoryLabel"
        ])
        Self.assertSource(composerText, containsAll: [
            "WorkspaceStatusTextBuilder.statusText",
            "WorkspaceStatusContextBuilder.context"
        ])
        Self.assertSource(topBarStateText, contains: "enum WorkspaceTopBarStateBuilder")
        Self.assertSource(modelText, contains: "WorkspaceTopBarStateBuilder.state")
        Self.assertSource(slashTranscriptText, contains: "WorkspaceStatusTextBuilder.modeLabel")

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

    func testWorkspaceModelDelegatesAgentProgressStatusCopy() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentStatusBuilder.swift")
        let progressText = try Self.appSourceText(
            named: "WorkspaceAgentSendProgressPlanner.swift"
        )

        Self.assertSource(builderText, containsAll: [
            "struct WorkspaceAgentStatusBuilder",
            "static func status(for thread: ChatThread)",
            "static func status(for event: ThreadEvent?)",
            "AgentRunner.streamingNotice"
        ])
        Self.assertSource(progressText, containsAll: [
            "struct WorkspaceAgentSendProgressPlan",
            "enum WorkspaceAgentSendProgressPlanner",
            "WorkspaceAgentStatusBuilder.status(for: thread)"
        ])
        Self.assertSource(composerText, contains: "WorkspaceAgentSendProgressPlanner.progress")
        Self.assertSource(modelText, excludesAll: [
            "private func agentStatus",
            "WorkspaceAgentStatusBuilder.status(for: thread)",
            "case .toolQueued:",
            "AgentRunner.streamingNotice"
        ])
    }
}
