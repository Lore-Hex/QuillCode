import XCTest

final class ParityWorkspaceShellToolCallGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesShellToolCallPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let localEnvironmentModelText = try Self.appSourceText(named: "WorkspaceModelLocalEnvironment.swift")
        let projectModelText = try Self.appSourceText(named: "WorkspaceModelProjects.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceShellToolCallPlanner.swift")

        [
            "enum WorkspaceShellToolCallPlanner",
            "static func localEnvironmentAction",
            "static func projectExtensionInstall",
            "static func projectExtensionUpdate",
            "ToolDefinition.shellRun.name",
            "ToolArguments.json(arguments)"
        ].forEach { Self.assertSource(plannerText, contains: $0) }

        Self.assertSource(
            localEnvironmentModelText,
            contains: "WorkspaceShellToolCallPlanner.localEnvironmentAction"
        )
        Self.assertSource(
            projectModelText,
            contains: "WorkspaceShellToolCallPlanner.projectExtensionInstall"
        )
        Self.assertSource(
            projectModelText,
            contains: "WorkspaceShellToolCallPlanner.projectExtensionUpdate"
        )

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
