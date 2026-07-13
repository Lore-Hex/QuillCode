import XCTest
@testable import QuillCodeApp

final class TopBarCommandCatalogTests: XCTestCase {
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
