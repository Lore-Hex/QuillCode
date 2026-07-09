import XCTest

final class ParityWorkspaceToolRoutingGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesToolCallExecutionRouting() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceToolCallExecutorFactory.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceToolCallExecutor.swift")

        [
            "struct WorkspaceToolCallExecutor",
            "WorkspaceBrowserToolExecutor.execute",
            "PlanUpdateToolExecutor.execute",
            "HandoffUpdateToolExecutor.execute",
            "SubagentProgressToolExecutor.execute",
            "WorkspaceRemoteProjectToolExecutor.execute",
            "ToolDefinition.applyPatch.name"
        ].forEach { Self.assertSource(executorText, contains: $0) }

        Self.assertSource(toolRunsText, contains: "WorkspaceToolRunCoordinator")
        Self.assertSource(factoryText, contains: "enum WorkspaceToolCallExecutorFactory")
        Self.assertSource(factoryText, contains: "WorkspaceToolCallExecutor(")
        Self.assertSource(coordinatorText, contains: "WorkspaceToolCallExecutorFactory.executor")

        [
            "call.name == ToolDefinition.browserInspect.name",
            "call.name == ToolDefinition.browserOpen.name",
            "call.name == ToolDefinition.browserClick.name",
            "call.name == ToolDefinition.browserType.name",
            "call.name == ToolDefinition.planUpdate.name",
            "call.name == ToolDefinition.handoffUpdate.name",
            "private func appendReviewDiffAfterPatchIfNeeded",
            "private func executeReviewGitToolCall"
        ].forEach { Self.assertSource(modelText, excludes: $0) }

        Self.assertSource(modelText, excludes: "func workspaceToolCallExecutor")
        Self.assertSource(toolRunsText, excludes: "func workspaceToolCallExecutor")
    }

    func testWorkspaceModelDelegatesToolExecutionOverrideCombining() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let combinerText = try Self.appSourceText(named: "WorkspaceToolExecutionOverrideCombiner.swift")

        [
            "struct WorkspaceToolExecutionOverrideCombiner",
            "static func combine",
            "activity?(call, workspaceRoot)",
            "remoteProject?(call, workspaceRoot)",
            "mcp?(call, workspaceRoot)"
        ].forEach { Self.assertSource(combinerText, contains: $0) }

        Self.assertSource(builderText, contains: "WorkspaceToolExecutionOverrideCombiner.combine")

        [
            "WorkspaceToolExecutionOverrideCombiner.combine",
            "private func combinedToolExecutionOverride",
            "if let result = await activity?(call, workspaceRoot)",
            "if let result = await plan?(call, workspaceRoot)"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }
}
