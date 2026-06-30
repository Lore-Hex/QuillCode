import XCTest
@testable import QuillCodeApp

final class SlashWorkspaceCommandParserTests: XCTestCase {
    func testSupportsWorkspaceAliases() {
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("browser"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("preview"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("diff"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("git-status"))
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

    func testGitDiffAndStatusAliasesRunGitCommands() {
        XCTAssertEqual(SlashCommandParser.parse("/diff"), .workspaceCommand("git-diff"))
        XCTAssertEqual(SlashCommandParser.parse("/changes"), .workspaceCommand("git-diff"))
        XCTAssertEqual(SlashCommandParser.parse("/git-status"), .workspaceCommand("git-status"))
        XCTAssertEqual(SlashCommandParser.parse("/gitstatus"), .workspaceCommand("git-status"))
    }

    func testInitAliasesScaffoldProjectInstructions() {
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("init"))
        XCTAssertTrue(SlashWorkspaceCommandParser.supports("init-project"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "init"), .workspaceCommand("project-init"))
        XCTAssertEqual(SlashCommandParser.parse("/init"), .workspaceCommand("project-init"))
        XCTAssertEqual(SlashCommandParser.parse("/init-project"), .workspaceCommand("project-init"))
    }

    func testWorktreeAliasesListGitWorktrees() {
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "worktree"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "worktrees"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashWorkspaceCommandParser.parse(name: "wt"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/worktree"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/wt"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/worktree list"), .workspaceCommand("git-worktree-list"))
        XCTAssertEqual(SlashCommandParser.parse("/wt ls"), .workspaceCommand("git-worktree-list"))
    }

    func testWorktreeCreateParsesPathBranchAndBase() {
        XCTAssertEqual(
            SlashCommandParser.parse(#"/worktree create "../quill code feature" --branch feature/quill --base main"#),
            .worktreeCreate(.init(path: "../quill code feature", branch: "feature/quill", base: "main"))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/wt add ../quick --from origin/main -b quick/work"),
            .worktreeCreate(.init(path: "../quick", branch: "quick/work", base: "origin/main"))
        )
    }

    func testWorktreeOpenAndRemoveParseTypedRequests() {
        XCTAssertEqual(
            SlashCommandParser.parse(#"/worktree open "../quill code feature""#),
            .worktreeOpen(.init(path: "../quill code feature"))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree switch ../quick"),
            .worktreeOpen(.init(path: "../quick"))
        )
        XCTAssertEqual(
            SlashCommandParser.parse(#"/wt remove "../quill code feature" --force"#),
            .worktreeRemove(.init(path: "../quill code feature", force: true))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/wt rm ../quick -f"),
            .worktreeRemove(.init(path: "../quick", force: true))
        )
    }

    func testWorktreePruneParsesTypedRequest() {
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree prune --dry-run --verbose"),
            .worktreePrune(.init(dryRun: true, verbose: true))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/wt cleanup -n -v"),
            .worktreePrune(.init(dryRun: true, verbose: true))
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree prune"),
            .worktreePrune(.init())
        )
    }

    func testWorktreeSubcommandsRejectAmbiguousOrMissingArguments() {
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree create"),
            .invalid("Missing worktree path. Try /worktree create ../feature --branch feature/name.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree open one two"),
            .invalid("Too many worktree open paths. Quote paths with spaces.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree open --bad"),
            .invalid("Unknown worktree open option '--bad'.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree list extra"),
            .invalid("Usage: /worktree list.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree create ../feature --branch"),
            .invalid("Missing branch after --branch.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree remove ../feature --hard"),
            .invalid("Unknown worktree remove option '--hard'.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree prune ../feature"),
            .invalid("Worktree prune does not take a path. Try /worktree prune --dry-run.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/worktree prune --bad"),
            .invalid("Unknown worktree prune option '--bad'.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse(#"/worktree open "../feature"#),
            .invalid("Unclosed quote in worktree command.")
        )
    }
}
