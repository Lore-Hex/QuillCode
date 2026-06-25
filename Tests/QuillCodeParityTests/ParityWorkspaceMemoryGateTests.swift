import XCTest

final class ParityWorkspaceMemoryGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesMemoryCommandOrchestration() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceMemoryEngine.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceMemoryCommandTranscriptPlanner.swift")
        let errorText = try Self.appSourceText(named: "WorkspaceMemoryErrorMessageBuilder.swift")
        let contextUpdateText = try Self.appSourceText(named: "WorkspaceMemoryContextUpdatePlanner.swift")

        XCTAssertTrue(engineText.contains("enum WorkspaceMemoryEngine"), "Memory command orchestration should live in a focused engine.")
        XCTAssertTrue(engineText.contains("struct WorkspaceMemoryMutation"), "Memory command outcomes should use a typed mutation value.")
        XCTAssertTrue(modelText.contains("WorkspaceMemoryEngine.saveGlobal"), "WorkspaceModel should delegate global memory saves.")
        XCTAssertTrue(modelText.contains("WorkspaceMemoryEngine.deleteGlobal"), "WorkspaceModel should delegate global memory deletion.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.globalMemories"), "WorkspaceModel should delegate global memory reloads through the project context refresher.")
        XCTAssertTrue(modelText.contains("WorkspaceMemoryEngine.contextUpdate"), "WorkspaceModel should delegate memory context update construction.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceMemoryCommandTranscriptPlanner"), "Memory command transcript copy should live in a focused planner.")
        XCTAssertTrue(errorText.contains("enum WorkspaceMemoryErrorMessageBuilder"), "Memory write and delete errors should share one user-facing formatter.")
        XCTAssertTrue(contextUpdateText.contains("struct WorkspaceMemoryContextUpdatePlanner"), "Memory thread context updates should live in a focused planner.")
        for delegatedCall in [
            "WorkspaceMemoryCommandTranscriptPlanner.memorySaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary",
            "WorkspaceMemoryErrorMessageBuilder.userFacingMessage",
            "WorkspaceMemoryContextUpdatePlanner.globalMemoryChanged"
        ] {
            XCTAssertTrue(engineText.contains(delegatedCall), "WorkspaceMemoryEngine should delegate \(delegatedCall).")
        }
        XCTAssertFalse(modelText.contains("It will be included as background context in future turns."), "WorkspaceModel should not own memory save success copy.")
        XCTAssertFalse(modelText.contains("Memory not saved"), "WorkspaceModel should not own memory save failure title copy.")
        XCTAssertFalse(modelText.contains("It will no longer be included as background context."), "WorkspaceModel should not own memory delete success copy.")
        XCTAssertFalse(modelText.contains("Memory not deleted"), "WorkspaceModel should not own memory delete failure title copy.")
        XCTAssertFalse(modelText.contains("Forgot memory:"), "WorkspaceModel should not own memory delete summary copy.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.saveGlobal"), "WorkspaceModel should not write memory files directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.deleteGlobal"), "WorkspaceModel should not delete memory files directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.loadGlobal"), "WorkspaceModel should not reload global memories directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteDeleteError.deleteFailed.localizedDescription"), "WorkspaceModel should not format memory delete errors directly.")
        XCTAssertFalse(modelText.contains("payloadJSON: note.relativePath"), "WorkspaceModel should not build memory change events inline.")
    }

    func testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let memoryIntegrationTests = try Self.appTestSourceText(named: "WorkspaceMemoryIntegrationTests.swift")

        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface"), "Workspace memory integration should live in a focused test file.")
        XCTAssertTrue(memoryIntegrationTests.contains("testSurfaceIncludesMemorySummariesAndCommand"), "Memory surface summaries should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface"), "Slash remember integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface"), "Agent memory tool integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface"), "Memory delete integration should live in focused memory tests.")
        XCTAssertFalse(modelTests.contains("testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface"), "WorkspaceModelTests should not own memory integration flows.")
        XCTAssertFalse(modelTests.contains("testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own slash memory integration flows.")
        XCTAssertFalse(modelTests.contains("testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own agent memory integration flows.")
        XCTAssertFalse(modelTests.contains("testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own memory delete integration flows.")
        XCTAssertFalse(broadSurfaceTests.contains("testSurfaceIncludesMemorySummariesAndCommand"), "WorkspaceSurfaceTests should not own memory surface summaries.")
    }

    func testPlaywrightMemoryFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let memoriesSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("memories.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let memoryFlowName = "shows memories from sidebar and command palette"

        XCTAssertTrue(memoriesSpecText.contains("harnessURL()"), "Focused memory flows should reuse the shared harness URL helper.")
        XCTAssertTrue(memoriesSpecText.contains("clickSidebarTool"), "Focused memory flows should cover sidebar and command-palette memory entry points.")
        XCTAssertTrue(memoriesSpecText.contains("project-memories-status"), "Focused memory flows should cover project memory count updates.")
        XCTAssertTrue(memoriesSpecText.contains("/remember Prefer small reviewable commits"), "Focused memory flows should cover memory creation through slash command text.")
        XCTAssertTrue(memoriesSpecText.contains("memory-delete"), "Focused memory flows should cover memory deletion.")
        XCTAssertTrue(memoriesSpecText.contains(memoryFlowName), "\(memoryFlowName) should live in memories.spec.ts.")
        XCTAssertFalse(coreSpecText.contains(memoryFlowName), "\(memoryFlowName) should not drift back into core.spec.ts.")
    }
}
