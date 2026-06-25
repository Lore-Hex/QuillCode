import XCTest

final class ParityWorkspaceMemoryGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesMemoryCommandOrchestration() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let memoryModelText = try Self.appSourceText(named: "WorkspaceModelMemory.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceMemoryEngine.swift")
        let remoteUpdaterText = try Self.appSourceText(named: "WorkspaceRemoteProjectMemoryUpdater.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceMemoryCommandTranscriptPlanner.swift")
        let errorText = try Self.appSourceText(named: "WorkspaceMemoryErrorMessageBuilder.swift")
        let contextUpdateText = try Self.appSourceText(named: "WorkspaceMemoryContextUpdatePlanner.swift")

        XCTAssertTrue(engineText.contains("enum WorkspaceMemoryEngine"), "Memory command orchestration should live in a focused engine.")
        XCTAssertTrue(engineText.contains("struct WorkspaceMemoryMutation"), "Memory command outcomes should use a typed mutation value.")
        XCTAssertTrue(remoteUpdaterText.contains("enum WorkspaceRemoteProjectMemoryUpdater"), "SSH Remote memory writes should live in a focused remote updater.")
        XCTAssertTrue(remoteUpdaterText.contains("enum WorkspaceRemoteProjectMemoryDeleter"), "SSH Remote memory deletion should stay with the focused remote memory mutation helpers.")
        XCTAssertTrue(remoteUpdaterText.contains("MemoryNoteLoader.validatedUpdateContent"), "Remote project memory edits should share local memory validation.")
        XCTAssertTrue(memoryModelText.contains("func runRememberSlashCommand"), "Memory slash-command execution should live in the focused WorkspaceModelMemory extension.")
        XCTAssertTrue(memoryModelText.contains("func prepareEditMemory"), "Memory edit preparation should live in the focused WorkspaceModelMemory extension.")
        XCTAssertTrue(memoryModelText.contains("func runEditMemorySlashCommand"), "Memory edit slash-command execution should live in the focused WorkspaceModelMemory extension.")
        XCTAssertTrue(memoryModelText.contains("func deleteMemory"), "Memory deletion should route global, local project, and SSH Remote project memories through the focused WorkspaceModelMemory extension.")
        XCTAssertTrue(memoryModelText.contains("func deleteGlobalMemory"), "Memory deletion execution should live in the focused WorkspaceModelMemory extension.")
        XCTAssertTrue(memoryModelText.contains("func refreshThreadMemoryContext"), "Thread memory refresh should live in the focused WorkspaceModelMemory extension.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceMemoryEngine.saveGlobal"), "WorkspaceModelMemory should delegate global memory saves.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceMemoryEngine.updateGlobal"), "WorkspaceModelMemory should delegate global memory updates.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceMemoryEngine.updateProject"), "WorkspaceModelMemory should delegate project memory updates.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceMemoryEngine.updateRemoteProject"), "WorkspaceModelMemory should delegate SSH Remote project memory updates.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceMemoryEngine.deleteGlobal"), "WorkspaceModelMemory should delegate global memory deletion.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceMemoryEngine.deleteProject"), "WorkspaceModelMemory should delegate local project memory deletion.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceMemoryEngine.deleteRemoteProject"), "WorkspaceModelMemory should delegate SSH Remote project memory deletion.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceProjectContextRefresher.globalMemories"), "WorkspaceModelMemory should delegate global memory reloads through the project context refresher.")
        XCTAssertTrue(memoryModelText.contains("WorkspaceMemoryEngine.contextUpdate"), "WorkspaceModelMemory should delegate memory context update construction.")
        XCTAssertFalse(modelText.contains("func runRememberSlashCommand"), "WorkspaceModel.swift should not own memory slash-command execution.")
        XCTAssertFalse(modelText.contains("func runEditMemorySlashCommand"), "WorkspaceModel.swift should not own memory edit slash-command execution.")
        XCTAssertFalse(modelText.contains("func deleteGlobalMemory"), "WorkspaceModel.swift should not own memory deletion execution.")
        XCTAssertFalse(modelText.contains("func applyGlobalMemoryMutation"), "WorkspaceModel.swift should not own global memory mutation application.")
        XCTAssertFalse(modelText.contains("func refreshThreadMemoryContext"), "WorkspaceModel.swift should not own thread memory refresh.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceMemoryCommandTranscriptPlanner"), "Memory command transcript copy should live in a focused planner.")
        XCTAssertTrue(errorText.contains("enum WorkspaceMemoryErrorMessageBuilder"), "Memory write and delete errors should share one user-facing formatter.")
        XCTAssertTrue(contextUpdateText.contains("struct WorkspaceMemoryContextUpdatePlanner"), "Memory thread context updates should live in a focused planner.")
        for delegatedCall in [
            "WorkspaceMemoryCommandTranscriptPlanner.memorySaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryUpdated",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotUpdated",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryUpdatedSummary",
            "WorkspaceRemoteProjectMemoryUpdater.update",
            "WorkspaceRemoteProjectMemoryDeleter.delete",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary",
            "WorkspaceMemoryErrorMessageBuilder.userFacingMessage",
            "WorkspaceMemoryContextUpdatePlanner.memoryChanged"
        ] {
            XCTAssertTrue(engineText.contains(delegatedCall), "WorkspaceMemoryEngine should delegate \(delegatedCall).")
        }
        XCTAssertFalse(modelText.contains("It will be included as background context in future turns."), "WorkspaceModel should not own memory save success copy.")
        XCTAssertFalse(modelText.contains("Memory not saved"), "WorkspaceModel should not own memory save failure title copy.")
        XCTAssertFalse(modelText.contains("It will no longer be included as background context."), "WorkspaceModel should not own memory delete success copy.")
        XCTAssertFalse(modelText.contains("Memory not deleted"), "WorkspaceModel should not own memory delete failure title copy.")
        XCTAssertFalse(modelText.contains("Forgot memory:"), "WorkspaceModel should not own memory delete summary copy.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.saveGlobal"), "WorkspaceModel should not write memory files directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.updateGlobal"), "WorkspaceModel should not update memory files directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.deleteGlobal"), "WorkspaceModel should not delete memory files directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.deleteProject"), "WorkspaceModel should not delete project memory files directly.")
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
        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryEditWorkspaceCommandPrefillsAndSlashUpdateRewritesGlobalMemory"), "Memory edit integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryEditWorkspaceCommandRewritesRemoteProjectMemoryThroughSSH"), "SSH Remote memory edit integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface"), "Agent memory tool integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface"), "Memory delete integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryDeleteWorkspaceCommandRemovesProjectMemoryAndRefreshesThreadSurface"), "Project memory delete integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryDeleteWorkspaceCommandRemovesRemoteProjectMemoryThroughSSH"), "SSH Remote memory delete integration should live in focused memory tests.")
        XCTAssertFalse(modelTests.contains("testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface"), "WorkspaceModelTests should not own memory integration flows.")
        XCTAssertFalse(modelTests.contains("testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own slash memory integration flows.")
        XCTAssertFalse(modelTests.contains("testMemoryEditWorkspaceCommandPrefillsAndSlashUpdateRewritesGlobalMemory"), "WorkspaceModelTests should not own memory edit integration flows.")
        XCTAssertFalse(modelTests.contains("testMemoryEditWorkspaceCommandRewritesRemoteProjectMemoryThroughSSH"), "WorkspaceModelTests should not own remote memory edit integration flows.")
        XCTAssertFalse(modelTests.contains("testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own agent memory integration flows.")
        XCTAssertFalse(modelTests.contains("testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own memory delete integration flows.")
        XCTAssertFalse(modelTests.contains("testMemoryDeleteWorkspaceCommandRemovesProjectMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own project memory delete integration flows.")
        XCTAssertFalse(modelTests.contains("testMemoryDeleteWorkspaceCommandRemovesRemoteProjectMemoryThroughSSH"), "WorkspaceModelTests should not own remote memory delete integration flows.")
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
        XCTAssertTrue(memoriesSpecText.contains("memory-edit"), "Focused memory flows should cover memory editing.")
        XCTAssertTrue(memoriesSpecText.contains("memory-delete"), "Focused memory flows should cover memory deletion.")
        XCTAssertTrue(memoriesSpecText.contains(memoryFlowName), "\(memoryFlowName) should live in memories.spec.ts.")
        XCTAssertFalse(coreSpecText.contains(memoryFlowName), "\(memoryFlowName) should not drift back into core.spec.ts.")
    }
}
