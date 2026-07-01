import XCTest

final class ParityWorkspaceCommandActionGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesCommandActionPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceCommandActionPlanner.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceCommandActionExecutor.swift")
        let planExecutorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")

        Self.assertSource(plannerText, containsAll: Self.plannerContracts)
        Self.assertSource(executorText, containsAll: Self.executorContracts)
        Self.assertSource(planExecutorText, contains: "return runWorkspaceCommandAction(action)")
        Self.assertSource(modelText, excludesAll: Self.modelForbiddenActionOwnership)
    }
}

private extension ParityWorkspaceCommandActionGateTests {
    static let plannerContracts = [
        "enum WorkspaceCommandActionEffect",
        "struct WorkspaceCommandActionPlanner",
        "func effect(for action: WorkspaceCommandAction)"
    ]

    static let executorContracts = [
        "WorkspaceCommandActionPlanner(",
        "func runWorkspaceCommandAction(",
        "func runWorkspaceCommandActionEffect("
    ]

    static let modelForbiddenActionOwnership = [
        "WorkspaceCommandActionPlanner(",
        "runWorkspaceCommandAction(action)",
        "runWorkspaceCommandActionEffect",
        "case .toggleTerminal:",
        "case .projectNewChat:",
        "case .projectRename:",
        "case .threadBulkArchive:",
        "setDraft(\"/project rename",
        "setDraft(\"/rename"
    ]
}
