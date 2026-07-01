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

    private func assertWorktreeRequestAndEngineContracts(
        _ requestsText: String,
        _ engineText: String,
        _ plannerText: String
    ) {
        Self.assertSource(requestsText, contains: "public struct WorkspaceWorktreeCreateRequest")
        Self.assertSource(requestsText, contains: "public struct WorkspaceWorktreeRemoveRequest")
        Self.assertSource(requestsText, contains: "public struct WorkspaceWorktreePruneRequest")
        Self.assertSource(engineText, contains: "struct WorkspaceWorktreeOpenEngine")
        Self.assertSource(engineText, contains: "static func localThread")
        Self.assertSource(engineText, contains: "static func remoteThread")
        Self.assertSource(plannerText, contains: "enum WorkspaceWorktreeToolCallPlanner")
        Self.assertSource(plannerText, contains: "static func create")
        Self.assertSource(plannerText, contains: "static func remove")
        Self.assertSource(plannerText, contains: "static func prune")
    }

    private func assertWorktreeExtensionDelegation(_ worktreeExtensionText: String) {
        Self.assertSource(worktreeExtensionText, contains: "extension QuillCodeWorkspaceModel")
        Self.assertSource(worktreeExtensionText, contains: "WorkspaceWorktreeToolCallPlanner.create")
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
