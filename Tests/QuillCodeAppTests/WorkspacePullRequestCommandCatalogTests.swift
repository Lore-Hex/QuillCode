import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspacePullRequestCommandCatalogTests: XCTestCase {
    func testDescriptorsBuildPaletteCommandsInOrder() {
        let commands = WorkspacePullRequestCommandCatalog.commands(isEnabled: true)

        XCTAssertEqual(commands.map(\.id), [
            "git-pr-create",
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
}
