import Foundation
import QuillCodeCore

public enum GitToolError: Error, CustomStringConvertible {
    case emptyPath
    case emptyPatch
    case emptyCommitMessage
    case emptyPullRequestTitle
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
            let remoteName = try safeGitName(trimmedNonEmpty(remote) ?? "origin")
            let branchName: String
            if let branch = trimmedNonEmpty(branch) {
                branchName = try safeGitName(branch)
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
            let trimmedTitle = trimmedNonEmpty(title)
            guard fill || trimmedTitle != nil else {
                throw GitToolError.emptyPullRequestTitle
            }

            var arguments = ["pr", "create"]
            if let trimmedTitle {
                arguments += ["--title", trimmedTitle]
            }
            if let body = trimmedNonEmpty(body) {
                arguments += ["--body", body]
            }
            if let base = trimmedNonEmpty(base) {
                arguments += ["--base", try safeGitName(base)]
            }
            if let head = trimmedNonEmpty(head) {
                arguments += ["--head", try safeGitName(head)]
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
                    artifacts: extractURLs(from: result.stdout)
                )
            }
            return result
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
            if let branch = trimmedNonEmpty(branch) {
                arguments += ["-b", branch]
            }
            let worktreePath = try safeWorktreePath(path, cwd: cwd)
            arguments.append(worktreePath)
            if let base = trimmedNonEmpty(base) {
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

    private func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func safeGitName(_ value: String) throws -> String {
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

    private func currentBranchName(cwd: URL) throws -> String {
        let result = runGit(["branch", "--show-current"], cwd: cwd, timeoutSeconds: 10)
        guard result.ok else {
            throw GitToolError.noCurrentBranch
        }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitToolError.noCurrentBranch
        }
        return try safeGitName(branch)
    }

    private func extractURLs(from output: String) -> [String] {
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

public extension ToolDefinition {
    static let gitStatus = ToolDefinition(
        name: "host.git.status",
        description: "Show git status for the project.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .local,
        risk: .read
    )

    static let gitDiff = ToolDefinition(
        name: "host.git.diff",
        description: "Show git diff for the project.",
        parametersJSON: #"{"type":"object","properties":{"staged":{"type":"boolean"}}}"#,
        host: .local,
        risk: .read
    )

    static let gitStage = ToolDefinition(
        name: "host.git.stage",
        description: "Stage one file path inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .append
    )

    static let gitRestore = ToolDefinition(
        name: "host.git.restore",
        description: "Restore one file path inside the project from git.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"staged":{"type":"boolean"}},"required":["path"]}"#,
        host: .local,
        risk: .destructive
    )

    static let gitStageHunk = ToolDefinition(
        name: "host.git.stage_hunk",
        description: "Stage one selected git diff hunk inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"patch":{"type":"string"}},"required":["path","patch"]}"#,
        host: .local,
        risk: .append
    )

    static let gitRestoreHunk = ToolDefinition(
        name: "host.git.restore_hunk",
        description: "Restore one selected git diff hunk inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"patch":{"type":"string"}},"required":["path","patch"]}"#,
        host: .local,
        risk: .destructive
    )

    static let gitCommit = ToolDefinition(
        name: "host.git.commit",
        description: "Create a git commit from already staged project changes.",
        parametersJSON: #"{"type":"object","properties":{"message":{"type":"string"}},"required":["message"]}"#,
        host: .local,
        risk: .append
    )

    static let gitPush = ToolDefinition(
        name: "host.git.push",
        description: "Push a project branch to a named git remote. Defaults to remote origin and the current branch.",
        parametersJSON: #"{"type":"object","properties":{"remote":{"type":"string"},"branch":{"type":"string"},"setUpstream":{"type":"boolean"}}}"#,
        host: .local,
        risk: .append
    )

    static let gitPullRequestCreate = ToolDefinition(
        name: "host.git.pr.create",
        description: "Create a GitHub pull request for the current project branch using GitHub CLI.",
        parametersJSON: #"{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"},"base":{"type":"string"},"head":{"type":"string"},"draft":{"type":"boolean"},"fill":{"type":"boolean"}}}"#,
        host: .local,
        risk: .append
    )

    static let gitWorktreeList = ToolDefinition(
        name: "host.git.worktree.list",
        description: "List git worktrees for the project.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .local,
        risk: .read
    )

    static let gitWorktreeCreate = ToolDefinition(
        name: "host.git.worktree.create",
        description: "Create a sibling git worktree for the project, optionally with a new branch and base ref.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"branch":{"type":"string"},"base":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .append
    )

    static let gitWorktreeRemove = ToolDefinition(
        name: "host.git.worktree.remove",
        description: "Remove a registered sibling git worktree for the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"force":{"type":"boolean"}},"required":["path"]}"#,
        host: .local,
        risk: .destructive
    )
}
