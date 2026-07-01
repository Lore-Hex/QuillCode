import XCTest

final class ParityWorkspaceThreadCommandIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceThreadLifecycleIntegrationTestsOwnModelLifecycleFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let lifecycleIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceThreadLifecycleIntegrationTests.swift"
        )

        let lifecycleFlowTests = [
            "testNewChatSelectsThreadAndRefreshesTopBar",
            "testForkFromLastCreatesBoundedThreadFromLatestUserTurn",
            "testWorkspaceCommandCompactContextCreatesBoundedThread",
            "testPinAndArchiveThreadByIDPersistChanges",
            "testRenameDuplicateUnarchiveAndDeleteThreadLifecycle"
        ]

        Self.assertSource(lifecycleIntegrationTests, containsAll: lifecycleFlowTests)
        Self.assertSource(modelTests, excludesAll: lifecycleFlowTests)
    }

    func testWorkspaceSlashCommandIntegrationTestsOwnCoreSlashFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let slashIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceSlashCommandIntegrationTests.swift"
        )

        let slashFlowTests = [
            "testSlashCommandsRouteToWorkspaceActions",
            "testSlashEnvironmentActionListsAndRunsByName",
            "testSlashThreadLifecycleCommands",
            "testSlashStatusReportsWorkspaceState"
        ]

        Self.assertSource(slashIntegrationTests, containsAll: slashFlowTests)
        Self.assertSource(modelTests, excludesAll: slashFlowTests)
    }

    func testWorkspaceLocalEnvironmentIntegrationTestsOwnModelLocalEnvironmentFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let localEnvironmentIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceLocalEnvironmentIntegrationTests.swift"
        )

        let localEnvironmentFlowTests = [
            "testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs",
            "testLocalEnvironmentActionMetadataInjectsBoundedEnvironment",
            "testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory",
            "testLocalEnvironmentActionMetadataPassesBoundedTimeout"
        ]

        Self.assertSource(localEnvironmentIntegrationTests, containsAll: localEnvironmentFlowTests)
        Self.assertSource(modelTests, excludesAll: localEnvironmentFlowTests)
    }
}
