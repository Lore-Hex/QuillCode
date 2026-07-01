import XCTest

final class ParityWorkspaceUIStateModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesUIStateContracts() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let stateText = try Self.appSourceText(named: "WorkspaceUIState.swift")
        let sendLifecycleText = try Self.appSourceText(named: "WorkspaceComposerSendLifecycle.swift")
        let sendStartText = try Self.appSourceText(named: "WorkspaceAgentSendStartPlanner.swift")
        let sendProgressText = try Self.appSourceText(named: "WorkspaceAgentSendProgressPlanner.swift")
        let sendTerminalText = try Self.appSourceText(named: "WorkspaceAgentSendTerminalPlanner.swift")

        Self.assertSource(stateText, containsAll: [
            "public struct ComposerState",
            "public struct MemoriesState",
            "public struct ActivityState"
        ])
        Self.assertSource(sendLifecycleText, contains: "enum WorkspaceComposerSendLifecycle")
        Self.assertSource(sendStartText, contains: "WorkspaceComposerSendLifecycle.started")
        Self.assertSource(sendProgressText, contains: "WorkspaceAgentStatusBuilder.status")
        Self.assertSource(composerText, containsAll: [
            "WorkspaceAgentSendStartPlanner.started",
            "WorkspaceAgentSendProgressPlanner.progress",
            "WorkspaceAgentSendTerminalPlanner.completed",
            "WorkspaceAgentSendTerminalPlanner.cancelled",
            "WorkspaceAgentSendTerminalPlanner.failed"
        ])
        Self.assertSource(sendTerminalText, containsAll: [
            "WorkspaceComposerSendLifecycle.completed",
            "WorkspaceComposerSendLifecycle.cancelled",
            "WorkspaceComposerSendLifecycle.failed"
        ])
        Self.assertSource(modelText, contains: "public internal(set) var composer: ComposerState")
        Self.assertSource(modelText, excludesAll: [
            "public struct ComposerState",
            "public struct MemoriesState",
            "public struct ActivityState"
        ])
    }
}
