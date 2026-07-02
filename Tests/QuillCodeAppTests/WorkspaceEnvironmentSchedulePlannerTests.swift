import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceEnvironmentSchedulePlannerTests: XCTestCase {
    func testPlansScheduleUsingActionTitlePrefix() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let plan = try XCTUnwrap(WorkspaceEnvironmentSchedulePlanner.plan(
            "Build Release in 30 minutes",
            actions: [
                action(
                    id: "local-env:.quillcode/actions/build-release.sh",
                    title: "Build Release",
                    relativePath: ".quillcode/actions/build-release.sh"
                )
            ],
            now: now
        ))

        XCTAssertEqual(plan.action.title, "Build Release")
        XCTAssertEqual(plan.schedule.scheduleDescription, "In 30 minutes")
        XCTAssertEqual(plan.schedule.nextRunAt, now.addingTimeInterval(30 * 60))
    }

    func testPlansScheduleUsingMarkerSplitForFuzzyActionName() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let plan = try XCTUnwrap(WorkspaceEnvironmentSchedulePlanner.plan(
            "verify workspace every 2 hours",
            actions: [
                action(
                    id: "local-env:.quillcode/actions/verify-workspace.sh",
                    title: "Verify Workspace",
                    relativePath: ".quillcode/actions/verify-workspace.sh"
                )
            ],
            now: now
        ))

        XCTAssertEqual(plan.action.title, "Verify Workspace")
        XCTAssertEqual(plan.schedule.scheduleDescription, "Every 2 hours")
        XCTAssertEqual(plan.schedule.recurrence, QuillAutomationRecurrence(interval: 2, unit: .hours))
    }

    func testReturnsNilForUnknownActionOrSchedule() {
        let actions = [
            action(
                id: "local-env:.quillcode/actions/build.sh",
                title: "Build",
                relativePath: ".quillcode/actions/build.sh"
            )
        ]

        XCTAssertNil(WorkspaceEnvironmentSchedulePlanner.plan("Deploy in 30 minutes", actions: actions))
        XCTAssertNil(WorkspaceEnvironmentSchedulePlanner.plan("Build eventually", actions: actions))
    }

    func testPrefixMatchRequiresTokenBoundary() {
        let actions = [
            action(
                id: "local-env:.quillcode/actions/build.sh",
                title: "Build",
                relativePath: ".quillcode/actions/build.sh"
            )
        ]

        XCTAssertNil(WorkspaceEnvironmentSchedulePlanner.plan("Buildkite in 30 minutes", actions: actions))
    }

    private func action(id: String, title: String, relativePath: String) -> LocalEnvironmentAction {
        LocalEnvironmentAction(
            id: id,
            title: title,
            relativePath: relativePath,
            command: "sh '\(relativePath)'"
        )
    }
}
