import XCTest

final class ParityWorkspacePlaywrightCommandPaletteGateTests: QuillCodeParityTestCase {
    func testPlaywrightCommandPaletteAndGitFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let commandSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("command-palette.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let commandFlowNames = [
            "runs a command from the command palette",
            "command palette scopes actions and slash commands",
            "ranks and navigates command palette with keyboard",
            "lists worktrees from the command palette",
            "prepares pull request creation from the command palette",
            "views pull request details, checks, and diff from the command palette",
            "covers the full pull request command family from the command palette",
            "runs local environment action from the command palette",
            "creates and removes worktrees from dialogs"
        ]

        Self.assertSource(commandSpecText, containsAll: [
            "harnessURL()",
            "clickSidebarTool",
            "fillCommandPalette",
            "clickCommandPaletteCommand",
            "commandPaletteResult",
            ">worktree",
            "host.git.pr.view",
            "git-pr-review-threads",
            "git-pr-review-comment",
            "git-pr-review-reply",
            "git-pr-merge",
            ".quillcode/actions/bootstrap.sh"
        ])
        Self.assertSource(commandSpecText, containsAll: commandFlowNames)
        Self.assertSource(coreSpecText, excludesAll: commandFlowNames)
    }
}
