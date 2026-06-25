import XCTest

final class ParityAutomationGateTests: QuillCodeParityTestCase {
    func testAutomationModelsLiveOutsideGeneralDomainModels() throws {
        let modelsText = try Self.coreSourceText(named: "Models.swift")
        let automationText = try Self.coreSourceText(named: "AutomationModels.swift")

        XCTAssertTrue(automationText.contains("public enum QuillAutomationKind"), "Automation kind should live in a focused core file.")
        XCTAssertTrue(automationText.contains("public enum QuillAutomationStatus"), "Automation status should live beside automation records.")
        XCTAssertTrue(automationText.contains("public enum QuillAutomationScheduleKind"), "Automation schedule kind should live beside automation records.")
        XCTAssertTrue(automationText.contains("public struct QuillAutomationRecurrence"), "Automation recurrence should live beside automation records.")
        XCTAssertTrue(automationText.contains("nextRun(after"), "Automation recurrence scheduling should stay with recurrence records.")
        XCTAssertTrue(automationText.contains("sortedForDisplay"), "Automation display sorting should stay with automation records.")
        XCTAssertFalse(modelsText.contains("public enum QuillAutomationKind"), "General domain models should not own automation records.")
        XCTAssertFalse(modelsText.contains("public enum QuillAutomationStatus"), "General domain models should not own automation status.")
        XCTAssertFalse(modelsText.contains("public enum QuillAutomationScheduleKind"), "General domain models should not own automation schedule records.")
        XCTAssertFalse(modelsText.contains("public struct QuillAutomationRecurrence"), "General domain models should not own automation recurrence.")
        XCTAssertFalse(modelsText.contains("sortedForDisplay(_ automations"), "General domain models should not own automation sorting.")
    }

    func testWorkspaceModelDelegatesAutomationStateMutations() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let modelAutomationText = try Self.appSourceText(named: "WorkspaceModelAutomations.swift")
        let automationText = try Self.appSourceText(named: "WorkspaceAutomationEngine.swift")

        XCTAssertTrue(modelAutomationText.contains("extension QuillCodeWorkspaceModel"), "Automation model API should live in a focused workspace model extension.")
        XCTAssertTrue(automationText.contains("enum WorkspaceAutomationStateReducer"), "Automation state mutation should live in a focused reducer.")
        XCTAssertTrue(automationText.contains("struct WorkspaceAutomationStateMutation"), "Automation state mutations should return typed mutation results.")
        XCTAssertTrue(automationText.contains("static func setItems"), "Automation sorting and visibility preservation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func createThreadFollowUp"), "Thread follow-up creation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func createWorkspaceSchedule"), "Workspace schedule creation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func updateStatus"), "Automation status mutation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func delete("), "Automation deletion should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func replace("), "Automation replacement should be reducer-owned.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.setItems"), "WorkspaceModel automation extension should delegate automation item setting.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.createThreadFollowUp"), "WorkspaceModel automation extension should delegate thread follow-up creation.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.createWorkspaceSchedule"), "WorkspaceModel automation extension should delegate workspace schedule creation.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.updateStatus"), "WorkspaceModel automation extension should delegate status changes.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.delete"), "WorkspaceModel automation extension should delegate deletion.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.replace"), "WorkspaceModel automation extension should delegate replacement.")
        XCTAssertFalse(modelText.contains("public func createThreadFollowUpAutomation"), "WorkspaceModel.swift should not own automation scheduling APIs.")
        XCTAssertFalse(modelText.contains("public func createWorkspaceScheduleAutomation"), "WorkspaceModel.swift should not own workspace-check scheduling APIs.")
        XCTAssertFalse(modelText.contains("public func runDueAutomations"), "WorkspaceModel.swift should not own automation-run orchestration.")
        XCTAssertFalse(modelText.contains("setAutomations(automations.items + [automation])"), "WorkspaceModel should not append automation records inline.")
        XCTAssertFalse(modelText.contains("QuillAutomation.sortedForDisplay(items)"), "WorkspaceModel should not own automation display sorting.")
        XCTAssertFalse(modelText.contains("automations.items[index].status"), "WorkspaceModel should not mutate automation status inline.")
        XCTAssertFalse(modelText.contains("automations.items.removeAll"), "WorkspaceModel should not delete automation records inline.")
    }

    func testWorkspaceSurfaceDelegatesAutomationsSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAutomationsSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceAutomationsSurfaceBuilder"), "Automation pane assembly should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func surface() -> WorkspaceAutomationsSurface"), "Automation pane assembly should be directly testable.")
        XCTAssertTrue(builderText.contains("hasSelectedThread"), "Thread follow-up command availability should be builder-owned.")
        XCTAssertTrue(builderText.contains("hasSelectedProject"), "Workspace schedule command availability should be builder-owned.")
        XCTAssertTrue(surfaceText.contains("WorkspaceAutomationsSurfaceBuilder("), "WorkspaceSurface should delegate automation pane assembly.")
        XCTAssertFalse(surfaceText.contains("automationCreateThreadFollowUp"), "WorkspaceSurface should not build automation follow-up commands inline.")
        XCTAssertFalse(surfaceText.contains("automationCreateWorkspaceSchedule"), "WorkspaceSurface should not build automation schedule commands inline.")
        XCTAssertFalse(surfaceText.contains("automationScheduleThreadFollowUpCommands"), "WorkspaceSurface should not build thread schedule command variants inline.")
        XCTAssertFalse(surfaceText.contains("automationScheduleWorkspaceScheduleCommands"), "WorkspaceSurface should not build workspace schedule command variants inline.")
    }

    func testPlaywrightAutomationFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let automationSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("automations.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let automationFlowNames = [
            "separates Automations from Activity in the sidebar",
            "creates and manages a thread follow-up automation",
            "creates and runs a workspace schedule automation",
            "schedules a recurring workspace check from slash text"
        ]

        XCTAssertTrue(automationSpecText.contains("harnessURL()"), "Focused automation flows should reuse the shared harness URL helper.")
        XCTAssertTrue(automationSpecText.contains("automations-button"), "Focused automation flows should cover the sidebar Automations entry point.")
        XCTAssertTrue(automationSpecText.contains("/follow-up tomorrow at 9:30 PM"), "Focused automation flows should cover slash-created thread follow-ups.")
        XCTAssertTrue(automationSpecText.contains("/workspace-check every 2 hours"), "Focused automation flows should cover recurring workspace schedule slash input.")
        for flowName in automationFlowNames {
            XCTAssertTrue(automationSpecText.contains(flowName), "\(flowName) should live in automations.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }
}
