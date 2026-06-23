import XCTest
@testable import QuillCodeApp

final class WorkspaceComposerSubmissionPlannerTests: XCTestCase {
    func testBlankDraftIsIgnored() {
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: " \n\t "),
            .ignore
        )
    }

    func testAgentPromptIsTrimmed() {
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "  run whoami\n"),
            .agent(prompt: "run whoami")
        )
    }

    func testSlashCommandKeepsTrimmedOriginalPrompt() {
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "  /model Nike 1.0  "),
            .slash(command: .model("Nike 1.0"), originalPrompt: "/model Nike 1.0")
        )
    }
}
