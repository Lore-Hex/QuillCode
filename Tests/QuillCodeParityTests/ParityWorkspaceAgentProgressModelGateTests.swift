import XCTest

final class ParityWorkspaceAgentProgressModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesAgentProgressStatusCopy() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentStatusBuilder.swift")
        let progressPlannerText = try Self.appSourceText(named: "WorkspaceAgentSendProgressPlanner.swift")

        Self.assertSource(builderText, containsAll: [
            "struct WorkspaceAgentStatusBuilder",
            "static func status(for thread: ChatThread)",
            "static func status(for event: ThreadEvent?)",
            "AgentRunner.streamingNotice"
        ])
        Self.assertSource(progressPlannerText, containsAll: [
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
