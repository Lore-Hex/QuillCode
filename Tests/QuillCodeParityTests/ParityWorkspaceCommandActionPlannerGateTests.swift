import XCTest

final class ParityWorkspaceCommandActionPlannerGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesCommandActionPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceCommandActionPlanner.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceCommandActionExecutor.swift")
        let planExecutorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")

        Self.assertSource(plannerText, containsAll: [
            "enum WorkspaceCommandActionEffect",
            "struct WorkspaceCommandActionPlanner",
            "func effect(for action: WorkspaceCommandAction)"
        ])
        Self.assertSource(executorText, containsAll: [
            "WorkspaceCommandActionPlanner(",
            "func runWorkspaceCommandAction(",
            "func runWorkspaceCommandActionEffect("
        ])
        Self.assertSource(
            planExecutorText,
            contains: "return runWorkspaceCommandAction(action, workspaceRoot: workspaceRoot)"
        )
        Self.assertSource(modelText, excludesAll: [
            "WorkspaceCommandActionPlanner(",
            "runWorkspaceCommandAction(action, workspaceRoot:",
            "runWorkspaceCommandActionEffect",
            "case .toggleTerminal:",
            "case .projectNewChat:",
            "case .projectRename:",
            "case .threadBulkArchive:",
            "setDraft(\"/project rename",
            "setDraft(\"/rename"
        ])
    }
}
