import XCTest

final class ParityWorkspaceAutomationStateGateTests: QuillCodeParityTestCase {
    func testWorkspaceAutomationDataFactoryAndReducerStayFocused() throws {
        let automationText = try Self.appSourceText(named: "WorkspaceAutomationEngine.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAutomationFactory.swift")
        let reducerText = try Self.appSourceText(named: "WorkspaceAutomationStateReducer.swift")

        Self.assertSource(automationText, containsAll: [
            "public struct AutomationsState",
            "public struct AutomationRunReport",
            "struct WorkspaceAutomationRunDraft",
            "struct WorkspaceAutomationTrigger"
        ])
        Self.assertSource(automationText, excludesAll: [
            "enum WorkspaceAutomationFactory",
            "enum WorkspaceAutomationStateReducer",
            "enum WorkspaceAutomationRunner"
        ])
        Self.assertSource(factoryText, containsAll: [
            "enum WorkspaceAutomationFactory",
            "static func threadFollowUp",
            "static func workspaceSchedule",
            "static func relativeSchedule",
            "static func tomorrowMorning"
        ])
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

    func testWorkspaceAutomationModelDelegatesStateMutations() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let automationModelText = try Self.appSourceText(named: "WorkspaceModelAutomations.swift")
        let automationRunModelText = try Self.appSourceText(named: "WorkspaceModelAutomationRuns.swift")

        Self.assertSource(automationModelText, containsAll: [
            "extension QuillCodeWorkspaceModel",
            "WorkspaceAutomationStateReducer.setItems",
            "WorkspaceAutomationStateReducer.createThreadFollowUp",
            "WorkspaceAutomationStateReducer.createWorkspaceSchedule"
        ])
        Self.assertSource(automationRunModelText, containsAll: [
            "extension QuillCodeWorkspaceModel",
            "WorkspaceAutomationStateReducer.updateStatus",
            "WorkspaceAutomationStateReducer.delete",
            "WorkspaceAutomationStateReducer.replace"
        ])
        Self.assertSource(automationModelText, excludesAll: [
            "WorkspaceAutomationStateReducer.updateStatus",
            "WorkspaceAutomationStateReducer.delete",
            "WorkspaceAutomationStateReducer.replace"
        ])
        Self.assertSource(modelText, excludesAll: [
            "public func createThreadFollowUpAutomation",
            "public func createWorkspaceScheduleAutomation",
            "setAutomations(automations.items + [automation])",
            "QuillAutomation.sortedForDisplay(items)",
            "automations.items[index].status",
            "automations.items.removeAll"
        ])
    }
}
