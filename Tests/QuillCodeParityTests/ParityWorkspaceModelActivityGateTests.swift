import XCTest

final class ParityWorkspaceModelActivityGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesRetryPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let retryPlannerText = try Self.appSourceText(named: "WorkspaceRetryPlanner.swift")
        let retryPlannerTests = try Self.appTestSourceText(named: "WorkspaceRetryPlannerTests.swift")

        assertContains(
            retryPlannerText,
            "enum WorkspaceRetryPlanner",
            "Retry planning should live in a focused helper."
        )
        assertContains(retryPlannerText, "static func canRetryLastUserTurn", "Retry availability should be testable.")
        assertContains(retryPlannerText, "static func retryDraft", "Retry draft selection should be testable.")
        assertContains(
            composerText,
            "WorkspaceRetryPlanner.canRetryLastUserTurn",
            "Composer should delegate retry availability."
        )
        assertContains(
            composerText,
            "WorkspaceRetryPlanner.retryDraft",
            "Composer should delegate retry draft selection."
        )
        assertContains(
            retryPlannerTests,
            "testRetryDraftUsesLatestNonEmptyUserMessageAndPreservesOriginalText",
            "Retry draft behavior should have focused coverage."
        )
        assertContains(
            retryPlannerTests,
            "testRetryRequiresUserMessageAndIdleComposer",
            "Retry availability should have focused coverage."
        )
        assertExcludes(modelText, "messages.last(where:", "WorkspaceModel should not scan transcript messages.")
        assertExcludes(modelText, "messages.contains {", "WorkspaceModel should not own retry availability scans.")
        assertExcludes(
            modelText,
            "WorkspaceRetryPlanner.canRetryLastUserTurn",
            "WorkspaceModel.swift should not own retry availability APIs."
        )
    }

    func testWorkspaceActivityIntegrationTestsOwnModelActivityFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let activityIntegrationTests = try Self.appTestSourceText(named: "WorkspaceActivityIntegrationTests.swift")
        let instructionTests = try Self.appTestSourceText(named: "WorkspaceActivityInstructionIntegrationTests.swift")
        let planHandoffTests = try Self.appTestSourceText(named: "WorkspaceActivityPlanHandoffIntegrationTests.swift")

        assertContains(
            instructionTests,
            "testActivitySourcesSurfaceInstructionDiagnostics",
            "Instruction source coverage should stay in focused instruction activity tests."
        )
        assertContains(
            instructionTests,
            "testActivitySourcesSurfaceInstructionSemanticConflictDiagnostics",
            "Instruction-review coverage should stay in focused instruction activity tests."
        )
        assertContains(
            planHandoffTests,
            "testPlanUpdateToolRecordsNormalizedActivityPlan",
            "Plan-update coverage should stay in focused plan/handoff activity tests."
        )
        assertContains(
            planHandoffTests,
            "testPlanUpdateToolRejectsMultipleRunningSteps",
            "Plan-update rejection coverage should stay in focused plan/handoff activity tests."
        )
        assertExcludes(
            activityIntegrationTests,
            "testActivitySourcesSurfaceInstructionDiagnostics",
            "Surface/context activity tests should not own instruction source flows."
        )
        assertExcludes(
            activityIntegrationTests,
            "testActivitySourcesSurfaceInstructionSemanticConflictDiagnostics",
            "Surface/context activity tests should not own instruction-review flows."
        )
        assertExcludes(
            activityIntegrationTests,
            "testPlanUpdateToolRecordsNormalizedActivityPlan",
            "Surface/context activity tests should not own plan-update tool flows."
        )
        assertExcludes(
            activityIntegrationTests,
            "testPlanUpdateToolRejectsMultipleRunningSteps",
            "Surface/context activity tests should not own plan-update rejection flows."
        )
        assertExcludes(
            modelTests,
            "testActivitySourcesSurfaceInstructionDiagnostics",
            "WorkspaceModelTests should not own instruction source activity flows."
        )
        assertExcludes(
            modelTests,
            "testPlanUpdateToolRecordsNormalizedActivityPlan",
            "WorkspaceModelTests should not own plan-update activity flows."
        )
        assertExcludes(
            modelTests,
            "testPlanUpdateToolRejectsMultipleRunningSteps",
            "WorkspaceModelTests should not own plan-update rejection flows."
        )
    }

    func testWorkspaceActivitySurfaceUsesFocusedBuilderAndSectionTypes() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceActivitySurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceActivitySurfaceBuilder.swift")
        let sectionText = try Self.appSourceText(named: "WorkspaceActivitySectionSurface.swift")
        let planBuilderText = try Self.appSourceText(named: "WorkspaceActivityPlanSurfaceBuilder.swift")
        let eventBuilderText = try Self.appSourceText(named: "WorkspaceActivityEventSurfaceBuilder.swift")
        let sourceBuilderText = try Self.appSourceText(named: "WorkspaceActivitySourceSurfaceBuilder.swift")
        let handoffBuilderText = try Self.appSourceText(named: "WorkspaceActivityHandoffSummaryBuilder.swift")
        let textHelperText = try Self.appSourceText(named: "WorkspaceActivityText.swift")
        let statusText = try Self.appSourceText(named: "WorkspaceActivityStatusLabel.swift")

        assertContains(
            surfaceText,
            "public struct WorkspaceActivitySurface",
            "Activity surface should keep the public DTO entry point."
        )
        assertContains(
            surfaceText,
            "WorkspaceActivitySurfaceBuilder.sections",
            "Activity surface should delegate section construction."
        )
        assertContains(
            surfaceText,
            "WorkspaceActivitySurfaceBuilder.planItems",
            "Activity surface should delegate task-plan row derivation."
        )
        assertContains(builderText, "enum WorkspaceActivitySurfaceBuilder", "Activity derivation should be focused.")
        assertContains(
            builderText,
            "WorkspaceActivityPlanSurfaceBuilder.fallbackItems",
            "Fallback rows should delegate."
        )
        assertContains(
            builderText,
            "WorkspaceActivityPlanSurfaceBuilder.authoredItems",
            "Authored rows should delegate."
        )
        assertContains(builderText, "WorkspaceActivityEventSurfaceBuilder.recentSteps", "Event rows should delegate.")
        assertContains(builderText, "WorkspaceActivitySourceSurfaceBuilder.items", "Source rows should delegate.")
        assertContains(builderText, "instructionConflictItems", "Instruction conflicts should be first-class.")
        assertContains(builderText, "WorkspaceActivityHandoffSummaryBuilder.summary", "Handoff copy should delegate.")
        assertContains(planBuilderText, "enum WorkspaceActivityPlanSurfaceBuilder", "Plan rows need a focused owner.")
        assertContains(
            planBuilderText,
            "static func authoredItems",
            "Authored plan rows should stay with fallback rows."
        )
        assertContains(planBuilderText, "private static func reviewState", "Fallback review-state copy belongs here.")
        assertContains(
            eventBuilderText,
            "enum WorkspaceActivityEventSurfaceBuilder",
            "Event rows need a focused owner."
        )
        assertContains(
            eventBuilderText,
            "private static func eventKindLabel",
            "Event labeling belongs with event rows."
        )
        assertContains(
            sourceBuilderText,
            "enum WorkspaceActivitySourceSurfaceBuilder",
            "Source rows need a focused owner."
        )
        assertContains(
            handoffBuilderText,
            "enum WorkspaceActivityHandoffSummaryBuilder",
            "Handoff copy needs a focused owner."
        )
        assertContains(textHelperText, "enum WorkspaceActivityText", "Shared activity text should not be copied.")
        assertContains(statusText, "enum ActivityStatusLabel", "Activity status labels should be shared.")
        assertContains(
            sectionText,
            "public enum ActivitySectionKind",
            "Section metadata should live beside section DTOs."
        )
        assertContains(sectionText, "case instructionReview", "Instruction review should be a first-class section.")
        assertContains(
            sectionText,
            "public struct ActivitySectionSurface",
            "Activity section DTOs should live outside the root surface file."
        )
        assertContains(
            sectionText,
            "public struct ActivityItemSurface",
            "Activity item DTOs should live outside the root surface file."
        )
        assertExcludes(surfaceText, "private static func planItems", "Activity surface should not own plan derivation.")
        assertExcludes(surfaceText, "private static func recentSteps", "Activity surface should not own event rows.")
        assertExcludes(surfaceText, "public enum ActivitySectionKind", "Activity surface should not own sections.")
        assertExcludes(builderText, "private static func eventKindLabel", "Top-level builder should not own labels.")
        assertExcludes(builderText, "private static func reviewState", "Top-level builder should not own review state.")
        assertExcludes(builderText, "Latest answer:", "Top-level builder should not own handoff prose.")
    }

    func testWorkspaceToolCardIntegrationTestsOwnModelToolCardFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let toolCardIntegrationTests = try Self.appTestSourceText(named: "WorkspaceToolCardIntegrationTests.swift")

        assertContains(
            toolCardIntegrationTests,
            "testToolCardsRepresentActionableApprovalReview",
            "Tool-card review projection should live in focused integration tests."
        )
        assertContains(
            toolCardIntegrationTests,
            "testToolCardApprovalActionRecordsDecisionAndRunsTool",
            "Tool-card approval execution should live in focused integration tests."
        )
        assertContains(
            toolCardIntegrationTests,
            "testToolCardsRepresentStoppedActiveToolAsFailed",
            "Stopped tool-card projection should live in focused integration tests."
        )
        assertExcludes(
            modelTests,
            "testToolCardsRepresentActionableApprovalReview",
            "WorkspaceModelTests should not own approval-card projection."
        )
        assertExcludes(
            modelTests,
            "testToolCardApprovalActionRecordsDecisionAndRunsTool",
            "WorkspaceModelTests should not own approval-card execution."
        )
        assertExcludes(
            modelTests,
            "testToolCardsRepresentStoppedActiveToolAsFailed",
            "WorkspaceModelTests should not own stopped tool-card projection."
        )
    }

    func testWorkspaceModelTestsRemainRetired() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")

        assertContains(modelTests, "Intentionally empty", "WorkspaceModelTests should stay as a retirement marker.")
        assertExcludes(modelTests, "func test", "New workspace coverage should use focused feature test suites.")
    }

    func testFocusedWorkspaceUnitSuitesUseSharedTemporaryDirectorySupport() throws {
        let supportText = try Self.appTestSourceText(named: "WorkspaceModelIntegrationTestSupport.swift")
        assertContains(supportText, "extension XCTestCase", "Temp helpers should register teardown cleanup.")
        assertContains(
            supportText,
            "func makeTempDirectory() throws -> URL",
            "Legacy app integration tests should use the shared wrapper."
        )
        assertContains(
            supportText,
            "makeQuillCodeTestDirectory()",
            "App integration temp helpers should delegate to teardown-backed support."
        )

        let suiteNames = [
            "WorkspaceAgentRunContextBuilderTests.swift",
            "WorkspaceAgentSendSessionFactoryTests.swift",
            "WorkspaceAgentSendSessionTests.swift",
            "WorkspaceMemoryEngineTests.swift",
            "WorkspaceTerminalEngineTests.swift",
            "WorkspaceToolCallExecutorTests.swift"
        ]

        for suiteName in suiteNames {
            let suiteText = try Self.appTestSourceText(named: suiteName)
            assertContains(
                suiteText,
                "makeQuillCodeTestDirectory()",
                "\(suiteName) should use the shared teardown-backed test directory helper."
            )
            assertExcludes(
                suiteText,
                "private func temporaryDirectory",
                "\(suiteName) should not reintroduce a private temp-directory helper."
            )
            assertExcludes(
                suiteText,
                "FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)",
                "\(suiteName) should not build untracked temp directories inline."
            )
        }

        let integrationSuiteNames = [
            "WorkspaceBrowserIntegrationTests.swift",
            "WorkspaceBrowserLocationResolverTests.swift",
            "WorkspaceCommandPlanExecutorTests.swift",
            "WorkspaceRemoteProjectToolExecutorTests.swift",
            "WorkspaceSlashCommandIntegrationTests.swift",
            "WorkspaceSurfaceTests.swift"
        ]
        for suiteName in integrationSuiteNames {
            let suiteText = try Self.appTestSourceText(named: suiteName)
            assertExcludes(
                suiteText,
                "private func makeTempDirectory()",
                "\(suiteName) should use WorkspaceModelIntegrationTestSupport.makeTempDirectory()."
            )
            assertExcludes(
                suiteText,
                "NSTemporaryDirectory()",
                "\(suiteName) should not build untracked temp directories inline."
            )
            assertExcludes(
                suiteText,
                "FileManager.default.temporaryDirectory",
                "\(suiteName) should not build untracked temp directories inline."
            )
        }
    }

}

private func assertContains(
    _ text: String,
    _ needle: String,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(text.contains(needle), message, file: file, line: line)
}

private func assertExcludes(
    _ text: String,
    _ needle: String,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(text.contains(needle), message, file: file, line: line)
}
