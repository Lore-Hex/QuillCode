import Foundation
import QuillCodeCore

public struct GitToolExecutor: Sendable {
    private let local: GitLocalToolExecutor
    private let pullRequests: GitHubPullRequestToolExecutor
    private let worktrees: GitWorktreeToolExecutor
    private let patches: GitPatchToolExecutor

    public init(
        shell: ShellToolExecutor = ShellToolExecutor(),
        githubCLIExecutable: URL? = nil,
        managedWorktreeRoot: URL? = nil
    ) {
        let runner = GitProcessRunner(githubCLIExecutable: githubCLIExecutable)
        self.local = GitLocalToolExecutor(shell: shell, runner: runner)
        self.pullRequests = GitHubPullRequestToolExecutor(runner: runner)
        self.worktrees = GitWorktreeToolExecutor(runner: runner, managedRoot: managedWorktreeRoot)
        self.patches = GitPatchToolExecutor(runner: runner)
    }

    public func status(cwd: URL) -> ToolResult {
        local.status(cwd: cwd)
    }

    public func diff(
        cwd: URL,
        staged: Bool = false,
        commit: String? = nil,
        baseBranch: String? = nil
    ) -> ToolResult {
        local.diff(cwd: cwd, staged: staged, commit: commit, baseBranch: baseBranch)
    }

    public func fetch(cwd: URL, remote: String? = nil, prune: Bool = false) -> ToolResult {
        local.fetch(cwd: cwd, remote: remote, prune: prune)
    }

    public func pull(
        cwd: URL,
        remote: String? = nil,
        branch: String? = nil,
        ffOnly: Bool = true
    ) -> ToolResult {
        local.pull(cwd: cwd, remote: remote, branch: branch, ffOnly: ffOnly)
    }

    public func listBranches(cwd: URL, includeRemote: Bool = true) -> ToolResult {
        local.listBranches(cwd: cwd, includeRemote: includeRemote)
    }

    public func switchBranch(
        cwd: URL,
        branch: String,
        create: Bool = false,
        startPoint: String? = nil
    ) -> ToolResult {
        local.switchBranch(cwd: cwd, branch: branch, create: create, startPoint: startPoint)
    }

    public func stage(cwd: URL, path: String) -> ToolResult {
        local.stage(cwd: cwd, path: path)
    }

    public func restore(cwd: URL, path: String, staged: Bool = false) -> ToolResult {
        local.restore(cwd: cwd, path: path, staged: staged)
    }

