import XCTest

final class ParityWorkspaceCommandPlanGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesCommandPlanExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")

        Self.assertSource(executorText, containsAll: Self.executorContracts)
        Self.assertSource(modelText, excludesAll: Self.modelForbiddenPlanOwnership)
    }
}

private extension ParityWorkspaceCommandPlanGateTests {
    static let executorContracts = [
        "public func runWorkspaceCommand(",
        "WorkspaceCommandPlan(commandID: commandID)",
        "func runWorkspaceCommandPlan(",
        "switch plan",
        "return runWorkspaceCommandAction(action)"
    ]

    static let modelForbiddenPlanOwnership = [
        "WorkspaceCommandPlan(commandID: commandID)",
        "case .localEnvironmentAction",
        "case .startMCPServer",
        "case .runTool"
    ]
}
