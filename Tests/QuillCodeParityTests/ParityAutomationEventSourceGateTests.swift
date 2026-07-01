import XCTest

final class ParityAutomationEventSourceGateTests: QuillCodeParityTestCase {
    func testMonitorEventSourceWiringStaysImplemented() throws {
        let eventSourceText = try Self.appSourceText(named: "AutomationEventSource.swift")
        let integrationText = try Self.appTestSourceText(
            named: "WorkspaceAutomationRunIntegrationTests.swift"
        )

        Self.assertSource(eventSourceText, containsAll: [
            "public protocol AutomationEventSource",
            "public struct FileChangeEventSource",
            "enum AutomationEventSourceResolver"
        ])
        Self.assertSource(
            integrationText,
            contains: "testRunDueAutomationReportsRunsFileChangeMonitorEventSource"
        )
    }
}
