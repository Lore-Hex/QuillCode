import Foundation
import QuillCodeCore

public struct GitWorktreeToolExecutor: Sendable {
    private let runner: GitProcessRunner

    public init(runner: GitProcessRunner) {
        self.runner = runner
    }

    public func list(cwd: URL) -> ToolResult {
        runGit(["worktree", "list", "--porcelain"], cwd: cwd, timeoutSeconds: 20)
    }

    public func create(cwd: URL, path: String, branch: String? = nil, base: String? = nil) -> ToolResult {
        do {
            var arguments = ["worktree", "add"]
            if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
                arguments += ["-b", try GitToolExecutor.safeGitName(branch)]
            }
            let worktreePath = try Self.safePath(path, cwd: cwd)
            arguments.append(worktreePath)
            if let base = GitToolExecutor.trimmedNonEmpty(base) {
                arguments.append(try GitToolExecutor.safeGitName(base))
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
        let parentPath = parent.path.hasSuffix("/") ? parent.path : "\(parent.path)/"
        guard standardized.path.hasPrefix(parentPath) else {
            throw GitToolError.outsideWorkspace(path)
        }
        guard standardized.path != workspace.path else {
            throw GitToolError.mainWorkspaceWorktreePath
        }
        return standardized.path
    }

    private func registeredPaths(cwd: URL) -> (paths: Set<String>, failure: ToolResult?) {
        let result = list(cwd: cwd)
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

    private func runGit(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        runner.runGit(arguments, cwd: cwd, timeoutSeconds: timeoutSeconds)
    }
}
