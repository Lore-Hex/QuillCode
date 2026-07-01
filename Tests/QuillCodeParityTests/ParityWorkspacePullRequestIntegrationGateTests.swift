import XCTest

final class ParityWorkspacePullRequestIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspacePullRequestIntegrationTestsOwnModelPullRequestFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let pullRequestTests = try Self.appTestSourceText(named: "WorkspacePullRequestIntegrationTests.swift")

        [
            "testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH",
            "testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH",
            "testWorkspacePullRequestCommandsPrefillComposer",
            "makeRemotePullRequestFixture"
        ].forEach {
            Self.assertSource(pullRequestTests, contains: $0)
            Self.assertSource(modelTests, excludes: $0)
        }
    }
}
