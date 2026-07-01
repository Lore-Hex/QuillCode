import XCTest

final class ParityPlaywrightCommandPaletteGateTests: QuillCodeParityTestCase {
    func testPlaywrightCommandPaletteFlowsStaySplitByWorkflow() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let commandCoreSpecText = try playwrightSpec("command-palette-core.spec.ts", in: testRoot)
        let worktreeSpecText = try playwrightSpec("command-palette-worktrees.spec.ts", in: testRoot)
        let pullRequestSpecText = try playwrightSpec("command-palette-pull-requests.spec.ts", in: testRoot)
        let pullRequestReviewSpecText = try playwrightSpec("command-palette-pr-review.spec.ts", in: testRoot)
        let localEnvironmentSpecText = try playwrightSpec("command-palette-local-env.spec.ts", in: testRoot)
        let broadCoreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )

        let flowContracts: [(String, String)] = [
            "runs a command from the command palette",
            "command palette scopes actions and slash commands",
            "ranks and navigates command palette with keyboard"
        ].map { ($0, commandCoreSpecText) }
        + [
            "lists worktrees from the command palette",
            "prunes worktrees from the command palette",
            "retries failed worktree prune preview",
            "creates and removes worktrees from dialogs",
            "retries failed worktree choice loading"
        ].map { ($0, worktreeSpecText) }
        + [
            "prepares pull request creation from the command palette",
            "opens a pull request from commits via the command palette",
            "views pull request details, checks, and diff from the palette",
            "covers pull request command visibility and draft actions"
        ].map { ($0, pullRequestSpecText) }
        + [
            "submits pull request review with inline notes from the palette",
            "lists pull request review threads from the command palette"
        ].map { ($0, pullRequestReviewSpecText) }
        + [
            "runs local environment action from the command palette"
        ].map { ($0, localEnvironmentSpecText) }

        Self.assertSource(commandCoreSpecText, containsAll: [
            "harnessURL()",
            "openCommandPalette",
            "fillCommandPalette",
            "clickCommandPaletteCommand",
            "expectSelectedCommandPaletteResult",
            ">worktree"
        ])
        Self.assertSource(worktreeSpecText, containsAll: [
            "expectWorktreeChoicesLoaded",
            "commandPaletteResult",
            ">worktree",
            "git-worktree-prune",
            "git-worktree-create",
            "git-worktree-open",
            "git-worktree-remove"
        ])
        Self.assertSource(pullRequestSpecText, containsAll: [
            "pullRequestCommandIDs",
            "draftCommands",
            "host.git.pr.view",
            "git-pr-review-comment",
            "git-pr-merge"
        ])
        Self.assertSource(pullRequestReviewSpecText, containsAll: [
            "host.git.pr.review",
            "host.git.pr.review_comment",
            "git-pr-review-threads"
        ])
        Self.assertSource(localEnvironmentSpecText, containsAll: [
            ".quillcode/actions/bootstrap.sh"
        ])
        for (flowName, specText) in flowContracts {
            Self.assertSource(specText, contains: flowName)
            Self.assertSource(broadCoreSpecText, excludes: flowName)
        }
    }

    private func playwrightSpec(_ name: String, in testRoot: URL) throws -> String {
        try String(contentsOf: testRoot.appendingPathComponent(name), encoding: .utf8)
    }
}
