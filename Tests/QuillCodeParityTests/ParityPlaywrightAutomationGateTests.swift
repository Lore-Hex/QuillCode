import XCTest

final class ParityPlaywrightAutomationGateTests: QuillCodeParityTestCase {
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
            "runs a configured monitor automation",
            "schedules a recurring workspace check from slash text"
        ]

        Self.assertSource(automationSpecText, containsAll: [
            "harnessURL()",
            "automations-button",
            "/follow-up tomorrow at 9:30 PM",
            "/follow-up friday afternoon",
            "/workspace-check every 2 hours",
            "/workspace-check next monday at noon",
            "__quillCodeTestCreateMonitorAutomation"
        ])
        for flowName in automationFlowNames {
            Self.assertSource(automationSpecText, contains: flowName)
            Self.assertSource(coreSpecText, excludes: flowName)
        }
    }
}
