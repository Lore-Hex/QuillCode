import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class AutomationWorkflowSurfaceTests: XCTestCase {
    func testActiveWorkflowBuildsRunPauseAndDeleteActions() {
        let automation = QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            title: "Morning check",
            detail: "Check the workspace.",
            kind: .workspaceSchedule,
            status: .active,
            scheduleKind: .cron,
            scheduleDescription: "Every morning",
            nextRunAt: Date(timeIntervalSince1970: 100)
        )

        let surface = AutomationWorkflowSurface(automation: automation)

        XCTAssertEqual(surface.id, "00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(surface.title, "Morning check")
        XCTAssertEqual(surface.detail, "Check the workspace.")
        XCTAssertEqual(surface.statusLabel, "Due")
        XCTAssertEqual(surface.scheduleLabel, "Every morning")
        XCTAssertEqual(surface.runActionTitle, "Run now")
        XCTAssertEqual(surface.runCommandID, "automation-run:00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(surface.primaryActionTitle, "Pause")
        XCTAssertEqual(surface.primaryCommandID, "automation-pause:00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(surface.deleteCommandID, "automation-delete:00000000-0000-0000-0000-000000000101")
    }

    func testPausedWorkflowBuildsResumeActionWithoutRunNow() {
        let automation = QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            title: "Follow up",
            detail: "Wake the thread.",
            kind: .threadFollowUp,
            status: .paused,
            scheduleKind: .heartbeat,
            scheduleDescription: "Tomorrow at 9:00 AM"
        )

        let surface = AutomationWorkflowSurface(automation: automation)

        XCTAssertEqual(surface.statusLabel, "Paused")
        XCTAssertEqual(surface.scheduleLabel, "Tomorrow at 9:00 AM")
        XCTAssertNil(surface.runActionTitle)
        XCTAssertNil(surface.runCommandID)
        XCTAssertEqual(surface.primaryActionTitle, "Resume")
        XCTAssertEqual(surface.primaryCommandID, "automation-resume:00000000-0000-0000-0000-000000000102")
    }

    func testActiveMonitorExposesRunNow() {
        let automation = QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            title: "Watch CI",
            detail: "Watch the current PR.",
            kind: .monitor,
            status: .active,
            scheduleKind: .event,
            scheduleDescription: ""
        )

        let surface = AutomationWorkflowSurface(automation: automation)

        XCTAssertEqual(surface.statusLabel, "Active")
        XCTAssertEqual(surface.scheduleLabel, "Event")
        XCTAssertEqual(surface.runActionTitle, "Run now")
        XCTAssertEqual(surface.runCommandID, "automation-run:00000000-0000-0000-0000-000000000103")
    }
}
