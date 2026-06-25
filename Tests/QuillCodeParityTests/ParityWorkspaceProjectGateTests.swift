import XCTest

final class ParityWorkspaceProjectGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesProjectMetadataLoading() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let loaderText = try Self.appSourceText(named: "WorkspaceProjectMetadataLoader.swift")

        XCTAssertTrue(loaderText.contains("enum WorkspaceProjectMetadataLoader"), "Project metadata loading should live in a focused loader.")
        XCTAssertTrue(loaderText.contains("ProjectInstructionLoader.load"), "Project instruction loading should stay with the metadata loader.")
        XCTAssertTrue(loaderText.contains("LocalEnvironmentActionLoader.load"), "Local environment action loading should stay with the metadata loader.")
        XCTAssertTrue(loaderText.contains("ProjectExtensionManifestLoader.load"), "Project extension loading should stay with the metadata loader.")
        XCTAssertTrue(loaderText.contains("MemoryNoteLoader.loadProject"), "Project memory loading should stay with the metadata loader.")
        XCTAssertTrue(loaderText.contains("SSHRemoteProjectContextLoader.load"), "SSH Remote context loading should stay with the metadata loader.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectMetadataLoader.loadLocal"), "WorkspaceModel should delegate local project metadata loading.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.refreshRemoteProjectContext"), "WorkspaceModel should delegate SSH Remote project metadata refresh.")
        XCTAssertFalse(modelText.contains("ProjectInstructionLoader.load"), "WorkspaceModel should not load instruction files directly.")
        XCTAssertFalse(modelText.contains("LocalEnvironmentActionLoader.load"), "WorkspaceModel should not load local environment actions directly.")
        XCTAssertFalse(modelText.contains("ProjectExtensionManifestLoader.load"), "WorkspaceModel should not load project extensions directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.loadProject"), "WorkspaceModel should not load project memories directly.")
        XCTAssertFalse(modelText.contains("SSHRemoteProjectContextLoader.load"), "WorkspaceModel should not load SSH Remote context directly.")
    }

    func testWorkspaceModelTestsDoNotOwnPureProjectLoaderCoverage() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let instructionTests = try Self.appTestSourceText(named: "ProjectInstructionLoaderTests.swift")
        let actionTests = try Self.appTestSourceText(named: "LocalEnvironmentActionLoaderTests.swift")
        let extensionTests = try Self.appTestSourceText(named: "ProjectExtensionManifestLoaderTests.swift")
        let memoryTests = try Self.appTestSourceText(named: "MemoryNoteLoaderTests.swift")

        XCTAssertTrue(instructionTests.contains("ProjectInstructionLoader.load"), "Project instruction loader coverage should live in its focused test file.")
        XCTAssertTrue(actionTests.contains("LocalEnvironmentActionLoader.load"), "Local environment loader coverage should live in its focused test file.")
        XCTAssertTrue(extensionTests.contains("ProjectExtensionManifestLoader.load"), "Project extension loader coverage should live in its focused test file.")
        XCTAssertTrue(memoryTests.contains("MemoryNoteLoader.loadProject"), "Project memory loader coverage should live in its focused test file.")
        XCTAssertFalse(modelTests.contains("ProjectInstructionLoader.load"), "WorkspaceModelTests should focus on model integration, not direct project instruction loader tests.")
        XCTAssertFalse(modelTests.contains("LocalEnvironmentActionLoader.load"), "WorkspaceModelTests should focus on model integration, not direct local environment loader tests.")
        XCTAssertFalse(modelTests.contains("ProjectExtensionManifestLoader.load"), "WorkspaceModelTests should focus on model integration, not direct extension loader tests.")
        XCTAssertFalse(modelTests.contains("MemoryNoteLoader.loadProject"), "WorkspaceModelTests should focus on model integration, not direct memory loader tests.")
    }

    func testWorkspaceProjectExtensionIntegrationTestsOwnModelExtensionFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let extensionIntegrationTests = try Self.appTestSourceText(named: "WorkspaceProjectExtensionIntegrationTests.swift")

        XCTAssertTrue(extensionIntegrationTests.contains("testProjectExtensionManifestsLoadIntoProjectSurface"), "Project extension manifest integration should live in focused extension integration tests.")
        XCTAssertTrue(extensionIntegrationTests.contains("testSurfaceIncludesProjectExtensionSummaryAndCommand"), "Project extension surface summaries should live in focused extension integration tests.")
        XCTAssertTrue(extensionIntegrationTests.contains("testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata"), "Project extension update integration should live in focused extension integration tests.")
        XCTAssertTrue(extensionIntegrationTests.contains("testProjectExtensionUpdateFailureKeepsManifestAndRecordsFailureNotice"), "Project extension update failure integration should live in focused extension integration tests.")
        XCTAssertFalse(modelTests.contains("testProjectExtensionManifestsLoadIntoProjectSurface"), "WorkspaceModelTests should not own project extension manifest integration flows.")
        XCTAssertFalse(modelTests.contains("testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata"), "WorkspaceModelTests should not own project extension update integration flows.")
        XCTAssertFalse(broadSurfaceTests.contains("testSurfaceIncludesProjectExtensionSummaryAndCommand"), "WorkspaceSurfaceTests should not own project extension surface summaries.")
    }

    func testWorkspaceProjectIntegrationTestsOwnModelProjectFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let projectIntegrationTests = try Self.appTestSourceText(named: "WorkspaceProjectIntegrationTests.swift")

        XCTAssertTrue(projectIntegrationTests.contains("testModelPersistsProjectRegistryChanges"), "Project registry persistence should live in focused project integration tests.")
        XCTAssertTrue(projectIntegrationTests.contains("testSelectingProjectControlsNextChatAndWorkspaceRoot"), "Project selection workspace integration should live in focused project tests.")
        XCTAssertTrue(projectIntegrationTests.contains("testProjectLifecycleActionsRenameRefreshNewChatAndRemove"), "Project lifecycle command integration should live in focused project tests.")
        XCTAssertTrue(projectIntegrationTests.contains("testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun"), "Project instruction integration should live in focused project tests.")
        XCTAssertFalse(modelTests.contains("testModelPersistsProjectRegistryChanges"), "WorkspaceModelTests should not own project registry persistence integration flows.")
        XCTAssertFalse(modelTests.contains("testSelectingProjectControlsNextChatAndWorkspaceRoot"), "WorkspaceModelTests should not own project selection integration flows.")
        XCTAssertFalse(modelTests.contains("testProjectLifecycleActionsRenameRefreshNewChatAndRemove"), "WorkspaceModelTests should not own project lifecycle command integration flows.")
        XCTAssertFalse(modelTests.contains("testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun"), "WorkspaceModelTests should not own project instruction integration flows.")
    }

    func testWorkspaceRemoteProjectIntegrationTestsOwnModelRemoteProjectFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let remoteProjectIntegrationTests = try Self.appTestSourceText(named: "WorkspaceRemoteProjectIntegrationTests.swift")
        let remoteProjectShellGitTests = try Self.appTestSourceText(named: "WorkspaceRemoteProjectShellGitIntegrationTests.swift")
        let remoteProjectPullRequestTests = try Self.appTestSourceText(named: "WorkspaceRemoteProjectPullRequestIntegrationTests.swift")
        let remoteProjectWorktreeTests = try Self.appTestSourceText(named: "WorkspaceRemoteProjectWorktreeIntegrationTests.swift")

        XCTAssertTrue(remoteProjectIntegrationTests.contains("testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions"), "SSH project setup should live in focused remote project integration tests.")
        XCTAssertTrue(remoteProjectShellGitTests.contains("testRemoteProjectAgentRunsShellThroughSSH"), "Remote shell agent execution should live in focused remote shell/git tests.")
        XCTAssertTrue(remoteProjectPullRequestTests.contains("testRemoteProjectAgentCreatesPullRequestThroughSSH"), "Remote PR creation should live in focused remote PR tests.")
        XCTAssertTrue(remoteProjectWorktreeTests.contains("testRemoteProjectRejectsUnsafeWorktreePathBeforeSSH"), "Remote worktree safety coverage should live in focused remote worktree tests.")
        XCTAssertFalse(modelTests.contains("testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions"), "WorkspaceModelTests should not own SSH project setup integration flows.")
        XCTAssertFalse(modelTests.contains("testRemoteProjectAgentRunsShellThroughSSH"), "WorkspaceModelTests should not own remote shell agent integration flows.")
        XCTAssertFalse(modelTests.contains("testRemoteProjectAgentCreatesPullRequestThroughSSH"), "WorkspaceModelTests should not own remote PR creation integration flows.")
        XCTAssertFalse(modelTests.contains("testRemoteProjectRejectsUnsafeWorktreePathBeforeSSH"), "WorkspaceModelTests should not own remote worktree safety integration flows.")
    }

    func testWorkspacePullRequestIntegrationTestsOwnModelPullRequestFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let pullRequestIntegrationTests = try Self.appTestSourceText(named: "WorkspacePullRequestIntegrationTests.swift")

        XCTAssertTrue(pullRequestIntegrationTests.contains("testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH"), "Remote PR workspace commands should live in focused pull request integration tests.")
        XCTAssertTrue(pullRequestIntegrationTests.contains("testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH"), "PR slash command dispatch should live in focused pull request integration tests.")
        XCTAssertTrue(pullRequestIntegrationTests.contains("testWorkspacePullRequestCommandsPrefillComposer"), "PR command prefills should live in focused pull request integration tests.")
        XCTAssertTrue(pullRequestIntegrationTests.contains("makeRemotePullRequestFixture"), "Repeated fake GitHub CLI plus SSH setup should stay centralized in the PR integration suite.")

        XCTAssertFalse(modelTests.contains("testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH"), "WorkspaceModelTests should not own remote PR workspace command integration.")
        XCTAssertFalse(modelTests.contains("testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH"), "WorkspaceModelTests should not own PR slash command integration.")
        XCTAssertFalse(modelTests.contains("testWorkspacePullRequestCommandsPrefillComposer"), "WorkspaceModelTests should not own PR command prefill integration.")
        XCTAssertFalse(modelTests.contains("makeRemotePullRequestFixture"), "WorkspaceModelTests should not own PR integration fixture setup.")
    }

    func testWorkspaceWorktreeIntegrationTestsOwnModelWorktreeFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let worktreeIntegrationTests = try Self.appTestSourceText(named: "WorkspaceWorktreeIntegrationTests.swift")

        XCTAssertTrue(worktreeIntegrationTests.contains("testWorkspaceCommandListsGitWorktrees"), "Local worktree listing should live in focused worktree integration tests.")
        XCTAssertTrue(worktreeIntegrationTests.contains("testRemoteWorkspaceCommandListsGitWorktreesThroughSSH"), "SSH Remote worktree listing should live in focused worktree integration tests.")
        XCTAssertTrue(worktreeIntegrationTests.contains("testWorkspaceWorktreeCommandsPrefillComposer"), "Worktree command prefill should live in focused worktree integration tests.")
        XCTAssertTrue(worktreeIntegrationTests.contains("testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit"), "Local worktree create/open integration should live in focused worktree integration tests.")
        XCTAssertTrue(worktreeIntegrationTests.contains("testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit"), "SSH Remote worktree create/open integration should live in focused worktree integration tests.")

        XCTAssertFalse(modelTests.contains("testWorkspaceCommandListsGitWorktrees"), "WorkspaceModelTests should not own local worktree listing integration.")
        XCTAssertFalse(modelTests.contains("testRemoteWorkspaceCommandListsGitWorktreesThroughSSH"), "WorkspaceModelTests should not own SSH Remote worktree listing integration.")
        XCTAssertFalse(modelTests.contains("testWorkspaceWorktreeCommandsPrefillComposer"), "WorkspaceModelTests should not own worktree command prefill integration.")
        XCTAssertFalse(modelTests.contains("testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit"), "WorkspaceModelTests should not own local worktree create/open integration.")
        XCTAssertFalse(modelTests.contains("testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit"), "WorkspaceModelTests should not own SSH Remote worktree create/open integration.")
    }

    func testWorkspaceModelDelegatesWorktreeOpenRecords() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let requestsText = try Self.appSourceText(named: "WorkspaceWorktreeRequests.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceWorktreeOpenEngine.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceWorktreeToolCallPlanner.swift")

        XCTAssertTrue(requestsText.contains("public struct WorkspaceWorktreeCreateRequest"), "Worktree create requests should live outside WorkspaceModel.")
        XCTAssertTrue(requestsText.contains("public struct WorkspaceWorktreeRemoveRequest"), "Worktree remove requests should live outside WorkspaceModel.")
        XCTAssertTrue(requestsText.contains("public struct WorkspaceWorktreePruneRequest"), "Worktree prune requests should live outside WorkspaceModel.")
        XCTAssertTrue(engineText.contains("struct WorkspaceWorktreeOpenEngine"), "Opened-worktree thread construction should live in a focused engine.")
        XCTAssertTrue(engineText.contains("static func localThread"), "Local worktree handoff records should be directly testable.")
        XCTAssertTrue(engineText.contains("static func remoteThread"), "SSH Remote worktree handoff records should be directly testable.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceWorktreeToolCallPlanner"), "Worktree tool-call JSON should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func create"), "Worktree create tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func remove"), "Worktree remove tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func prune"), "Worktree prune tool calls should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeToolCallPlanner.create"), "WorkspaceModel should delegate worktree create tool-call construction.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeToolCallPlanner.remove"), "WorkspaceModel should delegate worktree remove tool-call construction.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeToolCallPlanner.prune"), "WorkspaceModel should delegate worktree prune tool-call construction.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeOpenEngine.localThread"), "WorkspaceModel should delegate local worktree handoff records.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeOpenEngine.remoteThread"), "WorkspaceModel should delegate SSH Remote worktree handoff records.")
        XCTAssertTrue(modelText.contains("openCreatedWorktreeThread"), "WorkspaceModel should share selected-thread persistence for local and remote worktrees.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitWorktreeCreate.name"), "WorkspaceModel should not own worktree create tool-call details.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitWorktreeRemove.name"), "WorkspaceModel should not own worktree remove tool-call details.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitWorktreePrune.name"), "WorkspaceModel should not own worktree prune tool-call details.")
        XCTAssertFalse(modelText.contains("title: \"Worktree:"), "WorkspaceModel should not own worktree thread title copy.")
        XCTAssertFalse(modelText.contains("Opened remote worktree `"), "WorkspaceModel should not own remote worktree transcript copy.")
        XCTAssertFalse(modelText.contains("Opened worktree `"), "WorkspaceModel should not own local worktree transcript copy.")
    }
}
