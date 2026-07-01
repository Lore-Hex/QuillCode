import XCTest

final class ParityWorkspaceThreadSlashIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceThreadLifecycleIntegrationTestsOwnModelLifecycleFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let lifecycleIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceThreadLifecycleIntegrationTests.swift"
        )

        Self.assertSource(lifecycleIntegrationTests, containsAll: [
            "testNewChatSelectsThreadAndRefreshesTopBar",
            "testForkFromLastCreatesBoundedThreadFromLatestUserTurn",
            "testWorkspaceCommandCompactContextCreatesBoundedThread",
            "testPinAndArchiveThreadByIDPersistChanges",
            "testRenameDuplicateUnarchiveAndDeleteThreadLifecycle"
        ])

        Self.assertSource(modelTests, excludesAll: [
            "testNewChatSelectsThreadAndRefreshesTopBar",
            "testForkFromLastCreatesBoundedThreadFromLatestUserTurn",
            "testWorkspaceCommandCompactContextCreatesBoundedThread",
            "testPinAndArchiveThreadByIDPersistChanges",
            "testRenameDuplicateUnarchiveAndDeleteThreadLifecycle"
        ])
    }

    func testWorkspaceSlashCommandIntegrationTestsOwnCoreSlashFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let slashIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceSlashCommandIntegrationTests.swift"
        )

        Self.assertSource(slashIntegrationTests, containsAll: [
            "testSlashCommandsRouteToWorkspaceActions",
            "testSlashEnvironmentActionListsAndRunsByName",
            "testSlashThreadLifecycleCommands",
            "testSlashStatusReportsWorkspaceState"
        ])

        Self.assertSource(modelTests, excludesAll: [
            "testSlashCommandsRouteToWorkspaceActions",
            "testSlashEnvironmentActionListsAndRunsByName",
            "testSlashThreadLifecycleCommands",
            "testSlashStatusReportsWorkspaceState"
        ])
    }

    func testWorkspaceLocalEnvironmentIntegrationTestsOwnModelLocalEnvironmentFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let localEnvironmentIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceLocalEnvironmentIntegrationTests.swift"
        )

        Self.assertSource(localEnvironmentIntegrationTests, containsAll: [
            "testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs",
            "testLocalEnvironmentActionMetadataInjectsBoundedEnvironment",
            "testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory",
            "testLocalEnvironmentActionMetadataPassesBoundedTimeout"
        ])

        Self.assertSource(modelTests, excludesAll: [
            "testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs",
            "testLocalEnvironmentActionMetadataInjectsBoundedEnvironment",
            "testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory",
            "testLocalEnvironmentActionMetadataPassesBoundedTimeout"
        ])
    }
}
