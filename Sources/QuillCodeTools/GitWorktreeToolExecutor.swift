import Foundation
import QuillCodeCore

public struct GitWorktreeToolExecutor: Sendable {
    private let runner: GitProcessRunner
    private let managedMaterializer: GitManagedWorktreeMaterializer
    private let handoffExecutor: GitWorktreeHandoffExecutor

    public init(runner: GitProcessRunner) {
        self.runner = runner
        self.managedMaterializer = GitManagedWorktreeMaterializer(runner: runner)
        self.handoffExecutor = GitWorktreeHandoffExecutor(runner: runner)
    }

    public func list(cwd: URL) -> ToolResult {
        runGit(["worktree", "list", "--porcelain"], cwd: cwd, timeoutSeconds: 20)
    }

    public func create(
        cwd: URL,
        path: String,
        branch: String? = nil,
        base: String? = nil,
        managed: Bool = false
    ) -> ToolResult {
        if managed {
            guard GitInputValidator.trimmedNonEmpty(branch) == nil else {
                return ToolResult(ok: false, error: "Managed worktrees start detached and cannot create a branch.")
            }
            return managedMaterializer.create(cwd: cwd, path: path, base: base)
        }
        do {
            var arguments = ["worktree", "add"]
            if let branch = GitInputValidator.trimmedNonEmpty(branch) {
                arguments += ["-b", try GitInputValidator.safeName(branch)]
            }
            let worktreePath = try Self.safePath(path, cwd: cwd)
            arguments.append(worktreePath)
            if let base = GitInputValidator.trimmedNonEmpty(base) {
                arguments.append(try GitInputValidator.safeName(base))
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

    public func createBranchHere(cwd: URL, branch: String) -> ToolResult {
        do {
            let branchName = try GitInputValidator.safeName(branch)
            let currentPath = normalizedPath(cwd.path)
            let registered = registeredWorktrees(cwd: cwd)
            if let failure = registered.failure {
                return failure
            }
            guard let currentIndex = registered.records.firstIndex(where: {
                normalizedPath($0.path) == currentPath
            }) else {
                throw GitToolError.unregisteredWorktree(currentPath)
            }
            let current = registered.records[currentIndex]
            guard current.isDetached else {
                throw GitToolError.worktreeAlreadyOwnsBranch(current.branch ?? "an existing branch")
            }
            guard currentIndex > registered.records.startIndex else {
                throw GitToolError.mainWorkspaceWorktreePath
            }
            if let owner = registered.records.first(where: { $0.branch == branchName }) {
                throw GitToolError.branchCheckedOutInWorktree(branch: branchName, path: owner.path)
            }

            let existing = runGit(
                ["show-ref", "--verify", "--quiet", "refs/heads/\(branchName)"],
                cwd: cwd,
                timeoutSeconds: 10
            )
            if existing.ok {
                throw GitToolError.branchAlreadyExists(branchName)
            }
            guard existing.exitCode == 1 else { return existing }

            let result = runGit(["switch", "-c", branchName], cwd: cwd, timeoutSeconds: 30)
            guard result.ok else { return result }
            return ToolResult(
                ok: true,
                stdout: result.stdout.isEmpty ? "Created branch \(branchName).\n" : result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                artifacts: [branchName]
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func open(cwd: URL, path: String) -> ToolResult {
        do {
            let worktreePath = try Self.safePath(path, cwd: cwd)
            let registered = registeredPaths(cwd: cwd)
            if let failure = registered.failure {
                return failure
            }
            guard registered.paths.contains(worktreePath) else {
                throw GitToolError.unregisteredWorktree(worktreePath)
            }

            return ToolResult(
                ok: true,
                stdout: "worktree \(worktreePath)\n",
                artifacts: [worktreePath]
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func handoff(cwd: URL, destination: String) -> ToolResult {
        handoffExecutor.handoff(sourceRoot: cwd, destinationPath: destination)
    }

    public func remove(cwd: URL, path: String, force: Bool = false) -> ToolResult {
        do {
            let worktreePath = try Self.safePath(path, cwd: cwd)
            let registered = registeredPaths(cwd: cwd)
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

    public func prune(cwd: URL, dryRun: Bool = false, verbose: Bool = false) -> ToolResult {
        var arguments = ["worktree", "prune"]
        if dryRun {
            arguments.append("--dry-run")
        }
        if verbose {
            arguments.append("--verbose")
        }
        return runGit(arguments, cwd: cwd, timeoutSeconds: 30)
    }

    public static func safePath(_ path: String, cwd: URL) throws -> String {
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
        // A worktree lives in the workspace's PARENT dir, but must stay within it — lexically AND
        // through symlinks (a symlink under the parent must not let the worktree escape). Routed through
        // the shared WorkspaceBoundary so this gate enforces the same symlink-resolved rule as the
        // file / git-input / apply_patch validators (completes the #724 unification).
        guard WorkspaceBoundary.isWithin(candidate, root: parent) else {
            throw GitToolError.outsideWorkspace(path)
        }
        guard standardized.path != workspace.path else {
            throw GitToolError.mainWorkspaceWorktreePath
        }
        return standardized.path
    }

    private func registeredPaths(cwd: URL) -> (paths: Set<String>, failure: ToolResult?) {
        let registered = registeredWorktrees(cwd: cwd)
        if let failure = registered.failure {
            return ([], failure)
        }
        let paths = registered.records.map { normalizedPath($0.path) }
        return (Set(paths), nil)
    }

    private func registeredWorktrees(cwd: URL) -> (records: [GitWorktreeRecord], failure: ToolResult?) {
        let result = list(cwd: cwd)
        guard result.ok else {
            return ([], result)
        }
        return (GitWorktreePorcelainParser.parse(result.stdout), nil)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func runGit(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        runner.runGit(arguments, cwd: cwd, timeoutSeconds: timeoutSeconds)
    }
}
