import XCTest

final class ParityWorkspaceAutomationRunGateTests: QuillCodeParityTestCase {
    func testWorkspaceAutomationRunsDelegateRunnerAndEventSources() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let runModelText = try Self.appSourceText(named: "WorkspaceModelAutomationRuns.swift")
        let runnerText = try Self.appSourceText(named: "WorkspaceAutomationRunner.swift")
        let pollerText = try Self.appSourceText(named: "WorkspaceAutomationEventPoller.swift")

        Self.assertSource(runnerText, containsAll: [
            "enum WorkspaceAutomationRunner",
            "static func dueAutomationTriggers",
            "static func dueAutomationTriggersAsync",
            "static func threadFollowUpDraft",
            "static func workspaceScheduleDraft",
            "static func monitorDraft"
        ])
        Self.assertSource(runModelText, containsAll: [
            "automationEventSources()",
            "public func runDueAutomationReportsAsync",
            "automations.items.first(where:",
            "eventDescription:"
        ])
        Self.assertSource(pollerText, containsAll: [
            "enum WorkspaceAutomationEventPoller",
            "static let maximumConcurrentPolls = 4",
            "Task.detached(priority: .utility)",
            "AsyncStream<PendingEvent?>"
        ])
        Self.assertSource(modelText, excludesAll: [
            "public func runDueAutomations",
            "AutomationEventSourceResolver"
        ])
    }
}
