import XCTest
import QuillCodeApp
import QuillCodeCore
@testable import quill_code_desktop

@MainActor
final class DesktopNotificationPolicyTests: XCTestCase {
    func testAgentRunPolicyHonorsEnabledAndInactiveRules() {
        XCTAssertTrue(DesktopNotificationPolicy.shouldDeliverAgentRun(
            preferences: QuillCodeNotificationPreferences(),
            appIsActive: false
        ))
        XCTAssertFalse(DesktopNotificationPolicy.shouldDeliverAgentRun(
            preferences: QuillCodeNotificationPreferences(),
            appIsActive: true
        ))
        XCTAssertTrue(DesktopNotificationPolicy.shouldDeliverAgentRun(
            preferences: QuillCodeNotificationPreferences(agentRunNotificationsOnlyWhenInactive: false),
            appIsActive: true
        ))
        XCTAssertFalse(DesktopNotificationPolicy.shouldDeliverAgentRun(
            preferences: QuillCodeNotificationPreferences(agentRunNotificationsEnabled: false),
            appIsActive: false
        ))
    }

    func testAutomationCoordinatorRunsDueWorkWhenNotificationsAreDisabled() {
        let source = ChatThread(title: "Due follow-up", messages: [
            .init(role: .user, content: "check later"),
            .init(role: .assistant, content: "I will.")
        ])
        let automation = QuillAutomation(
            title: "Due follow-up",
            detail: "Resume later.",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            scheduleDescription: "Now",
            threadID: source.id,
            nextRunAt: Date(timeIntervalSince1970: 1)
        )
        let config = AppConfig(
            notificationPreferences: QuillCodeNotificationPreferences(automationNotificationsEnabled: false)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            threads: [source],
            selectedThreadID: source.id
        ))
        let notifier = RecordingDesktopAutomationNotifier()
        var didRefresh = false
        model.setAutomations([automation])

        QuillCodeDesktopAutomationCoordinator().runDueAutomations(
            model: model,
            notifier: notifier,
            refresh: { didRefresh = true }
        )

        XCTAssertTrue(didRefresh)
        XCTAssertTrue(notifier.automationReports.isEmpty)
        XCTAssertNotNil(model.root.threads.first { $0.title == "Follow-up: Due follow-up" })
    }

    func testAutomationCoordinatorDeliversReportsWhenNotificationsAreEnabled() {
        let source = ChatThread(title: "Due follow-up", messages: [
            .init(role: .user, content: "check later"),
            .init(role: .assistant, content: "I will.")
        ])
        let automation = QuillAutomation(
            title: "Due follow-up",
            detail: "Resume later.",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            scheduleDescription: "Now",
            threadID: source.id,
            nextRunAt: Date(timeIntervalSince1970: 1)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))
        let notifier = RecordingDesktopAutomationNotifier()
        model.setAutomations([automation])

        QuillCodeDesktopAutomationCoordinator().runDueAutomations(
            model: model,
            notifier: notifier,
            refresh: {}
        )

        XCTAssertEqual(notifier.automationReports.count, 1)
        XCTAssertEqual(notifier.automationReports.first?.automationID, automation.id)
    }

    func testAutomationCoordinatorDeliversScheduledCoworkerReport() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let automation = QuillAutomation(
            title: "Scheduled task: Check competitors",
            detail: "check competitor pricing pages and notify me with a diff",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: "Every Monday at 8:00 AM",
            projectID: project.id,
            nextRunAt: Date(timeIntervalSince1970: 1)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id
        ))
        let notifier = RecordingDesktopAutomationNotifier()
        model.setAutomations([automation])

        QuillCodeDesktopAutomationCoordinator().runDueAutomations(
            model: model,
            notifier: notifier,
            refresh: {}
        )

        let report = notifier.automationReports.first
        XCTAssertEqual(notifier.automationReports.count, 1)
        XCTAssertEqual(report?.automationID, automation.id)
        XCTAssertEqual(report?.title, "QuillCode scheduled task ready")
        XCTAssertEqual(
            report?.body,
            "Scheduled check: QuillCode was created for QuillCode: check competitor pricing pages and notify me with a diff."
        )
    }
}

private final class RecordingDesktopAutomationNotifier: QuillCodeAutomationNotifying, @unchecked Sendable {
    private(set) var automationReports: [AutomationRunReport] = []

    func deliver(_ report: AutomationRunReport) {
        automationReports.append(report)
    }
}
