import XCTest

final class ParityWorkspaceAutomationRunGateTests: QuillCodeParityTestCase {
    func testWorkspaceAutomationRunsDelegateRunnerAndEventSources() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let runModelText = try Self.appSourceText(named: "WorkspaceModelAutomationRuns.swift")
        let runnerText = try Self.appSourceText(named: "WorkspaceAutomationRunner.swift")

        Self.assertSource(runnerText, containsAll: [
            "enum WorkspaceAutomationRunner",
            "static func dueAutomationTriggers",
            "static func threadFollowUpDraft",
            "static func workspaceScheduleDraft",
            "static func monitorDraft"
        ])
        Self.assertSource(runModelText, containsAll: [
            "automationEventSources()",
            "eventDescription:"
        ])
        Self.assertSource(modelText, excludesAll: [
            "public func runDueAutomations",
            "AutomationEventSourceResolver"
        ])
    }
}
