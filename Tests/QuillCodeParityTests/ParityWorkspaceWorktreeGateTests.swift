import XCTest

final class ParityWorkspaceWorktreeGateTests: QuillCodeParityTestCase {
    func testWorkspaceWorktreeIntegrationTestsOwnModelWorktreeFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let worktreeIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceWorktreeIntegrationTests.swift"
        )

        Self.assertSource(worktreeIntegrationTests, contains: "testWorkspaceCommandListsGitWorktrees")
        Self.assertSource(worktreeIntegrationTests, contains: "testRemoteWorkspaceCommandListsGitWorktreesThroughSSH")
        Self.assertSource(worktreeIntegrationTests, contains: "testWorkspaceWorktreeCommandsPrefillComposer")
        Self.assertSource(
            worktreeIntegrationTests,
            contains: "testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit"
        )
        Self.assertSource(
            worktreeIntegrationTests,
            contains: "testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit"
        )

        Self.assertSource(modelTests, excludes: "testWorkspaceCommandListsGitWorktrees")
        Self.assertSource(modelTests, excludes: "testRemoteWorkspaceCommandListsGitWorktreesThroughSSH")
        Self.assertSource(modelTests, excludes: "testWorkspaceWorktreeCommandsPrefillComposer")
        Self.assertSource(modelTests, excludes: "testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit")
        Self.assertSource(modelTests, excludes: "testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit")
    }

    func testWorkspaceModelDelegatesWorktreeOpenRecords() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let worktreeExtensionText = try Self.appSourceText(named: "WorkspaceModelWorktrees.swift")
        let requestsText = try Self.appSourceText(named: "WorkspaceWorktreeRequests.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceWorktreeOpenEngine.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceWorktreeToolCallPlanner.swift")

        assertWorktreeRequestAndEngineContracts(requestsText, engineText, plannerText)
        assertWorktreeExtensionDelegation(worktreeExtensionText)
        assertWorktreeOwnershipExclusions(modelText, worktreeExtensionText)
    }

    func testManagedWorktreeMaterializationStaysSplitAcrossFocusedBoundaries() throws {
        let executor = try Self.toolsSourceText(named: "GitWorktreeToolExecutor.swift")
        let materializer = try Self.toolsSourceText(named: "GitManagedWorktreeMaterializer.swift")
        let snapshot = try Self.toolsSourceText(named: "ManagedWorktreeTransferSnapshot.swift")
        let model = try Self.appSourceText(named: "WorkspaceModelWorktrees.swift")
        let threadPlanner = try Self.appSourceText(named: "WorktreeThreadPlanner.swift")
        let toolsTests = try Self.toolsTestSourceText(named: "GitWorktreeToolExecutorTests.swift")

        Self.assertSource(executor, contains: "managedMaterializer.create")
        Self.assertSource(materializer, contains: "[\"worktree\", \"add\", \"--detach\"")
        Self.assertSource(materializer, contains: "[\"worktree\", \"remove\", \"--force\"")
        Self.assertSource(snapshot, contains: "--cached")
        Self.assertSource(snapshot, contains: ".worktreeinclude")
        Self.assertSource(snapshot, contains: "AGENTS.override.md")
        Self.assertSource(threadPlanner, contains: "managed: true")
        Self.assertSource(model, excludes: "copyItem")
        Self.assertSource(
            toolsTests,
            contains: "testManagedCreateStartsDetachedAndPreservesLocalChangeState"
        )
        Self.assertSource(
            toolsTests,
            contains: "testManagedCreateRollsBackWhenLocalFileWouldOverwriteBaseContent"
        )
        Self.assertSource(
            toolsTests,
            contains: "testCreateBranchHereTurnsDetachedManagedWorktreeIntoOwnedBranch"
        )
        Self.assertSource(executor, contains: "func createBranchHere")
        Self.assertSource(model, contains: "func reconcileManagedWorktreeBranch")
    }

    func testManagedArchiveSnapshotsStayDurableTransactionalAndUserOwnedSafe() throws {
        let store = try Self.toolsSourceText(named: "ManagedWorktreeSnapshotStore.swift")
        let removal = try Self.toolsSourceText(named: "ManagedWorktreeSnapshotStoreRemoval.swift")
        let model = try Self.appSourceText(named: "WorkspaceModelManagedWorktreeSnapshots.swift")
        let core = try Self.coreSourceText(named: "WorktreeBinding.swift")
        let toolsTests = try Self.toolsTestSourceText(named: "ManagedWorktreeSnapshotStoreTests.swift")
        let appTests = try Self.appTestSourceText(
            named: "WorkspaceManagedWorktreeSnapshotIntegrationTests.swift"
        )

        for contract in [
            "repositoryCommonDirectory",
            "WorktreeSnapshotReference",
            "worktree\", \"add\", \"--detach",
            "ManagedWorktreeSnapshotApplier"
        ] {
            Self.assertSource(store, contains: contract)
        }
        Self.assertSource(removal, contains: "func removeIfUnchanged")
        Self.assertSource(removal, contains: "worktree\", \"remove\", \"--force")
        Self.assertSource(removal, contains: "mismatchError: .sourceChanged")
        Self.assertSource(core, contains: "isDisposableManagedWorktree")
        Self.assertSource(core, contains: "canRestoreSnapshot")
        Self.assertSource(model, contains: "!root.threads[threadIndex].isPinned")
        Self.assertSource(model, contains: "!agentRuns.isRunning(threadID)")
        Self.assertSource(model, contains: "try threadPersistence.saveOrThrow(savedThread)")
        Self.assertSource(
            toolsTests,
            contains: "testCaptureRemoveAndRestorePreservesExactTaskState"
        )
        Self.assertSource(toolsTests, contains: "testCorruptPatchRollsBackCreatedWorktree")
        Self.assertSource(
            appTests,
            contains: "testArchivePersistsSnapshotRemovesWorktreeAndCommandRestoresIt"
        )
        Self.assertSource(appTests, contains: "testPinnedManagedTaskArchivesWithoutRemovingWorktree")
        Self.assertSource(appTests, contains: "testRunningManagedTaskArchivesWithoutRemovingWorktree")
        Self.assertSource(appTests, contains: "testNamedBranchTaskArchivesWithoutRemovingPermanentWorktree")
    }

    func testManagedWorktreeRootAndRetentionStayEndToEndAndCodexCompatible() throws {
        let config = try Self.coreSourceText(named: "AppConfig.swift")
        let binding = try Self.coreSourceText(named: "WorktreeBinding.swift")
        let planner = try Self.appSourceText(named: "ManagedWorktreeRetentionPlanner.swift")
        let lifecycle = try Self.appSourceText(named: "WorkspaceModelManagedWorktreeSnapshots.swift")
        let settings = try Self.appSourceText(named: "QuillCodeManagedWorktreeSettingsCard.swift")
        let integration = try Self.appTestSourceText(
            named: "WorkspaceManagedWorktreeRetentionIntegrationTests.swift"
        )
        let playwright = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/playwright/tests/settings.spec.ts"),
            encoding: .utf8
        )

        Self.assertSource(config, contains: "defaultRetentionLimit = 15")
        Self.assertSource(config, contains: "automaticCleanupEnabled")
        Self.assertSource(binding, contains: "managedRoot")
        Self.assertSource(planner, contains: "!thread.isPinned")
        Self.assertSource(planner, contains: "!runningThreadIDs.contains(thread.id)")
        Self.assertSource(planner, contains: "thread.worktree?.snapshot == nil")
        Self.assertSource(lifecycle, contains: "try store.capture")
        Self.assertSource(lifecycle, contains: "try store.removeIfUnchanged")
        Self.assertSource(lifecycle, contains: "enforceManagedWorktreeRetention")
        Self.assertSource(settings, contains: "Automatically clean up old managed worktrees")
        Self.assertSource(
            integration,
            contains: "testEnforcementSnapshotsAndRemovesOldestExcessWorktrees"
        )
        Self.assertSource(playwright, contains: "configures managed worktree root and recent-task retention")
    }

    private func assertWorktreeRequestAndEngineContracts(
        _ requestsText: String,
        _ engineText: String,
        _ plannerText: String
    ) {
        Self.assertSource(requestsText, contains: "public struct WorkspaceWorktreeCreateRequest")
        Self.assertSource(requestsText, contains: "public struct WorkspaceWorktreeCreateBranchRequest")
        Self.assertSource(requestsText, contains: "public struct WorkspaceWorktreeRemoveRequest")
        Self.assertSource(requestsText, contains: "public struct WorkspaceWorktreePruneRequest")
        Self.assertSource(engineText, contains: "struct WorkspaceWorktreeOpenEngine")
        Self.assertSource(engineText, contains: "static func localThread")
        Self.assertSource(engineText, contains: "static func remoteThread")
        Self.assertSource(plannerText, contains: "enum WorkspaceWorktreeToolCallPlanner")
        Self.assertSource(plannerText, contains: "static func create")
        Self.assertSource(plannerText, contains: "static func createBranch")
        Self.assertSource(plannerText, contains: "static func remove")
        Self.assertSource(plannerText, contains: "static func prune")
    }

    private func assertWorktreeExtensionDelegation(_ worktreeExtensionText: String) {
        Self.assertSource(worktreeExtensionText, contains: "extension QuillCodeWorkspaceModel")
        Self.assertSource(worktreeExtensionText, contains: "WorkspaceWorktreeToolCallPlanner.create")
        Self.assertSource(worktreeExtensionText, contains: "WorkspaceWorktreeToolCallPlanner.createBranch")
        Self.assertSource(worktreeExtensionText, contains: "WorkspaceWorktreeToolCallPlanner.remove")
        Self.assertSource(worktreeExtensionText, contains: "WorkspaceWorktreeToolCallPlanner.prune")
        Self.assertSource(worktreeExtensionText, contains: "WorkspaceWorktreeOpenEngine.localThread")
        Self.assertSource(worktreeExtensionText, contains: "WorkspaceWorktreeOpenEngine.remoteThread")
        Self.assertSource(worktreeExtensionText, contains: "openCreatedWorktreeThread")
    }

    private func assertWorktreeOwnershipExclusions(
        _ modelText: String,
        _ worktreeExtensionText: String
    ) {
        Self.assertSource(modelText, excludes: "public func createWorktree")
        Self.assertSource(modelText, excludes: "public func createBranchHere")
        Self.assertSource(modelText, excludes: "public func openWorktree")
        Self.assertSource(modelText, excludes: "public func removeWorktree")
        Self.assertSource(modelText, excludes: "public func pruneWorktrees")
        Self.assertSource(worktreeExtensionText, excludes: "ToolDefinition.gitWorktreeCreate.name")
        Self.assertSource(worktreeExtensionText, excludes: "ToolDefinition.gitWorktreeRemove.name")
        Self.assertSource(worktreeExtensionText, excludes: "ToolDefinition.gitWorktreePrune.name")
        Self.assertSource(worktreeExtensionText, excludes: "title: \"Worktree:")
        Self.assertSource(worktreeExtensionText, excludes: "Opened remote worktree `")
        Self.assertSource(worktreeExtensionText, excludes: "Opened worktree `")
    }
}
