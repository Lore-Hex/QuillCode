import XCTest
@testable import QuillCodeApp

@MainActor
final class WorkspaceCommandPaletteRankerTests: XCTestCase {
    func testRanksCommandsByShortcutKeywordsAndTitle() {
        let commands = QuillCodeWorkspaceModel().surface().commands

        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "shell").first?.id, "toggle-terminal")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "cmd+k").first?.id, "search")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "cmd+f").first?.id, "find-in-chat")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "cmd+/").first?.id, "keyboard-shortcuts")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "shortcuts").first?.id, "keyboard-shortcuts")
    }

    func testRanksMultiTokenQueriesAcrossTitlesAndKeywords() {
        let commands = QuillCodeWorkspaceModel().surface().commands

        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "create pull").first?.id, "git-pr-create")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "checks").first?.id, "git-pr-checks")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "pr diff").first?.id, "git-pr-diff")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "checkout pull").first?.id, "git-pr-checkout")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "request reviewers").first?.id, "git-pr-reviewers")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "comment pull").first?.id, "git-pr-comment")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "approve pr").first?.id, "git-pr-review")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "inline reply").first?.id, "git-pr-review-reply")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "unresolved threads").first?.id, "git-pr-review-threads")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: ">resolve thread").first?.id, "git-pr-review-thread")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "label pr").first?.id, "git-pr-labels")
        XCTAssertEqual(WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "merge pull").first?.id, "git-pr-merge")
    }

    func testSlashScopeOnlySearchesSlashCommands() {
        let commands = QuillCodeWorkspaceModel().surface().commands
        let slashResults = WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "/mode")

        XCTAssertEqual(slashResults.first?.title, "/mode auto|plan|review|read-only")
        XCTAssertTrue(slashResults.allSatisfy { $0.id.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) })
        XCTAssertEqual(
            WorkspaceCommandPaletteRanker.groupedCommands(commands, matching: "/").map(\.title),
            [WorkspaceCommandPalette.slashCategory]
        )
    }

    func testActionScopeExcludesSlashCommands() {
        let commands = QuillCodeWorkspaceModel().surface().commands
        let actionResults = WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: ">shell")

        XCTAssertEqual(actionResults.first?.id, "toggle-terminal")
        XCTAssertFalse(actionResults.contains { $0.id.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) })
    }

    func testMixedScopeAddsSlashCommandsOnlyForNonEmptyQueries() {
        let commands = QuillCodeWorkspaceModel().surface().commands

        XCTAssertFalse(
            WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "")
                .contains { $0.id.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) }
        )
        XCTAssertTrue(
            WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "mode")
                .contains { $0.id.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) }
        )
    }

    func testGroupsUsePaletteCategoryOrder() {
        let commands = QuillCodeWorkspaceModel().surface().commands
        let groups = WorkspaceCommandPaletteRanker.groupedCommands(commands, matching: ">worktree")

        XCTAssertEqual(groups.map(\.title), [WorkspaceCommandPalette.gitCategory])
        XCTAssertEqual(groups.first?.commands.map(\.id), [
            "git-worktree-list",
            "git-worktree-create",
            "git-worktree-open",
            "git-worktree-remove",
            "git-worktree-prune"
        ])
    }

    func testPublicPaletteDelegatesToRanker() {
        let commands = QuillCodeWorkspaceModel().surface().commands

        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "create pull"),
            WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: "create pull")
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.groupedCommands(commands, matching: "/"),
            WorkspaceCommandPaletteRanker.groupedCommands(commands, matching: "/")
        )
    }
}
