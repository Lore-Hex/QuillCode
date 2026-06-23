import XCTest
@testable import QuillCodeApp

final class QuillCodeRuntimeIssueRecoveryPlannerTests: XCTestCase {
    func testSettingsLabelsRouteToEnabledSettingsCommand() {
        let settings = command(id: "settings")
        let planner = RuntimeIssueRecoveryPlanner(commands: [settings])

        XCTAssertEqual(planner.action(for: issue(actionLabel: "Open Settings")), .command(settings))
        XCTAssertEqual(planner.action(for: issue(actionLabel: "Add key")), .command(settings))
        XCTAssertEqual(planner.action(for: issue(actionLabel: "Fix key")), .command(settings))
    }

    func testSettingsLabelsRequireEnabledSettingsCommand() {
        let planner = RuntimeIssueRecoveryPlanner(commands: [
            command(id: "settings", isEnabled: false)
        ])

        XCTAssertNil(planner.action(for: issue(actionLabel: "Open Settings")))
        XCTAssertNil(planner.action(for: issue(actionLabel: "Add key")))
        XCTAssertNil(planner.action(for: issue(actionLabel: "Fix key")))
    }

    func testRetryRoutesToEnabledRetryCommand() {
        let retry = command(id: "retry-last-turn")
        let planner = RuntimeIssueRecoveryPlanner(commands: [retry])

        XCTAssertEqual(planner.action(for: issue(actionLabel: "Retry")), .command(retry))
    }

    func testRetryRequiresEnabledRetryCommand() {
        let planner = RuntimeIssueRecoveryPlanner(commands: [
            command(id: "retry-last-turn", isEnabled: false)
        ])

        XCTAssertNil(planner.action(for: issue(actionLabel: "Retry")))
    }

    func testSwitchModelPresentsModelPickerWithoutCommandDependency() {
        let planner = RuntimeIssueRecoveryPlanner(commands: [])

        XCTAssertEqual(planner.action(for: issue(actionLabel: "Switch model")), .presentModelPicker)
    }

    func testMissingOrUnknownLabelsHaveNoRecoveryAction() {
        let planner = RuntimeIssueRecoveryPlanner(commands: [
            command(id: "settings"),
            command(id: "retry-last-turn")
        ])

        XCTAssertNil(planner.action(for: nil))
        XCTAssertNil(planner.action(for: issue(actionLabel: nil)))
        XCTAssertNil(planner.action(for: issue(actionLabel: "Open Console")))
    }

    private func command(id: String, isEnabled: Bool = true) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: id,
            category: WorkspaceCommandPalette.controlCategory,
            isEnabled: isEnabled
        )
    }

    private func issue(actionLabel: String?) -> RuntimeIssueSurface {
        RuntimeIssueSurface(
            severity: .warning,
            title: "Runtime issue",
            message: "Needs recovery.",
            actionLabel: actionLabel
        )
    }
}
