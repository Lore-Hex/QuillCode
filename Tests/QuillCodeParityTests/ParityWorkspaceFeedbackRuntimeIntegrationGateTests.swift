import XCTest

final class ParityWorkspaceFeedbackRuntimeIntegrationGateTests: QuillCodeParityTestCase {
    func testFocusedArtifactTestsOwnSurfaceSpecificFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let toolCardSurfaceTests = try Self.appTestSourceText(named: "QuillCodeToolCardSurfaceTests.swift")

        Self.assertSource(toolCardSurfaceTests, containsAll: [
            "testArtifactStateDerivesLinksAndImagePreviews",
            "testArtifactStateDerivesDocumentPreviews"
        ])
        Self.assertSource(modelTests, excludesAll: [
            "testArtifactStateDerivesLinksAndImagePreviews",
            "testArtifactStateDerivesDocumentPreviews"
        ])
    }

    func testWorkspaceRuntimeIssueIntegrationTestsOwnModelRuntimeIssueFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let runtimeIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceRuntimeIssueIntegrationTests.swift"
        )

        let runtimeIssueFlowTests = [
            "testApplyRuntimeRefreshesAgentStatus",
            "testRuntimeIssueSurfacesMissingTrustedRouterSignIn",
            "testRuntimeIssueNormalizesRejectedTrustedRouterKey",
            "testRuntimeIssueNormalizesTrustedRouterRateLimit",
            "testRuntimeIssueIncludesRedactedDiagnostics",
            "testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError"
        ]

        Self.assertSource(runtimeIntegrationTests, containsAll: runtimeIssueFlowTests)
        Self.assertSource(modelTests, excludesAll: runtimeIssueFlowTests)
    }
}
