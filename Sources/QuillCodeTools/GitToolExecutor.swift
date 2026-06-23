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
    private let githubCLIExecutable: URL?

    public init(
        shell: ShellToolExecutor = ShellToolExecutor(),
        githubCLIExecutable: URL? = nil
    ) {
        self.shell = shell
        self.githubCLIExecutable = githubCLIExecutable
    }

    public func status(cwd: URL) -> ToolResult {
        shell.run(.init(command: "git status --short --branch", cwd: cwd, timeoutSeconds: 15))
    }

    public func diff(cwd: URL, staged: Bool = false) -> ToolResult {
        shell.run(.init(command: staged ? "git diff --staged" : "git diff", cwd: cwd, timeoutSeconds: 20))
    }

    public func stage(cwd: URL, path: String) -> ToolResult {
        do {
            return runGit(["add", "--", try safeRelativePath(path, cwd: cwd)], cwd: cwd, timeoutSeconds: 20)
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
            arguments += ["--", try safeRelativePath(path, cwd: cwd)]
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
            let remoteName = try Self.safeGitName(Self.trimmedNonEmpty(remote) ?? "origin")
            let branchName: String
            if let branch = Self.trimmedNonEmpty(branch) {
                branchName = try Self.safeGitName(branch)
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
        do {
            let trimmedTitle = Self.trimmedNonEmpty(title)
            guard fill || trimmedTitle != nil else {
                throw GitToolError.emptyPullRequestTitle
            }

            var arguments = ["pr", "create"]
            if let trimmedTitle {
                arguments += ["--title", trimmedTitle]
            }
            if let body = Self.trimmedNonEmpty(body) {
                arguments += ["--body", body]
            }
            if let base = Self.trimmedNonEmpty(base) {
                arguments += ["--base", try Self.safeGitName(base)]
            }
            if let head = Self.trimmedNonEmpty(head) {
                arguments += ["--head", try Self.safeGitName(head)]
            }
            if draft {
                arguments.append("--draft")
            }
            if fill {
                arguments.append("--fill")
            }

            let result = runGitHub(arguments, cwd: cwd, timeoutSeconds: 120)
            if result.ok {
                return ToolResult(
                    ok: true,
                    stdout: result.stdout,
                    stderr: result.stderr,
                    exitCode: result.exitCode,
                    artifacts: Self.extractURLs(from: result.stdout)
                )
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func viewPullRequest(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "view"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            arguments.append("--comments")
            let result = runGitHub(arguments, cwd: cwd, timeoutSeconds: 45)
            guard result.ok else { return result }
            return ToolResult(
                ok: true,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                artifacts: Self.extractURLs(from: result.stdout)
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func pullRequestChecks(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "checks"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            return runGitHub(arguments, cwd: cwd, timeoutSeconds: 45)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func diffPullRequest(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "diff"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            return runGitHub(arguments, cwd: cwd, timeoutSeconds: 45)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func checkoutPullRequest(cwd: URL, selector: String? = nil, branch: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "checkout"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            if let branch = Self.trimmedNonEmpty(branch) {
                arguments += ["--branch", try Self.safeGitName(branch)]
            }
            return runGitHub(arguments, cwd: cwd, timeoutSeconds: 120)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func updatePullRequestReviewers(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        do {
            let reviewersToAdd = try Self.safePullRequestReviewers(add)
            let reviewersToRemove = try Self.safePullRequestReviewers(remove)
            guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
                throw GitToolError.emptyPullRequestReviewers
            }

            var arguments = ["pr", "edit"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            if !reviewersToAdd.isEmpty {
                arguments += ["--add-reviewer", reviewersToAdd.joined(separator: ",")]
            }
            if !reviewersToRemove.isEmpty {
                arguments += ["--remove-reviewer", reviewersToRemove.joined(separator: ",")]
            }

            let result = runGitHub(arguments, cwd: cwd, timeoutSeconds: 60)
            guard result.ok else { return result }
            return ToolResult(
                ok: true,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                artifacts: Self.extractURLs(from: result.stdout)
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func updatePullRequestLabels(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        do {
            let labelsToAdd = try Self.safePullRequestLabels(add)
            let labelsToRemove = try Self.safePullRequestLabels(remove)
            guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
                throw GitToolError.emptyPullRequestLabels
            }

            var arguments = ["pr", "edit"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            if !labelsToAdd.isEmpty {
                arguments += ["--add-label", labelsToAdd.joined(separator: ",")]
            }
            if !labelsToRemove.isEmpty {
                arguments += ["--remove-label", labelsToRemove.joined(separator: ",")]
            }

            let result = runGitHub(arguments, cwd: cwd, timeoutSeconds: 60)
            guard result.ok else { return result }
            return ToolResult(
                ok: true,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                artifacts: Self.extractURLs(from: result.stdout)
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func commentOnPullRequest(cwd: URL, selector: String? = nil, body: String) -> ToolResult {
        do {
            guard let body = Self.trimmedNonEmpty(body) else {
                throw GitToolError.emptyPullRequestComment
            }

            var arguments = ["pr", "comment"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            arguments += ["--body", body]

            let result = runGitHub(arguments, cwd: cwd, timeoutSeconds: 60)
            guard result.ok else { return result }
            return ToolResult(
                ok: true,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                artifacts: Self.extractURLs(from: result.stdout)
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func reviewPullRequest(
        cwd: URL,
        selector: String? = nil,
        action: String,
        body: String? = nil
    ) -> ToolResult {
        do {
            let flag = try Self.safePullRequestReviewFlag(action)
            let body = Self.trimmedNonEmpty(body)
            guard flag == "--approve" || body != nil else {
                throw GitToolError.emptyPullRequestReviewBody
            }

            var arguments = ["pr", "review"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            arguments.append(flag)
            if let body {
                arguments += ["--body", body]
            }

            let result = runGitHub(arguments, cwd: cwd, timeoutSeconds: 60)
            guard result.ok else { return result }
            return ToolResult(
                ok: true,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                artifacts: Self.extractURLs(from: result.stdout)
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func mergePullRequest(
        cwd: URL,
        selector: String? = nil,
        method: String? = nil,
        auto: Bool = false,
        deleteBranch: Bool = false
    ) -> ToolResult {
        do {
            var arguments = ["pr", "merge"]
            if let selector = try Self.safePullRequestSelector(selector) {
                arguments.append(selector)
            }
            arguments.append(try Self.safePullRequestMergeFlag(method))
            if auto {
                arguments.append("--auto")
            }
            if deleteBranch {
                arguments.append("--delete-branch")
            }

            let result = runGitHub(arguments, cwd: cwd, timeoutSeconds: 120)
            guard result.ok else { return result }
            return ToolResult(
                ok: true,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                artifacts: Self.extractURLs(from: result.stdout)
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func listWorktrees(cwd: URL) -> ToolResult {
        runGit(["worktree", "list", "--porcelain"], cwd: cwd, timeoutSeconds: 20)
    }

    public func createWorktree(cwd: URL, path: String, branch: String? = nil, base: String? = nil) -> ToolResult {
        do {
            var arguments = ["worktree", "add"]
            if let branch = Self.trimmedNonEmpty(branch) {
                arguments += ["-b", branch]
            }
            let worktreePath = try safeWorktreePath(path, cwd: cwd)
            arguments.append(worktreePath)
            if let base = Self.trimmedNonEmpty(base) {
                arguments.append(base)
            }
            let result = runGit(arguments, cwd: cwd, timeoutSeconds: 45)
            if result.ok {
                return ToolResult(
                    ok: true,
                    stdout: result.stdout,
                    stderr: result.stderr,
                    exitCode: result.exitCode,
                    artifacts: [worktreePath]
                )
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func removeWorktree(cwd: URL, path: String, force: Bool = false) -> ToolResult {
        do {
            let worktreePath = try safeWorktreePath(path, cwd: cwd)
            let registered = registeredWorktreePaths(cwd: cwd)
            if let failure = registered.failure {
                return failure
            }
            guard registered.paths.contains(worktreePath) else {
                throw GitToolError.unregisteredWorktree(worktreePath)
            }

            var arguments = ["worktree", "remove"]
            if force {
                arguments.append("--force")
            }
            arguments.append(worktreePath)
            return runGit(arguments, cwd: cwd, timeoutSeconds: 30)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func safeRelativePath(_ path: String, cwd: URL) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitToolError.emptyPath
        }

        let root = cwd.standardizedFileURL
        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : root.appendingPathComponent(trimmed)
        let standardized = candidate.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard standardized.path == root.path || standardized.path.hasPrefix(rootPath) else {
            throw GitToolError.outsideWorkspace(path)
        }
        guard standardized.path != root.path else {
            return "."
        }
        return String(standardized.path.dropFirst(rootPath.count))
    }

    private func safeWorktreePath(_ path: String, cwd: URL) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitToolError.emptyPath
        }

        let workspace = cwd.standardizedFileURL
        let parent = workspace.deletingLastPathComponent().standardizedFileURL
        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : parent.appendingPathComponent(trimmed)
        let standardized = candidate.standardizedFileURL
        let parentPath = parent.path.hasSuffix("/") ? parent.path : "\(parent.path)/"
        guard standardized.path.hasPrefix(parentPath) else {
            throw GitToolError.outsideWorkspace(path)
        }
        guard standardized.path != workspace.path else {
            throw GitToolError.mainWorkspaceWorktreePath
        }
        return standardized.path
    }

    public static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func safeGitName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitToolError.emptyBranch
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-")
        guard trimmed.rangeOfCharacter(from: allowed.inverted) == nil,
              !trimmed.hasPrefix("-"),
              !trimmed.contains("..")
        else {
            throw GitToolError.invalidGitName(value)
        }
        return trimmed
    }

    public static func safePullRequestSelector(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 300,
              !trimmed.hasPrefix("-"),
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw GitToolError.invalidPullRequestSelector(value)
        }
        return trimmed
    }

    public static func safePullRequestReviewers(_ values: [String]?) throws -> [String] {
        var reviewers: [String] = []
        var seen = Set<String>()
        for value in values ?? [] {
            let reviewer = try safePullRequestReviewer(value)
            guard seen.insert(reviewer).inserted else { continue }
            reviewers.append(reviewer)
        }
        return reviewers
    }

    public static func safePullRequestReviewer(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 80,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil,
              !trimmed.hasPrefix("-")
        else {
            throw GitToolError.invalidPullRequestReviewer(value)
        }
        if trimmed == "@copilot" {
            return trimmed
        }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ Self.isSafeGitHubReviewerComponent(String($0)) })
        else {
            throw GitToolError.invalidPullRequestReviewer(value)
        }
        return trimmed
    }

    private static func isSafeGitHubReviewerComponent(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= 39,
              value.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]$|^[A-Za-z0-9]$"#, options: .regularExpression) != nil
        else {
            return false
        }
        return true
    }

    public static func safePullRequestLabels(_ values: [String]?) throws -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for value in values ?? [] {
            let label = try safePullRequestLabel(value)
            guard seen.insert(label).inserted else { continue }
            labels.append(label)
        }
        return labels
    }

    public static func safePullRequestLabel(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 100,
              trimmed.rangeOfCharacter(from: .newlines) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil,
              !trimmed.contains(","),
              !trimmed.hasPrefix("-")
        else {
            throw GitToolError.invalidPullRequestLabel(value)
        }
        return trimmed
    }

    public static func safePullRequestReviewFlag(_ value: String) throws -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") {
        case "approve", "approved":
            return "--approve"
        case "comment", "comments":
            return "--comment"
        case "request_changes", "request_change", "changes":
            return "--request-changes"
        default:
            throw GitToolError.invalidPullRequestReviewAction(value)
        }
    }

    public static func safePullRequestMergeFlag(_ value: String?) throws -> String {
        let normalized = (trimmedNonEmpty(value) ?? "squash")
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "merge", "merge_commit":
            return "--merge"
        case "squash", "squash_merge":
            return "--squash"
        case "rebase":
            return "--rebase"
        default:
            throw GitToolError.invalidPullRequestMergeMethod(value ?? "")
        }
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
        return try Self.safeGitName(branch)
    }

    public static func extractURLs(from output: String) -> [String] {
        output
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
    }

    private func registeredWorktreePaths(cwd: URL) -> (paths: Set<String>, failure: ToolResult?) {
        let result = listWorktrees(cwd: cwd)
        guard result.ok else {
            return ([], result)
        }
        let paths = result.stdout
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard line.hasPrefix("worktree ") else { return nil }
                return URL(fileURLWithPath: String(line.dropFirst("worktree ".count)))
                    .standardizedFileURL
                    .path
            }
        return (Set(paths), nil)
    }

    private func applyHunk(
        cwd: URL,
        path: String,
        patch: String,
        arguments: [String],
        successMessage: String
    ) -> ToolResult {
        do {
            let relativePath = try safeRelativePath(path, cwd: cwd)
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
        runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git"] + arguments,
            cwd: cwd,
            timeoutSeconds: timeoutSeconds,
            toolName: "Git"
        )
    }

    private func runGitHub(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        if let githubCLIExecutable {
            return runProcess(
                executableURL: githubCLIExecutable,
                arguments: arguments,
                cwd: cwd,
                timeoutSeconds: timeoutSeconds,
                toolName: "GitHub CLI"
            )
        }
        return runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["gh"] + arguments,
            cwd: cwd,
            timeoutSeconds: timeoutSeconds,
            toolName: "GitHub CLI"
        )
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        cwd: URL,
        timeoutSeconds: TimeInterval,
        toolName: String
    ) -> ToolResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ToolResult(ok: false, error: "Failed to start \(toolName.lowercased()): \(error)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            return ToolResult(ok: false, error: "\(toolName) command timed out after \(Int(timeoutSeconds))s.")
        }

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let ok = process.terminationStatus == 0
        return ToolResult(
            ok: ok,
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus,
            error: ok ? nil : "\(toolName) command failed with exit code \(process.terminationStatus)."
        )
    }
}
