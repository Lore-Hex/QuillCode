import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspacePullRequestCommandCatalogTests: XCTestCase {
    func testDescriptorsBuildPaletteCommandsInOrder() {
        let commands = WorkspacePullRequestCommandCatalog.commands(isEnabled: true)

        XCTAssertEqual(commands.map(\.id), [
            "git-pr-create",
            "git-pr-fill",
            "git-pr-list",
            "git-pr-view",
            "git-pr-checks",
            "git-pr-diff",
            "git-pr-checkout",
            "git-pr-reviewers",
            "git-pr-comment",
            "git-pr-review",
            "git-pr-review-comment",
            "git-pr-review-reply",
            "git-pr-review-threads",
            "git-pr-review-thread",
            "git-pr-labels",
            "git-pr-merge"
        ])
        XCTAssertTrue(commands.allSatisfy(\.isEnabled))
        XCTAssertEqual(commands.first?.category, WorkspaceCommandPalette.gitCategory)
    }

    func testDescriptorsOwnCommandPlansAndIcons() {
        XCTAssertEqual(
            WorkspacePullRequestCommandCatalog.toolNameByCommandID,
            [
                "git-pr-list": ToolDefinition.gitPullRequestList.name,
                "git-pr-view": ToolDefinition.gitPullRequestView.name,
                "git-pr-checks": ToolDefinition.gitPullRequestChecks.name,
                "git-pr-diff": ToolDefinition.gitPullRequestDiff.name,
                "git-pr-review-threads": ToolDefinition.gitPullRequestReviewThreads.name
            ]
        )
        XCTAssertEqual(
            WorkspacePullRequestCommandCatalog.draftByCommandID["git-pr-review-thread"],
            "Resolve pull request review thread: "
        )
        XCTAssertEqual(
            QuillCodeCommandIconCatalog.systemImage(for: "git-pr-checks"),
            "checklist"
        )
    }

    func testDescriptorsOwnSlashDefinitionsUsedByCatalog() {
        let slashDefinitions = WorkspacePullRequestCommandCatalog.slashDefinitions
        let slashUsages = slashDefinitions.map(\.usage)

        XCTAssertEqual(slashUsages, [
            "/pr create",
            "/pr fill",
            "/pr list [open|closed|merged|all] [limit]",
            "/pr view [selector]",
            "/pr checks [selector]",
            "/pr diff [selector]",
            "/pr checkout selector",
            "/pr reviewers add|remove login",
            "/pr comment body",
            "/pr review approve|comment|request_changes",
            "/pr review-comment path line body",
            "/pr review-reply commentId body",
            "/pr review-threads [selector]",
            "/pr review-thread resolve|unresolve threadId",
            "/pr labels add|remove label",
            "/pr merge [squash|merge|rebase]"
        ])
        XCTAssertEqual(
            slashDefinitions.first { $0.usage == "/pr labels add|remove label" }?.insertText,
            "/pr labels add "
        )

        let catalogPullRequestUsages = SlashCommandCatalog.definitions
            .filter { $0.usage.hasPrefix("/pr ") }
            .map(\.usage)
        XCTAssertEqual(catalogPullRequestUsages, slashUsages)
        XCTAssertTrue(SlashCommandCatalog.helpText().contains("/pr list [open|closed|merged|all] [limit]"))
        XCTAssertTrue(SlashCommandCatalog.helpText().contains("/pr review-threads [selector]"))
    }
}
