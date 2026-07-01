import XCTest

final class ParityWorkspaceTerminalActiveWorkGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesTerminalLifecyclePlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let terminalText = try Self.appSourceText(named: "WorkspaceModelTerminal.swift")
        let lifecycleText = try Self.appSourceText(named: "WorkspaceTerminalLifecyclePlanner.swift")

        Self.assertSource(terminalText, contains: "extension QuillCodeWorkspaceModel")

        [
            "enum WorkspaceTerminalLifecyclePlanner",
            "static func started",
            "static func missingExecutionContext",
            "static func finished"
        ].forEach { Self.assertSource(lifecycleText, contains: $0) }

        [
            "WorkspaceTerminalLifecyclePlanner.started",
            "WorkspaceTerminalLifecyclePlanner.missingExecutionContext",
            "WorkspaceTerminalLifecyclePlanner.stopped",
            "WorkspaceTerminalLifecyclePlanner.cancelled",
            "WorkspaceTerminalLifecyclePlanner.finished"
        ].forEach { Self.assertSource(terminalText, contains: $0) }

        [
            "public func runTerminalCommand",
            "public func clearTerminalHistory"
        ].forEach { Self.assertSource(modelText, excludes: $0) }

        [
            "TopBarAgentStatusLabel.terminal",
            "TopBarAgentStatusLabel.stopped",
            "result.ok ?"
        ].forEach { Self.assertSource(terminalText, excludes: $0) }
    }

    func testWorkspaceModelDelegatesActiveWorkStopPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let activeWorkText = try Self.appSourceText(named: "WorkspaceModelActiveWork.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceActiveWorkStopPlanner.swift")

        Self.assertSource(activeWorkText, contains: "extension QuillCodeWorkspaceModel")

        [
            "enum WorkspaceActiveWorkStopPlanner",
            "static func cancel",
            "static func disconnectAll"
        ].forEach { Self.assertSource(plannerText, contains: $0) }

        [
            "WorkspaceActiveWorkStopPlanner.cancel",
            "WorkspaceActiveWorkStopPlanner.disconnectAll",
            "applyActiveWorkStopPlan"
        ].forEach { Self.assertSource(activeWorkText, contains: $0) }

        [
            "public func cancelActiveWork",
            "public func disconnectAll",
            "stopActiveWorkspaceWork"
        ].forEach { Self.assertSource(modelText, excludes: $0) }

        [
            "TopBarAgentStatusLabel.stopped",
            "TopBarAgentStatusLabel.idle",
            "? TopBarAgentStatusLabel"
        ].forEach { Self.assertSource(activeWorkText, excludes: $0) }
    }
}
