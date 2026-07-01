import XCTest

final class ParityWorkspaceProjectIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceProjectExtensionIntegrationTestsOwnModelExtensionFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let extensionTests = try Self.appTestSourceText(
            named: "WorkspaceProjectExtensionIntegrationTests.swift"
        )

        Self.assertSource(extensionTests, contains: "testProjectExtensionManifestsLoadIntoProjectSurface")
        Self.assertSource(extensionTests, contains: "testSurfaceIncludesProjectExtensionSummaryAndCommand")
        Self.assertSource(extensionTests, contains: "testProjectExtensionInstallCommandRunsAndRefreshesProjectMetadata")
        Self.assertSource(extensionTests, contains: "testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata")
        Self.assertSource(
            extensionTests,
            contains: "testProjectExtensionUpdateFailureKeepsManifestAndRecordsFailureNotice"
        )
        Self.assertSource(modelTests, excludes: "testProjectExtensionManifestsLoadIntoProjectSurface")
        Self.assertSource(modelTests, excludes: "testProjectExtensionInstallCommandRunsAndRefreshesProjectMetadata")
        Self.assertSource(modelTests, excludes: "testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata")
        Self.assertSource(broadSurfaceTests, excludes: "testSurfaceIncludesProjectExtensionSummaryAndCommand")
    }

    func testWorkspaceProjectIntegrationTestsOwnModelProjectFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let projectIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceProjectIntegrationTests.swift"
        )

        Self.assertSource(projectIntegrationTests, contains: "testModelPersistsProjectRegistryChanges")
        Self.assertSource(projectIntegrationTests, contains: "testSelectingProjectControlsNextChatAndWorkspaceRoot")
        Self.assertSource(projectIntegrationTests, contains: "testProjectLifecycleActionsRenameRefreshNewChatAndRemove")
        Self.assertSource(
            projectIntegrationTests,
            contains: "testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun"
        )
        Self.assertSource(modelTests, excludes: "testModelPersistsProjectRegistryChanges")
        Self.assertSource(modelTests, excludes: "testSelectingProjectControlsNextChatAndWorkspaceRoot")
        Self.assertSource(modelTests, excludes: "testProjectLifecycleActionsRenameRefreshNewChatAndRemove")
        Self.assertSource(modelTests, excludes: "testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun")
    }

    func testWorkspaceRemoteProjectIntegrationTestsOwnModelRemoteProjectFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let remoteProjectTests = try Self.appTestSourceText(
            named: "WorkspaceRemoteProjectIntegrationTests.swift"
        )
        let shellGitTests = try Self.appTestSourceText(
            named: "WorkspaceRemoteProjectShellGitIntegrationTests.swift"
        )
        let pullRequestTests = try Self.appTestSourceText(
            named: "WorkspaceRemoteProjectPullRequestIntegrationTests.swift"
        )
        let worktreeTests = try Self.appTestSourceText(
            named: "WorkspaceRemoteProjectWorktreeIntegrationTests.swift"
        )

        Self.assertSource(remoteProjectTests, contains: "testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions")
        Self.assertSource(shellGitTests, contains: "testRemoteProjectAgentRunsShellThroughSSH")
        Self.assertSource(pullRequestTests, contains: "testRemoteProjectAgentCreatesPullRequestThroughSSH")
        Self.assertSource(worktreeTests, contains: "testRemoteProjectRejectsUnsafeWorktreePathBeforeSSH")
        Self.assertSource(modelTests, excludes: "testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions")
        Self.assertSource(modelTests, excludes: "testRemoteProjectAgentRunsShellThroughSSH")
        Self.assertSource(modelTests, excludes: "testRemoteProjectAgentCreatesPullRequestThroughSSH")
        Self.assertSource(modelTests, excludes: "testRemoteProjectRejectsUnsafeWorktreePathBeforeSSH")
    }

    func testWorkspacePullRequestIntegrationTestsOwnModelPullRequestFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let pullRequestIntegrationTests = try Self.appTestSourceText(
            named: "WorkspacePullRequestIntegrationTests.swift"
        )

        Self.assertSource(
            pullRequestIntegrationTests,
            contains: "testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH"
        )
        Self.assertSource(
            pullRequestIntegrationTests,
            contains: "testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH"
        )
        Self.assertSource(
            pullRequestIntegrationTests,
            contains: "testWorkspacePullRequestCommandsPrefillComposer"
        )
        Self.assertSource(pullRequestIntegrationTests, contains: "makeRemotePullRequestFixture")
        Self.assertSource(modelTests, excludes: "testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH")
        Self.assertSource(modelTests, excludes: "testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH")
        Self.assertSource(modelTests, excludes: "testWorkspacePullRequestCommandsPrefillComposer")
        Self.assertSource(modelTests, excludes: "makeRemotePullRequestFixture")
    }
}