    public func stageHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        patches.stageHunk(cwd: cwd, path: path, patch: patch)
    }

    public func unstageHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        patches.unstageHunk(cwd: cwd, path: path, patch: patch)
    }

    public func restoreHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        patches.restoreHunk(cwd: cwd, path: path, patch: patch)
    }

    public func commit(cwd: URL, message: String) -> ToolResult {
        local.commit(cwd: cwd, message: message)
    }

    public func push(
        cwd: URL,
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool = false
    ) -> ToolResult {
        local.push(cwd: cwd, remote: remote, branch: branch, setUpstream: setUpstream)
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

    public func listPullRequests(cwd: URL, state: String? = nil, limit: Int? = nil) -> ToolResult {
        pullRequests.list(cwd: cwd, state: state, limit: limit)
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

    public func updatePullRequestLifecycle(cwd: URL, selector: String? = nil, action: String) -> ToolResult {
        pullRequests.updateLifecycle(cwd: cwd, selector: selector, action: action)
    }

    public func reviewPullRequest(
        cwd: URL,
        selector: String? = nil,
        action: String,
        body: String? = nil
    ) -> ToolResult {
        pullRequests.review(cwd: cwd, selector: selector, action: action, body: body)
    }

    public func commentOnPullRequestLine(
        cwd: URL,
        selector: String? = nil,
        path: String,
        line: Int,
        side: String? = nil,
        body: String,
        startLine: Int? = nil,
        startSide: String? = nil
    ) -> ToolResult {
        pullRequests.reviewComment(
            cwd: cwd,
            selector: selector,
            path: path,
            line: line,
            side: side,
            body: body,
            startLine: startLine,
            startSide: startSide
        )
    }

    public func replyToPullRequestReviewComment(
        cwd: URL,
        selector: String? = nil,
        commentID: Int,
        body: String
    ) -> ToolResult {
        pullRequests.reviewReply(cwd: cwd, selector: selector, commentID: commentID, body: body)
    }

    public func listPullRequestReviewThreads(cwd: URL, selector: String? = nil) -> ToolResult {
        pullRequests.reviewThreads(cwd: cwd, selector: selector)
    }

    public func updatePullRequestReviewThread(
        cwd: URL,
        threadID: String,
        action: String
    ) -> ToolResult {
        pullRequests.reviewThread(cwd: cwd, threadID: threadID, action: action)
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

    public func createWorktree(
        cwd: URL,
        path: String,
        branch: String? = nil,
        base: String? = nil,
        managed: Bool = false
    ) -> ToolResult {
        worktrees.create(cwd: cwd, path: path, branch: branch, base: base, managed: managed)
    }

    public func openWorktree(cwd: URL, path: String) -> ToolResult {
        worktrees.open(cwd: cwd, path: path)
    }

    public func handoffWorktree(cwd: URL, destination: String) -> ToolResult {
        worktrees.handoff(cwd: cwd, destination: destination)
    }

    public func createWorktreeBranch(cwd: URL, branch: String) -> ToolResult {
        worktrees.createBranchHere(cwd: cwd, branch: branch)
    }

    public func removeWorktree(cwd: URL, path: String, force: Bool = false) -> ToolResult {
        worktrees.remove(cwd: cwd, path: path, force: force)
    }

    public func pruneWorktrees(cwd: URL, dryRun: Bool = false, verbose: Bool = false) -> ToolResult {
        worktrees.prune(cwd: cwd, dryRun: dryRun, verbose: verbose)
    }

    public static func trimmedNonEmpty(_ value: String?) -> String? {
        GitInputValidator.trimmedNonEmpty(value)
    }

    public static func safeGitName(_ value: String) throws -> String {
        try GitInputValidator.safeName(value)
    }

    public static func safePullRequestSelector(_ value: String?) throws -> String? {
        try GitHubPullRequestInputValidator.safeSelector(value)
    }

    public static func safePullRequestReviewers(_ values: [String]?) throws -> [String] {
        try GitHubPullRequestInputValidator.safeReviewers(values)
    }

    public static func safePullRequestReviewer(_ value: String) throws -> String {
        try GitHubPullRequestInputValidator.safeReviewer(value)
    }

    public static func safePullRequestLabels(_ values: [String]?) throws -> [String] {
        try GitHubPullRequestInputValidator.safeLabels(values)
    }

    public static func safePullRequestLabel(_ value: String) throws -> String {
        try GitHubPullRequestInputValidator.safeLabel(value)
    }

    public static func safePullRequestReviewFlag(_ value: String) throws -> String {
        try GitHubPullRequestInputValidator.safeReviewFlag(value)
    }

    public static func safePullRequestMergeFlag(_ value: String?) throws -> String {
        try GitHubPullRequestInputValidator.safeMergeFlag(value)
    }

    public static func safePullRequestLifecycleAction(_ value: String) throws -> String {
        try GitHubPullRequestInputValidator.safeLifecycleAction(value)
    }

    public static func safePullRequestReviewLine(_ value: Int) throws -> Int {
        try GitHubPullRequestInputValidator.safeReviewLine(value)
    }

    public static func safePullRequestReviewSide(_ value: String?) throws -> String {
        try GitHubPullRequestInputValidator.safeReviewSide(value)
    }

    public static func safePullRequestReviewCommentID(_ value: Int) throws -> Int {
        try GitHubPullRequestInputValidator.safeReviewCommentID(value)
    }

    public static func safePullRequestReviewThreadID(_ value: String) throws -> String {
        try GitHubPullRequestInputValidator.safeReviewThreadID(value)
    }

    public static func safePullRequestReviewThreadAction(_ value: String) throws -> String {
        try GitHubPullRequestInputValidator.safeReviewThreadAction(value)
    }

    public static func extractURLs(from output: String) -> [String] {
        GitHubPullRequestOutputParser.extractURLs(from: output)
    }
}
