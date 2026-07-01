import XCTest

final class ParityWorkspaceAutomationModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesAutomationStateMutations() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let automationModelText = try Self.appSourceText(named: "WorkspaceModelAutomations.swift")
        let automationRunText = try Self.appSourceText(named: "WorkspaceModelAutomationRuns.swift")
        let stateText = try Self.appSourceText(named: "WorkspaceAutomationEngine.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAutomationFactory.swift")
        let reducerText = try Self.appSourceText(named: "WorkspaceAutomationStateReducer.swift")
        let runnerText = try Self.appSourceText(named: "WorkspaceAutomationRunner.swift")

        assertAutomationDataOwnsRecords(stateText)
        assertAutomationFactoryOwnsConstruction(factoryText)
        assertAutomationReducerOwnsMutations(reducerText)
        assertAutomationRunnerOwnsRunPlanning(runnerText)
        assertWorkspaceExtensionsDelegateAutomationAPIs(
            automationModelText: automationModelText,
            automationRunText: automationRunText
        )
        assertWorkspaceRootDoesNotOwnAutomationMutations(modelText)
    }

    private func assertAutomationDataOwnsRecords(_ stateText: String) {
        Self.assertSource(stateText, containsAll: [
            "public struct AutomationsState",
            "public struct AutomationRunReport",
            "struct WorkspaceAutomationRunDraft",
            "struct WorkspaceAutomationTrigger"
        ])
        Self.assertSource(stateText, excludesAll: [
            "enum WorkspaceAutomationFactory",
            "enum WorkspaceAutomationStateReducer",
            "enum WorkspaceAutomationRunner"
        ])
    }

    private func assertAutomationFactoryOwnsConstruction(_ factoryText: String) {
        Self.assertSource(factoryText, containsAll: [
            "enum WorkspaceAutomationFactory",
            "static func threadFollowUp",
            "static func workspaceSchedule",
            "static func relativeSchedule",
            "static func tomorrowMorning"
        ])
    }

    private func assertAutomationReducerOwnsMutations(_ reducerText: String) {
        Self.assertSource(reducerText, containsAll: [
            "enum WorkspaceAutomationStateReducer",
            "struct WorkspaceAutomationStateMutation",
            "static func setItems",
            "static func createThreadFollowUp",
            "static func createWorkspaceSchedule",
            "static func updateStatus",
            "static func delete(",
            "static func replace("
        ])
    }

    private func assertAutomationRunnerOwnsRunPlanning(_ runnerText: String) {
        Self.assertSource(runnerText, containsAll: [
            "enum WorkspaceAutomationRunner",
            "static func dueAutomationTriggers",
            "static func threadFollowUpDraft",
            "static func workspaceScheduleDraft",
            "static func monitorDraft"
        ])
    }

    private func assertWorkspaceExtensionsDelegateAutomationAPIs(
        automationModelText: String,
        automationRunText: String
    ) {
        Self.assertSource(automationModelText, containsAll: [
            "extension QuillCodeWorkspaceModel",
            "WorkspaceAutomationStateReducer.setItems",
            "WorkspaceAutomationStateReducer.createThreadFollowUp",
            "WorkspaceAutomationStateReducer.createWorkspaceSchedule"
        ])
        Self.assertSource(automationRunText, containsAll: [
            "extension QuillCodeWorkspaceModel",
            "WorkspaceAutomationStateReducer.updateStatus",
            "WorkspaceAutomationStateReducer.delete",
            "WorkspaceAutomationStateReducer.replace",
            "automationEventSources()",
            "eventDescription:"
        ])
        Self.assertSource(automationModelText, excludesAll: [
            "WorkspaceAutomationStateReducer.updateStatus",
            "WorkspaceAutomationStateReducer.delete",
            "WorkspaceAutomationStateReducer.replace"
        ])
    }

    private func assertWorkspaceRootDoesNotOwnAutomationMutations(_ modelText: String) {
        Self.assertSource(modelText, excludesAll: [
            "public func createThreadFollowUpAutomation",
            "public func createWorkspaceScheduleAutomation",
            "public func runDueAutomations",
            "AutomationEventSourceResolver",
            "setAutomations(automations.items + [automation])",
            "QuillAutomation.sortedForDisplay(items)",
            "automations.items[index].status",
            "automations.items.removeAll"
        ])
    }
}
