import XCTest
@testable import QuillCodeApp

final class SlashWorkspaceCommandParserTests: XCTestCase {
    func testSupportsWorkspaceAliases() {
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("browser"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("preview"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("worktree"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("worktrees"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("wt"))
        XCTAssertFalse(SlashWorkspaceCommandParser.supports("project"))
    }

    func testBrowserAliasesToggleBrowserPane() {
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "browser"), .workspaceCommand("toggle-browser"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "preview"), .workspaceCommand("toggle-browser"))
        XCTAssertEqual(SlashCommandParser.parse("/browser"), .workspaceCommand("toggle-browser"))
        XCTAssertEqual(SlashCommandParser.parse("/preview"), .workspaceCommand("toggle-browser"))
    }

    func testWorktreeAliasesListGitWorktrees() {
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "worktree"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "worktrees"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "wt"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/worktree"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/wt"), .workspaceCommand("git-worktree-list"))
    }
}
