import XCTest

final class ParityWorkspaceFeedbackRuntimeIntegrationGateTests: QuillCodeParityTestCase {
    func testFocusedFeedbackAndArtifactTestsOwnSurfaceSpecificFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let feedbackExtensionText = try Self.appSourceText(named: "WorkspaceModelFeedback.swift")
        let feedbackPlannerText = try Self.appSourceText(
            named: "WorkspaceMessageFeedbackPlanner.swift"
        )
        let feedbackPlannerTests = try Self.appTestSourceText(
            named: "WorkspaceMessageFeedbackPlannerTests.swift"
        )
        let feedbackIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceFeedbackIntegrationTests.swift"
        )
        let toolCardSurfaceTests = try Self.appTestSourceText(
            named: "QuillCodeToolCardSurfaceTests.swift"
        )

        Self.assertSource(feedbackExtensionText, containsAll: [
            "public func setMessageFeedback",
            "WorkspaceMessageFeedbackPlanner.event"
        ])

        Self.assertSource(feedbackPlannerText, containsAll: [
            "enum WorkspaceMessageFeedbackPlanner",
            "static func summary"
        ])

        Self.assertSource(feedbackPlannerTests, containsAll: [
            "testEventEncodesHelpfulFeedbackPayloadAndSummary",
            "testSummaryCoversBothFeedbackValues"
        ])

        Self.assertSource(feedbackIntegrationTests, contains: "testMessageFeedbackIsStoredAndSurfaced")

        Self.assertSource(toolCardSurfaceTests, containsAll: [
            "testArtifactStateDerivesLinksAndImagePreviews",
            "testArtifactStateDerivesDocumentPreviews"
        ])

        Self.assertSource(modelText, excludesAll: [
            "public func setMessageFeedback",
            "Marked assistant response helpful"
        ])

        Self.assertSource(modelTests, excludesAll: [
            "testMessageFeedbackIsStoredAndSurfaced",
            "testArtifactStateDerivesLinksAndImagePreviews",
            "testArtifactStateDerivesDocumentPreviews"
        ])
    }

    func testWorkspaceRuntimeIssueIntegrationTestsOwnModelRuntimeIssueFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let runtimeIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceRuntimeIssueIntegrationTests.swift"
        )

        Self.assertSource(runtimeIntegrationTests, containsAll: [
            "testApplyRuntimeRefreshesAgentStatus",
            "testRuntimeIssueSurfacesMissingTrustedRouterSignIn",
            "testRuntimeIssueNormalizesRejectedTrustedRouterKey",
            "testRuntimeIssueNormalizesTrustedRouterRateLimit",
            "testRuntimeIssueIncludesRedactedDiagnostics",
            "testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError"
        ])

        Self.assertSource(modelTests, excludesAll: [
            "testApplyRuntimeRefreshesAgentStatus",
            "testRuntimeIssueSurfacesMissingTrustedRouterSignIn",
            "testRuntimeIssueNormalizesRejectedTrustedRouterKey",
            "testRuntimeIssueNormalizesTrustedRouterRateLimit",
            "testRuntimeIssueIncludesRedactedDiagnostics",
            "testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError"
        ])
    }

    func testWorkspaceModelTestsDoNotOwnRuntimeFactoryCoverage() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let runtimeFactoryTests = try Self.appTestSourceText(
            named: "WorkspaceRuntimeFactoryTests.swift"
        )

        Self.assertSource(runtimeFactoryTests, containsAll: [
            "QuillCodeRuntimeFactory(",
            "fetchModelCatalog",
            "QUILLCODE_USE_MOCK_LLM"
        ])

        Self.assertSource(modelTests, excludesAll: [
            "QuillCodeRuntimeFactory(",
            "func testRuntimeFactory"
        ])
    }
}
