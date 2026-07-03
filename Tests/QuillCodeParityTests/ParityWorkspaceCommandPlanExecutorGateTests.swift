import XCTest

final class ParityWorkspaceCommandPlanExecutorGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesCommandPlanExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")

        Self.assertSource(executorText, containsAll: [
            "public func runWorkspaceCommand(",
            "WorkspaceCommandPlan(commandID: commandID)",
            "func runWorkspaceCommandPlan(",
            "switch plan",
            "return runWorkspaceCommandAction(action, workspaceRoot: workspaceRoot)"
        ])
        Self.assertSource(modelText, excludesAll: [
            "WorkspaceCommandPlan(commandID: commandID)",
            "case .localEnvironmentAction",
            "case .startMCPServer",
            "case .runTool"
        ])
    }
}
