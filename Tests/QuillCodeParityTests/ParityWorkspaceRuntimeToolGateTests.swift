import XCTest

final class ParityWorkspaceRuntimeToolGateTests: QuillCodeParityTestCase {
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

    func testWorkspaceModelDelegatesShellToolCallPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let environmentText = try Self.appSourceText(named: "WorkspaceModelLocalEnvironment.swift")
        let projectText = try Self.appSourceText(named: "WorkspaceModelProjects.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceShellToolCallPlanner.swift")

        [
            "enum WorkspaceShellToolCallPlanner",
            "static func localEnvironmentAction",
            "static func projectExtensionInstall",
            "static func projectExtensionUpdate",
            "ToolDefinition.shellRun.name",
            "ToolArguments.json(arguments)"
        ].forEach { Self.assertSource(plannerText, contains: $0) }

        Self.assertSource(environmentText, contains: "WorkspaceShellToolCallPlanner.localEnvironmentAction")
        Self.assertSource(projectText, contains: "WorkspaceShellToolCallPlanner.projectExtensionInstall")
        Self.assertSource(projectText, contains: "WorkspaceShellToolCallPlanner.projectExtensionUpdate")

        [
            "arguments[\"environment\"] = environment",
            "arguments[\"timeoutSeconds\"] = timeoutSeconds",
            "WorkspaceShellToolCallPlanner.localEnvironmentAction",
            "WorkspaceShellToolCallPlanner.projectExtensionInstall",
            "WorkspaceShellToolCallPlanner.projectExtensionUpdate",
            "let command = manifest.installCommand",
            "let command = manifest.updateCommand"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }
}
