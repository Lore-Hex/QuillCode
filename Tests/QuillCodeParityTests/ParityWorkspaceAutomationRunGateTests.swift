import XCTest

final class ParityWorkspaceAutomationRunGateTests: QuillCodeParityTestCase {
    func testWorkspaceAutomationRunsDelegateRunnerAndEventSources() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let runModelText = try Self.appSourceText(named: "WorkspaceModelAutomationRuns.swift")
        let asyncRunModelText = try Self.appSourceText(named: "WorkspaceModelAsyncAutomationRuns.swift")
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
            "automations.items.first(where:",
            "eventDescription:"
        ])
        Self.assertSource(asyncRunModelText, containsAll: [
            "public func runDueAutomationReportsAsync",
            "await runCancellableToolCall(",
            "onProgressUpdated: onProgressUpdated"
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
