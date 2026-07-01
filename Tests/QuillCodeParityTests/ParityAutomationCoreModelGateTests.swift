import XCTest

final class ParityAutomationCoreModelGateTests: QuillCodeParityTestCase {
    func testAutomationModelsLiveOutsideGeneralDomainModels() throws {
        Self.assertLegacyGeneralModelsFileIsRetired()
        let modelsText = try Self.generalDomainModelsText()
        let automationText = try Self.coreSourceText(named: "AutomationModels.swift")

        Self.assertSource(automationText, containsAll: [
            "public enum QuillAutomationKind",
            "public enum QuillAutomationStatus",
            "public enum QuillAutomationScheduleKind",
            "public struct QuillAutomationRecurrence",
            "public struct QuillAutomationEventSource",
            "nextRun(after",
            "sortedForDisplay"
        ])
        Self.assertSource(modelsText, excludesAll: [
            "public enum QuillAutomationKind",
            "public enum QuillAutomationStatus",
            "public enum QuillAutomationScheduleKind",
            "public struct QuillAutomationRecurrence",
            "public struct QuillAutomationEventSource",
            "sortedForDisplay(_ automations"
        ])
    }
}
