import XCTest
@testable import QuillCodeApp

final class LinuxNotificationAdapterTests: XCTestCase {
    func testAgentNotificationUsesNotifySendArgvWithoutShellQuoting() {
        let notification = AgentRunNotification(
            kind: .needsApproval,
            title: "Approve\ncommand",
            body: "Run `ls`; keep $HOME literal\t",
            threadID: UUID(),
            approvalRequestID: "request-1"
        )

        let command = LinuxNotificationAdapter.command(for: notification)

        XCTAssertEqual(command.executable, "notify-send")
        XCTAssertEqual(command.arguments[0], "--app-name=QuillCode")
        XCTAssertEqual(command.arguments.suffix(2).first, "Approve command")
        XCTAssertEqual(command.arguments.last, "Run `ls`; keep $HOME literal")
        XCTAssertFalse(command.arguments.contains("sh"))
        XCTAssertFalse(command.arguments.contains("-c"))
    }

    func testUrgentRunNotificationsUseCriticalUrgency() {
        let approval = LinuxNotificationAdapter.command(for: note(kind: .needsApproval))
        XCTAssertTrue(approval.arguments.contains("--urgency=critical"))
        XCTAssertTrue(approval.arguments.contains("--expire-time=0"))

        let failure = LinuxNotificationAdapter.command(for: note(kind: .checksFailing))
        XCTAssertTrue(failure.arguments.contains("--urgency=critical"))
        XCTAssertTrue(failure.arguments.contains("--expire-time=12000"))
    }

    func testLowRiskRunNotificationsUseBoundedLifetime() {
        let verified = LinuxNotificationAdapter.command(for: note(kind: .verifiedGreen))
        XCTAssertTrue(verified.arguments.contains("--urgency=low"))
        XCTAssertTrue(verified.arguments.contains("--expire-time=5000"))

        let finished = LinuxNotificationAdapter.command(for: note(kind: .finished))
        XCTAssertTrue(finished.arguments.contains("--urgency=normal"))
        XCTAssertTrue(finished.arguments.contains("--expire-time=6000"))
    }

    func testAutomationReportsUseNormalUrgency() {
        let report = AutomationRunReport(
            automationID: UUID(),
            followUpThreadID: UUID(),
            title: "Scheduled check",
            body: "Workspace check finished."
        )

        let command = LinuxNotificationAdapter.command(for: report)

        XCTAssertEqual(command.executable, "notify-send")
        XCTAssertTrue(command.arguments.contains("--urgency=normal"))
        XCTAssertTrue(command.arguments.contains("--expire-time=8000"))
        XCTAssertEqual(command.arguments.suffix(2).first, "Scheduled check")
        XCTAssertEqual(command.arguments.last, "Workspace check finished.")
    }

    func testNotificationTextIsBoundedAndReadable() throws {
        let longTitle = String(repeating: "Title ", count: 40)
        let longBody = String(repeating: "Body ", count: 80)
        let command = LinuxNotificationAdapter.command(for: AgentRunNotification(
            kind: .failed,
            title: longTitle,
            body: longBody,
            threadID: UUID()
        ))

        let title = command.arguments[command.arguments.count - 2]
        let body = try XCTUnwrap(command.arguments.last)
        XCTAssertLessThanOrEqual(title.count, 96)
        XCTAssertLessThanOrEqual(body.count, 240)
        XCTAssertTrue(title.hasSuffix("..."))
        XCTAssertTrue(body.hasSuffix("..."))
    }

    func testEmptyTextFallsBackToReadableDefaults() {
        let command = LinuxNotificationAdapter.command(for: AgentRunNotification(
            kind: .finished,
            title: " \n\t ",
            body: "",
            threadID: UUID()
        ))

        XCTAssertEqual(command.arguments.suffix(2).first, "QuillCode")
        XCTAssertEqual(command.arguments.last, "Open QuillCode for details.")
    }

    private func note(kind: AgentRunNotification.Kind) -> AgentRunNotification {
        AgentRunNotification(
            kind: kind,
            title: "QuillCode",
            body: "Run finished",
            threadID: UUID()
        )
    }
}
