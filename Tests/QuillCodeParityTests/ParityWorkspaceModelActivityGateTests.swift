import XCTest

final class ParityWorkspaceModelActivityGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesRetryPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let retryPlannerText = try Self.appSourceText(named: "WorkspaceRetryPlanner.swift")
        let retryPlannerTests = try Self.appTestSourceText(named: "WorkspaceRetryPlannerTests.swift")

        XCTAssertTrue(retryPlannerText.contains("enum WorkspaceRetryPlanner"), "Retry planning should live in a focused helper.")
        XCTAssertTrue(retryPlannerText.contains("static func canRetryLastUserTurn"), "Retry availability should be directly testable.")
        XCTAssertTrue(retryPlannerText.contains("static func retryDraft"), "Retry draft selection should be directly testable.")
        XCTAssertTrue(composerText.contains("WorkspaceRetryPlanner.canRetryLastUserTurn"), "WorkspaceModel composer APIs should delegate retry availability.")
        XCTAssertTrue(composerText.contains("WorkspaceRetryPlanner.retryDraft"), "WorkspaceModel composer APIs should delegate retry draft selection.")
        XCTAssertTrue(retryPlannerTests.contains("testRetryDraftUsesLatestNonEmptyUserMessageAndPreservesOriginalText"), "Retry draft behavior should have focused coverage.")
        XCTAssertTrue(retryPlannerTests.contains("testRetryRequiresUserMessageAndIdleComposer"), "Retry availability should have focused coverage.")
        XCTAssertFalse(modelText.contains("messages.last(where:"), "WorkspaceModel should not scan transcript messages for retry drafts.")
        XCTAssertFalse(modelText.contains("messages.contains {"), "WorkspaceModel should not own retry availability scans.")
        XCTAssertFalse(modelText.contains("WorkspaceRetryPlanner.canRetryLastUserTurn"), "WorkspaceModel.swift should not own retry availability APIs.")
    }

    func testWorkspaceActivityIntegrationTestsOwnModelActivityFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let activityIntegrationTests = try Self.appTestSourceText(named: "WorkspaceActivityIntegrationTests.swift")

        XCTAssertTrue(activityIntegrationTests.contains("testPlanUpdateToolRecordsNormalizedActivityPlan"), "Plan-update activity integration should live in focused activity tests.")
        XCTAssertTrue(activityIntegrationTests.contains("testPlanUpdateToolRejectsMultipleRunningSteps"), "Plan-update rejection integration should live in focused activity tests.")
        XCTAssertFalse(modelTests.contains("testPlanUpdateToolRecordsNormalizedActivityPlan"), "WorkspaceModelTests should not own plan-update activity integration flows.")
        XCTAssertFalse(modelTests.contains("testPlanUpdateToolRejectsMultipleRunningSteps"), "WorkspaceModelTests should not own plan-update rejection integration flows.")
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

        XCTAssertTrue(surfaceText.contains("public struct WorkspaceActivitySurface"), "Activity surface payload should keep the public DTO entry point.")
        XCTAssertTrue(surfaceText.contains("WorkspaceActivitySurfaceBuilder.sections"), "Activity surface should delegate section construction.")
        XCTAssertTrue(surfaceText.contains("WorkspaceActivitySurfaceBuilder.planItems"), "Activity surface should delegate derived task-plan rows.")
        XCTAssertTrue(builderText.contains("enum WorkspaceActivitySurfaceBuilder"), "Activity derivation should live in a focused builder.")
        XCTAssertTrue(builderText.contains("WorkspaceActivityPlanSurfaceBuilder.fallbackItems"), "Activity builder should delegate fallback plan rows.")
        XCTAssertTrue(builderText.contains("WorkspaceActivityPlanSurfaceBuilder.authoredItems"), "Activity builder should delegate authored plan rows.")
        XCTAssertTrue(builderText.contains("WorkspaceActivityEventSurfaceBuilder.recentSteps"), "Activity builder should delegate event-row projection.")
        XCTAssertTrue(builderText.contains("WorkspaceActivitySourceSurfaceBuilder.items"), "Activity builder should delegate source-row projection.")
        XCTAssertTrue(builderText.contains("instructionConflictItems"), "Activity builder should promote instruction conflicts into a first-class review section.")
        XCTAssertTrue(builderText.contains("WorkspaceActivityHandoffSummaryBuilder.summary"), "Activity builder should delegate handoff summary copy.")
        XCTAssertTrue(planBuilderText.contains("enum WorkspaceActivityPlanSurfaceBuilder"), "Plan-row derivation should have a focused owner.")
        XCTAssertTrue(planBuilderText.contains("static func authoredItems"), "Authored plan rows should stay beside fallback plan rows.")
        XCTAssertTrue(planBuilderText.contains("private static func reviewState"), "Fallback plan review-state copy should stay in the plan builder.")
        XCTAssertTrue(eventBuilderText.contains("enum WorkspaceActivityEventSurfaceBuilder"), "Event-row projection should have a focused owner.")
        XCTAssertTrue(eventBuilderText.contains("private static func eventKindLabel"), "Event labeling should stay beside event-row projection.")
        XCTAssertTrue(sourceBuilderText.contains("enum WorkspaceActivitySourceSurfaceBuilder"), "Instruction and memory source rows should have a focused owner.")
        XCTAssertTrue(handoffBuilderText.contains("enum WorkspaceActivityHandoffSummaryBuilder"), "Handoff summary copy should have a focused owner.")
        XCTAssertTrue(textHelperText.contains("enum WorkspaceActivityText"), "Shared activity text formatting should not be copied between builders.")
        XCTAssertTrue(statusText.contains("enum ActivityStatusLabel"), "Activity status labels should be shared by focused builders.")
        XCTAssertTrue(sectionText.contains("public enum ActivitySectionKind"), "Activity section metadata should live beside section DTOs.")
        XCTAssertTrue(sectionText.contains("case instructionReview"), "Instruction conflict review should be a first-class Activity section.")
        XCTAssertTrue(sectionText.contains("public struct ActivitySectionSurface"), "Activity section DTOs should live outside the root surface file.")
        XCTAssertTrue(sectionText.contains("public struct ActivityItemSurface"), "Activity item DTOs should live outside the root surface file.")
        XCTAssertFalse(surfaceText.contains("private static func planItems"), "Activity surface should not own plan derivation.")
        XCTAssertFalse(surfaceText.contains("private static func recentSteps"), "Activity surface should not own event-row derivation.")
        XCTAssertFalse(surfaceText.contains("public enum ActivitySectionKind"), "Activity surface should not own section metadata.")
        XCTAssertFalse(builderText.contains("private static func eventKindLabel"), "Top-level activity builder should not own event labeling.")
        XCTAssertFalse(builderText.contains("private static func reviewState"), "Top-level activity builder should not own fallback plan review state.")
        XCTAssertFalse(builderText.contains("Latest answer:"), "Top-level activity builder should not own handoff summary prose.")
    }

    func testWorkspaceToolCardIntegrationTestsOwnModelToolCardFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let toolCardIntegrationTests = try Self.appTestSourceText(named: "WorkspaceToolCardIntegrationTests.swift")

        XCTAssertTrue(toolCardIntegrationTests.contains("testToolCardsRepresentActionableApprovalReview"), "Tool-card review projection should live in focused tool-card integration tests.")
        XCTAssertTrue(toolCardIntegrationTests.contains("testToolCardApprovalActionRecordsDecisionAndRunsTool"), "Tool-card approval execution should live in focused tool-card integration tests.")
        XCTAssertTrue(toolCardIntegrationTests.contains("testToolCardsRepresentStoppedActiveToolAsFailed"), "Stopped tool-card projection should live in focused tool-card integration tests.")
        XCTAssertFalse(modelTests.contains("testToolCardsRepresentActionableApprovalReview"), "WorkspaceModelTests should not own actionable approval-card projection.")
        XCTAssertFalse(modelTests.contains("testToolCardApprovalActionRecordsDecisionAndRunsTool"), "WorkspaceModelTests should not own approval-card execution integration.")
        XCTAssertFalse(modelTests.contains("testToolCardsRepresentStoppedActiveToolAsFailed"), "WorkspaceModelTests should not own stopped tool-card projection.")
    }

    func testWorkspaceModelTestsRemainRetired() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")

        XCTAssertTrue(modelTests.contains("Intentionally empty"), "WorkspaceModelTests should stay as a visible retirement marker.")
        XCTAssertFalse(modelTests.contains("func test"), "New workspace integration coverage should use a focused feature test suite, not WorkspaceModelTests.")
    }

    func testFocusedWorkspaceUnitSuitesUseSharedTemporaryDirectorySupport() throws {
        let supportText = try Self.appTestSourceText(named: "WorkspaceModelIntegrationTestSupport.swift")
        XCTAssertTrue(supportText.contains("extension XCTestCase"), "App integration temp helpers should live on XCTestCase so they can register teardown cleanup.")
        XCTAssertTrue(supportText.contains("func makeTempDirectory() throws -> URL"), "Legacy app integration tests should route through the shared temp-directory wrapper.")
        XCTAssertTrue(supportText.contains("makeQuillCodeTestDirectory()"), "App integration temp helpers should delegate to the teardown-backed helper.")

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
            XCTAssertTrue(
                suiteText.contains("makeQuillCodeTestDirectory()"),
                "\(suiteName) should use the shared teardown-backed test directory helper."
            )
            XCTAssertFalse(
                suiteText.contains("private func temporaryDirectory"),
                "\(suiteName) should not reintroduce a private temp-directory helper."
            )
            XCTAssertFalse(
                suiteText.contains("FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)"),
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
            XCTAssertFalse(
                suiteText.contains("private func makeTempDirectory()"),
                "\(suiteName) should use WorkspaceModelIntegrationTestSupport.makeTempDirectory()."
            )
            XCTAssertFalse(
                suiteText.contains("NSTemporaryDirectory()"),
                "\(suiteName) should not build untracked temp directories inline."
            )
            XCTAssertFalse(
                suiteText.contains("FileManager.default.temporaryDirectory"),
                "\(suiteName) should not build untracked temp directories inline."
            )
        }
    }

}
