import XCTest

final class ParityWorkspaceWorktreeIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceWorktreeIntegrationTestsOwnModelWorktreeFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let worktreeTests = try Self.appTestSourceText(named: "WorkspaceWorktreeIntegrationTests.swift")

        [
            "testWorkspaceCommandListsGitWorktrees",
            "testRemoteWorkspaceCommandListsGitWorktreesThroughSSH",
            "testWorkspaceWorktreeCommandsPrefillComposer",
            "testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit",
            "testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit"
        ].forEach {
            Self.assertSource(worktreeTests, contains: $0)
            Self.assertSource(modelTests, excludes: $0)
        }
    }

    func testWorkspaceModelDelegatesWorktreeOpenRecords() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let worktreeExtensionText = try Self.appSourceText(named: "WorkspaceModelWorktrees.swift")
        let requestsText = try Self.appSourceText(named: "WorkspaceWorktreeRequests.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceWorktreeOpenEngine.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceWorktreeToolCallPlanner.swift")

        [
            "public struct WorkspaceWorktreeCreateRequest",
            "public struct WorkspaceWorktreeRemoveRequest",
            "public struct WorkspaceWorktreePruneRequest"
        ].forEach { Self.assertSource(requestsText, contains: $0) }
        [
            "struct WorkspaceWorktreeOpenEngine",
            "static func localThread",
            "static func remoteThread"
        ].forEach { Self.assertSource(engineText, contains: $0) }
        [
            "enum WorkspaceWorktreeToolCallPlanner",
            "static func create",
            "static func remove",
            "static func prune"
        ].forEach { Self.assertSource(plannerText, contains: $0) }
        [
            "extension QuillCodeWorkspaceModel",
            "WorkspaceWorktreeToolCallPlanner.create",
            "WorkspaceWorktreeToolCallPlanner.remove",
            "WorkspaceWorktreeToolCallPlanner.prune",
            "WorkspaceWorktreeOpenEngine.localThread",
            "WorkspaceWorktreeOpenEngine.remoteThread",
            "openCreatedWorktreeThread"
        ].forEach { Self.assertSource(worktreeExtensionText, contains: $0) }
        [
            "public func createWorktree",
            "public func openWorktree",
            "public func removeWorktree",
            "public func pruneWorktrees"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
        [
            "ToolDefinition.gitWorktreeCreate.name",
            "ToolDefinition.gitWorktreeRemove.name",
            "ToolDefinition.gitWorktreePrune.name",
            "title: \"Worktree:",
            "Opened remote worktree `",
            "Opened worktree `"
        ].forEach { Self.assertSource(worktreeExtensionText, excludes: $0) }
    }
}
