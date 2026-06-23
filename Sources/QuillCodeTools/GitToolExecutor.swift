import Foundation
import QuillCodeCore

public enum GitToolError: Error, CustomStringConvertible {
    case emptyPath
    case emptyPatch
    case emptyCommitMessage
    case emptyPullRequestTitle
    case emptyPullRequestComment
    case emptyPullRequestReviewBody
    case emptyPullRequestReviewers
    case emptyPullRequestLabels
    case invalidPullRequestReviewAction(String)
    case invalidPullRequestMergeMethod(String)
    case invalidPullRequestSelector(String)
    case invalidPullRequestReviewer(String)
    case invalidPullRequestLabel(String)
    case emptyBranch
    case invalidGitName(String)
    case noCurrentBranch
    case outsideWorkspace(String)
    case mainWorkspaceWorktreePath
    case unregisteredWorktree(String)
    case patchPathMismatch(String)
    case temporaryPatchFailed(String)

    public var description: String {
        switch self {
        case .emptyPath:
            return "Git path is required."
        case .emptyPatch:
            return "Git patch is empty."
        case .emptyCommitMessage:
            return "Git commit message is required."
        case .emptyPullRequestTitle:
            return "Git pull request title is required unless fill is enabled."
        case .emptyPullRequestComment:
            return "Git pull request comment body is required."
        case .emptyPullRequestReviewBody:
            return "Git pull request review body is required for comment and request_changes actions."
        case .emptyPullRequestReviewers:
            return "At least one GitHub pull request reviewer to add or remove is required."
        case .emptyPullRequestLabels:
            return "At least one GitHub pull request label to add or remove is required."
        case .invalidPullRequestReviewAction(let value):
            return "GitHub pull request review action is unsupported: \(value)"
        case .invalidPullRequestMergeMethod(let value):
            return "GitHub pull request merge method is unsupported: \(value)"
        case .invalidPullRequestSelector(let value):
            return "GitHub pull request selector is unsupported: \(value)"
        case .invalidPullRequestReviewer(let value):
            return "GitHub pull request reviewer is unsupported: \(value)"
        case .invalidPullRequestLabel(let value):
            return "GitHub pull request label is unsupported: \(value)"
        case .emptyBranch:
            return "Git branch is required."
        case .invalidGitName(let value):
            return "Git remote or branch contains unsupported characters: \(value)"
        case .noCurrentBranch:
            return "Git push needs a branch, but the current checkout has no branch."
        case .outsideWorkspace(let path):
            return "Git path is outside the workspace: \(path)"
        case .mainWorkspaceWorktreePath:
            return "Git worktree path cannot be the main workspace."
        case .unregisteredWorktree(let path):
            return "Git worktree is not registered: \(path)"
        case .patchPathMismatch(let path):
            return "Git patch touches a different path than requested: \(path)"
        case .temporaryPatchFailed(let message):
            return "Failed to prepare git patch: \(message)"
        }
    }
}

public struct GitToolExecutor: Sendable {
    private let shell: ShellToolExecutor
    private let runner: GitProcessRunner
    private let pullRequests: GitHubPullRequestToolExecutor
    private let worktrees: GitWorktreeToolExecutor

    public init(
        shell: ShellToolExecutor = ShellToolExecutor(),
        githubCLIExecutable: URL? = nil
    ) {
        self.shell = shell
        let runner = GitProcessRunner(githubCLIExecutable: githubCLIExecutable)
        self.runner = runner
        self.pullRequests = GitHubPullRequestToolExecutor(runner: runner)
        self.worktrees = GitWorktreeToolExecutor(runner: runner)
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
        applyHunk(cwd: cwd, path: path, patch: patch, arguments: ["apply", "--cached", "--whitespace=nowarn"], successMessage: "Hunk staged.\n")
    }

    public func restoreHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        applyHunk(cwd: cwd, path: path, patch: patch, arguments: ["apply", "--reverse", "--whitespace=nowarn"], successMessage: "Hunk restored.\n")
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

    private func applyHunk(
        cwd: URL,
        path: String,
        patch: String,
        arguments: [String],
        successMessage: String
    ) -> ToolResult {
        do {
            let relativePath = try GitInputValidator.safeRelativePath(path, cwd: cwd)
            let trimmedPatch = patch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPatch.isEmpty else {
                throw GitToolError.emptyPatch
            }
            if let mismatch = Self.mismatchedPatchPath(in: patch, expectedPath: relativePath) {
                throw GitToolError.patchPathMismatch(mismatch)
            }

            var normalizedPatch = patch
            if !normalizedPatch.hasSuffix("\n") {
                normalizedPatch.append("\n")
            }
            let patchURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("quillcode-hunk-\(UUID().uuidString).patch")
            do {
                try normalizedPatch.write(to: patchURL, atomically: true, encoding: .utf8)
            } catch {
                throw GitToolError.temporaryPatchFailed(String(describing: error))
            }
            defer { try? FileManager.default.removeItem(at: patchURL) }

            let check = runGit(arguments + ["--check", patchURL.path], cwd: cwd, timeoutSeconds: 20)
            guard check.ok else { return check }
            let apply = runGit(arguments + [patchURL.path], cwd: cwd, timeoutSeconds: 20)
            if apply.ok {
                return ToolResult(ok: true, stdout: successMessage, stderr: apply.stderr, exitCode: apply.exitCode)
            }
            return apply
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public static func mismatchedPatchPath(in patch: String, expectedPath: String) -> String? {
        for line in patch.components(separatedBy: .newlines) {
            guard line.hasPrefix("--- ") || line.hasPrefix("+++ ") || line.hasPrefix("diff --git ") else {
                continue
            }
            for path in pathsInDiffMetadataLine(line) {
                guard path != "/dev/null" else { continue }
                let normalized = normalizedPatchPath(path)
                guard normalized == expectedPath else {
                    return normalized
                }
            }
        }
        return nil
    }

    private static func pathsInDiffMetadataLine(_ line: String) -> [String] {
        if line.hasPrefix("diff --git ") {
            return pathsInDiffGitHeader(String(line.dropFirst("diff --git ".count)))
        }
        return line
            .dropFirst(4)
            .split(separator: "\t")
            .first
            .map { [String($0)] } ?? []
    }

    private static func pathsInDiffGitHeader(_ header: String) -> [String] {
        if header.hasPrefix("\"") {
            return quotedPaths(in: header)
        }
        guard let secondPathRange = header.range(of: " b/") else {
            return header.split(separator: " ").map(String.init)
        }
        let first = String(header[..<secondPathRange.lowerBound])
        let second = String(header[header.index(after: secondPathRange.lowerBound)...])
        return [first, second]
    }

    private static func quotedPaths(in header: String) -> [String] {
        var paths: [String] = []
        var current = ""
        var isInQuote = false
        var isEscaped = false

        for character in header {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                if isInQuote {
                    paths.append(current)
                    current = ""
                }
                isInQuote.toggle()
                continue
            }
            if isInQuote {
                current.append(character)
            }
        }
        return paths
    }

    private static func normalizedPatchPath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("\"") {
            path.removeFirst()
        }
        if path.hasSuffix("\"") {
            path.removeLast()
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path.removeFirst(2)
        }
        return path
    }

    private func runGit(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        runner.runGit(arguments, cwd: cwd, timeoutSeconds: timeoutSeconds)
    }
}
