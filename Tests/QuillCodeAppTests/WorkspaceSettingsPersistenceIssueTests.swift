import XCTest
@testable import QuillCodeApp

@MainActor
final class WorkspaceSettingsPersistenceIssueTests: XCTestCase {
    func testIssueTracksExactKindsAndRecoversIndependently() throws {
        let model = QuillCodeWorkspaceModel()

        model.recordSettingsPersistenceFailure([
            .configuration,
            .trustedRouterCredential
        ])

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(model.settingsPersistenceIssueTracker.failedKindCount, 2)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.title, "Some settings changes are not saved")
        XCTAssertEqual(
            issue.diagnostics.first { $0.label == "Affected data" }?.value,
            "Configuration, TrustedRouter credential"
        )
        XCTAssertEqual(
            issue.diagnostics.first { $0.label == "Private content included" }?.value,
            "No"
        )

        model.recordSettingsPersistenceSuccess([.configuration])

        XCTAssertEqual(model.settingsPersistenceIssueTracker.failedKindCount, 1)
        XCTAssertEqual(model.surface().runtimeIssue?.title, "A settings change is not saved")
        XCTAssertEqual(
            model.surface().runtimeIssue?.diagnostics.first { $0.label == "Affected data" }?.value,
            "TrustedRouter credential"
        )

        model.recordSettingsPersistenceSuccess([.trustedRouterCredential])

        XCTAssertEqual(model.settingsPersistenceIssueTracker.failedKindCount, 0)
        XCTAssertNotEqual(model.surface().runtimeIssue?.title, issue.title)
    }

    func testRegistryFailureKeepsPriorityOverSettingsFailure() {
        let model = QuillCodeWorkspaceModel()

        model.registryPersistenceIssueTracker.recordFailure(for: .projects)
        model.recordSettingsPersistenceFailure([.configuration])

        XCTAssertEqual(model.surface().runtimeIssue?.title, "A workspace change is not saved")
    }
}
