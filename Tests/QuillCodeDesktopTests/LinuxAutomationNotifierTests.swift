import XCTest
import QuillCodeApp
@testable import quill_code_desktop

final class LinuxAutomationNotifierTests: XCTestCase {
    func testLinuxNotifierForwardsAgentAndAutomationNotifications() async {
        let recorder = LinuxNotificationDeliveryRecorder()
        let notifier = LinuxAutomationNotifier(
            deliverAgentNotification: { notification in
                await recorder.record(notification)
            },
            deliverAutomationReport: { report in
                await recorder.record(report)
            }
        )
        let threadID = UUID()
        let automationID = UUID()
        let followUpThreadID = UUID()

        notifier.deliver(AgentRunNotification(
            kind: .needsApproval,
            title: "Approve command",
            body: "Review a shell command.",
            threadID: threadID,
            approvalRequestID: "request-1"
        ))
        notifier.deliver(AutomationRunReport(
            automationID: automationID,
            followUpThreadID: followUpThreadID,
            title: "Workspace check",
            body: "The scheduled check is ready."
        ))

        let snapshot = await recorder.waitForCounts(agent: 1, automation: 1)
        XCTAssertEqual(snapshot.agentNotifications.map(\.threadID), [threadID])
        XCTAssertEqual(snapshot.automationReports.map(\.automationID), [automationID])
        XCTAssertEqual(snapshot.automationReports.map(\.followUpThreadID), [followUpThreadID])
    }
}

private actor LinuxNotificationDeliveryRecorder {
    private var agentNotifications: [AgentRunNotification] = []
    private var automationReports: [AutomationRunReport] = []

    func record(_ notification: AgentRunNotification) -> SystemNotificationDeliveryResult {
        agentNotifications.append(notification)
        return deliveredResult()
    }

    func record(_ report: AutomationRunReport) -> SystemNotificationDeliveryResult {
        automationReports.append(report)
        return deliveredResult()
    }

    func waitForCounts(agent: Int, automation: Int) async -> Snapshot {
        for _ in 0..<50 {
            if agentNotifications.count >= agent, automationReports.count >= automation {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return Snapshot(
            agentNotifications: agentNotifications,
            automationReports: automationReports
        )
    }

    private func deliveredResult() -> SystemNotificationDeliveryResult {
        SystemNotificationDeliveryResult(
            command: SystemNotificationCommand(executable: "notify-send", arguments: []),
            status: .delivered
        )
    }

    struct Snapshot {
        var agentNotifications: [AgentRunNotification]
        var automationReports: [AutomationRunReport]
    }
}
