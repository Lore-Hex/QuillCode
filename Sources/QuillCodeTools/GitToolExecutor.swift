import Foundation
import QuillCodeCore

public struct GitToolExecutor: Sendable {
    private let shell: ShellToolExecutor
    private let runner: GitProcessRunner
    private let pullRequests: GitHubPullRequestToolExecutor
    private let worktrees: GitWorktreeToolExecutor
    private let patches: GitPatchToolExecutor

    public init(
        shell: ShellToolExecutor = ShellToolExecutor(),
        githubCLIExecutable: URL? = nil
    ) {
        self.shell = shell
        let runner = GitProcessRunner(githubCLIExecutable: githubCLIExecutable)
        self.runner = runner
        self.pullRequests = GitHubPullRequestToolExecutor(runner: runner)
        self.worktrees = GitWorktreeToolExecutor(runner: runner)
        self.patches = GitPatchToolExecutor(runner: runner)
    }

    public func status(cwd: URL) -> ToolResult {
        shell.run(.init(command: "git status --short --branch", cwd: cwd, timeoutSeconds: 15))
    }

    public func diff(cwd: URL, staged: Bool = false) -> ToolResult {
        shell.run(.init(command: staged ? "git diff --staged" : "git diff", cwd: cwd, timeoutSeconds: 20))
    }

    public func stage(cwd: URL, path: String) -> ToolResult {
        do {
            return runGit(["add", "--", try GitInputValidator.safeRelativePath(path, cwd: cwd)], cwd: cwd, timeoutSeconds: 20)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func restore(cwd: URL, path: String, staged: Bool = false) -> ToolResult {
        do {
            var arguments = ["restore"]
            if staged {
                arguments.append("--staged")
            }
            arguments += ["--", try GitInputValidator.safeRelativePath(path, cwd: cwd)]
            return runGit(arguments, cwd: cwd, timeoutSeconds: 20)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func stageHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        patches.stageHunk(cwd: cwd, path: path, patch: patch)
    }

    public func restoreHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        patches.restoreHunk(cwd: cwd, path: path, patch: patch)
    }

    public func commit(cwd: URL, message: String) -> ToolResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolResult(ok: false, error: String(describing: GitToolError.emptyCommitMessage))
        }
        return runGit(["commit", "-m", trimmed], cwd: cwd, timeoutSeconds: 30)
    }

    public func push(
        cwd: URL,
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool = false
    ) -> ToolResult {
        do {
            let remoteName = try GitInputValidator.safeName(GitInputValidator.trimmedNonEmpty(remote) ?? "origin")
            let branchName: String
            if let branch = GitInputValidator.trimmedNonEmpty(branch) {
                branchName = try GitInputValidator.safeName(branch)
            } else {
                branchName = try currentBranchName(cwd: cwd)
            }
            guard !branchName.isEmpty else {
                throw GitToolError.emptyBranch
            }

            var arguments = ["push"]
            if setUpstream {
                arguments.append("-u")
            }
            arguments += [remoteName, branchName]
            return runGit(arguments, cwd: cwd, timeoutSeconds: 120)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func createPullRequest(
        cwd: URL,
        title: String? = nil,
        body: String? = nil,
        base: String? = nil,
        head: String? = nil,
        draft: Bool = false,
        fill: Bool = false
    ) -> ToolResult {
        pullRequests.createPullRequest(
            cwd: cwd,
            title: title,
            body: body,
            base: base,
            head: head,
            draft: draft,
            fill: fill
        )
    }

    public func viewPullRequest(cwd: URL, selector: String? = nil) -> ToolResult {
        pullRequests.view(cwd: cwd, selector: selector)
    }

    public func pullRequestChecks(cwd: URL, selector: String? = nil) -> ToolResult {
        pullRequests.checks(cwd: cwd, selector: selector)
    }

    public func diffPullRequest(cwd: URL, selector: String? = nil) -> ToolResult {
        pullRequests.diff(cwd: cwd, selector: selector)
    }

    public func checkoutPullRequest(cwd: URL, selector: String? = nil, branch: String? = nil) -> ToolResult {
        pullRequests.checkout(cwd: cwd, selector: selector, branch: branch)
    }

    public func updatePullRequestReviewers(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        pullRequests.updateReviewers(cwd: cwd, selector: selector, add: add, remove: remove)
    }

    public func updatePullRequestLabels(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        pullRequests.updateLabels(cwd: cwd, selector: selector, add: add, remove: remove)
    }

    public func commentOnPullRequest(cwd: URL, selector: String? = nil, body: String) -> ToolResult {
        pullRequests.comment(cwd: cwd, selector: selector, body: body)
    }

    public func reviewPullRequest(
        cwd: URL,
        selector: String? = nil,
        action: String,
        body: String? = nil
    ) -> ToolResult {
        pullRequests.review(cwd: cwd, selector: selector, action: action, body: body)
    }

    public func mergePullRequest(
        cwd: URL,
        selector: String? = nil,
        method: String? = nil,
        auto: Bool = false,
        deleteBranch: Bool = false
    ) -> ToolResult {
        pullRequests.merge(
            cwd: cwd,
            selector: selector,
            method: method,
            auto: auto,
            deleteBranch: deleteBranch
        )
    }

    public func listWorktrees(cwd: URL) -> ToolResult {
        worktrees.list(cwd: cwd)
    }

    public func createWorktree(cwd: URL, path: String, branch: String? = nil, base: String? = nil) -> ToolResult {
        worktrees.create(cwd: cwd, path: path, branch: branch, base: base)
    }

    public func removeWorktree(cwd: URL, path: String, force: Bool = false) -> ToolResult {
        worktrees.remove(cwd: cwd, path: path, force: force)
    }

    public static func trimmedNonEmpty(_ value: String?) -> String? {
        GitInputValidator.trimmedNonEmpty(value)
    }

    public static func safeGitName(_ value: String) throws -> String {
        try GitInputValidator.safeName(value)
    }

    public static func safePullRequestSelector(_ value: String?) throws -> String? {
        try GitHubPullRequestToolExecutor.safeSelector(value)
    }

    public static func safePullRequestReviewers(_ values: [String]?) throws -> [String] {
        try GitHubPullRequestToolExecutor.safeReviewers(values)
    }

    public static func safePullRequestReviewer(_ value: String) throws -> String {
        try GitHubPullRequestToolExecutor.safeReviewer(value)
    }

    public static func safePullRequestLabels(_ values: [String]?) throws -> [String] {
        try GitHubPullRequestToolExecutor.safeLabels(values)
    }

    public static func safePullRequestLabel(_ value: String) throws -> String {
        try GitHubPullRequestToolExecutor.safeLabel(value)
    }

    public static func safePullRequestReviewFlag(_ value: String) throws -> String {
        try GitHubPullRequestToolExecutor.safeReviewFlag(value)
    }

    public static func safePullRequestMergeFlag(_ value: String?) throws -> String {
        try GitHubPullRequestToolExecutor.safeMergeFlag(value)
    }

    private func currentBranchName(cwd: URL) throws -> String {
        let result = runGit(["branch", "--show-current"], cwd: cwd, timeoutSeconds: 10)
        guard result.ok else {
            throw GitToolError.noCurrentBranch
        }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitToolError.noCurrentBranch
        }
        return try GitInputValidator.safeName(branch)
    }

    public static func extractURLs(from output: String) -> [String] {
        GitHubPullRequestToolExecutor.extractURLs(from: output)
    }

    private func runGit(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        runner.runGit(arguments, cwd: cwd, timeoutSeconds: timeoutSeconds)
    }
}
