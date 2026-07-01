import XCTest

final class ParityWorkspaceRemoteProjectIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceRemoteProjectIntegrationTestsOwnModelRemoteProjectFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let remoteProjectTests = [
            try Self.appTestSourceText(named: "WorkspaceRemoteProjectIntegrationTests.swift"),
            try Self.appTestSourceText(named: "WorkspaceRemoteProjectShellGitIntegrationTests.swift"),
            try Self.appTestSourceText(named: "WorkspaceRemoteProjectPullRequestIntegrationTests.swift"),
            try Self.appTestSourceText(named: "WorkspaceRemoteProjectWorktreeIntegrationTests.swift")
        ].joined(separator: "\n")

        [
            "testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions",
            "testRemoteProjectAgentRunsShellThroughSSH",
            "testRemoteProjectAgentCreatesPullRequestThroughSSH",
            "testRemoteProjectRejectsUnsafeWorktreePathBeforeSSH"
        ].forEach {
            Self.assertSource(remoteProjectTests, contains: $0)
            Self.assertSource(modelTests, excludes: $0)
        }
    }
}
