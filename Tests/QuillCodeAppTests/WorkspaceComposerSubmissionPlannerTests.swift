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

    func testPresentationSlashCommandsKeepWorkspaceCommandIDs() {
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "/search"),
            .slash(command: .workspaceCommand("search"), originalPrompt: "/search")
        )
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "/find"),
            .slash(command: .workspaceCommand("find-in-chat"), originalPrompt: "/find")
        )
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "/settings"),
            .slash(command: .workspaceCommand("settings"), originalPrompt: "/settings")
        )
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "/shortcuts"),
            .slash(command: .workspaceCommand("keyboard-shortcuts"), originalPrompt: "/shortcuts")
        )
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "/commands"),
            .slash(command: .workspaceCommand("command-palette"), originalPrompt: "/commands")
        )
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "/plugins"),
            .slash(command: .workspaceCommand("toggle-extensions"), originalPrompt: "/plugins")
        )
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "/automations"),
            .slash(command: .workspaceCommand("toggle-automations"), originalPrompt: "/automations")
        )
        XCTAssertEqual(
            WorkspaceComposerSubmissionPlanner.plan(draft: "/activity"),
            .slash(command: .workspaceCommand("toggle-activity"), originalPrompt: "/activity")
        )
    }
}
