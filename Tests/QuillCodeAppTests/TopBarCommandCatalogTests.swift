import XCTest
@testable import QuillCodeApp

final class TopBarCommandCatalogTests: XCTestCase {
    func testOverflowShowsFinishOnlyWhileManagedTaskCanFinish() {
        let baseCommands = [
            command(id: "command-palette", title: "Command Palette"),
            command(id: "toggle-sidebar", title: "Toggle Sidebar"),
            command(id: "search", title: "Search"),
            command(id: "thread-finish-worktree", title: "Finish task in Local"),
            command(id: "settings", title: "Settings"),
            command(id: "keyboard-shortcuts", title: "Keyboard Shortcuts"),
            command(id: "disconnect-all", title: "Disconnect All", isEnabled: false)
        ]

        XCTAssertEqual(
            TopBarOverflowCommandCatalog.commands(
                from: baseCommands,
                showsComputerUseSetup: false
            ).map(\.id),
            [
                "command-palette",
                "toggle-sidebar",
                "search",
                "thread-finish-worktree",
                "settings",
                "keyboard-shortcuts"
            ]
        )

        let disabledFinish = baseCommands.map { command in
            command.id == "thread-finish-worktree"
                ? WorkspaceCommandSurface(
                    id: command.id,
                    title: command.title,
                    category: command.category,
                    isEnabled: false
                )
                : command
        }
        XCTAssertFalse(
            TopBarOverflowCommandCatalog.commands(
                from: disabledFinish,
                showsComputerUseSetup: false
            ).contains { $0.id == "thread-finish-worktree" }
        )
    }

    func testOverflowIncludesOnlyEnabledPublishAndPullRequestLifecycleActions() {
        let commands = [
            command(id: "thread-publish-branch", title: "Publish branch"),
            command(id: "thread-refresh-pull-request", title: "Refresh pull request"),
            command(id: "thread-land-pull-request", title: "Land pull request", isEnabled: false),
            command(id: "thread-cleanup-merged-worktree", title: "Clean up merged worktree", isEnabled: false)
        ]

        XCTAssertEqual(
            TopBarOverflowCommandCatalog.commands(
                from: commands,
                showsComputerUseSetup: false
            ).map(\.id),
            ["thread-publish-branch", "thread-refresh-pull-request"]
        )
    }

    func testProjectActionsKeepRunnableEnvironmentCommandsInSourceOrder() {
        let commands = [
            command(id: "search", title: "Search", category: WorkspaceCommandPalette.navigationCategory),
            command(id: "local-env:test", title: "Run Tests"),
            command(id: "local-env:build", title: "Run Build"),
            command(id: "local-env:disabled", title: "Run Disabled", isEnabled: false),
            command(id: "local-env:not-environment", title: "Run Wrong Category", category: WorkspaceCommandPalette.workspaceCategory)
        ]

        XCTAssertEqual(
            TopBarProjectActionCatalog.commands(from: commands).map(\.id),
            ["local-env:test", "local-env:build"]
        )
    }

    func testProjectActionsAreAbsentWhenProjectDefinesNoRunnableActions() {
        let commands = [
            command(id: "search", title: "Search", category: WorkspaceCommandPalette.navigationCategory),
            command(id: "local-env:disabled", title: "Run Disabled", isEnabled: false)
        ]

        XCTAssertTrue(TopBarProjectActionCatalog.commands(from: commands).isEmpty)
    }

    private func command(
        id: String,
        title: String,
        category: String = WorkspaceCommandPalette.environmentCategory,
        isEnabled: Bool = true
    ) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: title,
            category: category,
            isEnabled: isEnabled
        )
    }
}
