import XCTest

final class ParityWorkspaceMCPIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceMCPIntegrationTestsOwnModelMCPFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let mcpIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceMCPIntegrationTests.swift"
        )

        Self.assertSource(mcpIntegrationTests, containsAll: [
            "testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses",
            "testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction",
            "testReadyMCPServerCanBeCalledFromAgentTurn",
            "testReadyMCPResourceCanBeReadFromAgentTurn",
            "testReadyMCPPromptCanBeLoadedFromAgentTurn",
            "testMCPToolCallRejectsUnadvertisedTools"
        ])

        Self.assertSource(modelTests, excludesAll: [
            "testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses",
            "testReadyMCPServerCanBeCalledFromAgentTurn",
            "testReadyMCPResourceCanBeReadFromAgentTurn",
            "testReadyMCPPromptCanBeLoadedFromAgentTurn",
            "testMCPToolCallRejectsUnadvertisedTools"
        ])

        Self.assertSource(
            broadSurfaceTests,
            excludes: "testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction"
        )
    }
}
