import Foundation
import QuillCodeCore

struct GitWorktreeHandoffPreflight: Sendable {
    private let runner: GitProcessRunner

    init(runner: GitProcessRunner) {
        self.runner = runner
    }

    func destination(sourceRoot: URL, destinationPath: String) throws -> URL {
        let opened = GitWorktreeToolExecutor(runner: runner).open(
            cwd: sourceRoot,
            path: destinationPath
        )
        guard opened.ok, let path = opened.artifacts.first else {
            throw GitWorktreeHandoffError.preflight(opened.error ?? opened.stderr)
        }
        let destinationRoot = URL(fileURLWithPath: path).standardizedFileURL
        guard try commonDirectory(sourceRoot) == commonDirectory(destinationRoot) else {
            throw GitWorktreeHandoffError.differentRepository
        }
        let sourceCommit = try revision(sourceRoot)
        let destinationCommit = try revision(destinationRoot)
        guard sourceCommit == destinationCommit else {
            throw GitWorktreeHandoffError.commitMismatch(sourceCommit, destinationCommit)
        }
        return destinationRoot
    }

    func isClean(_ destinationRoot: URL) throws -> Bool {
        let status = runner.runGit(
            ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
            cwd: destinationRoot,
            timeoutSeconds: 20
        )
        guard status.ok else {
            throw GitWorktreeHandoffError.commandFailed("destination status", status)
        }
        return status.stdout.isEmpty
    }

    private func revision(_ root: URL) throws -> String {
        let result = runner.runGit(["rev-parse", "HEAD"], cwd: root, timeoutSeconds: 20)
        guard result.ok else {
            throw GitWorktreeHandoffError.commandFailed("commit inspection", result)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commonDirectory(_ root: URL) throws -> URL {
        let result = runner.runGit(["rev-parse", "--git-common-dir"], cwd: root, timeoutSeconds: 20)
        guard result.ok else {
            throw GitWorktreeHandoffError.commandFailed("repository inspection", result)
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : root.appendingPathComponent(path)
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

enum GitWorktreeHandoffError: Error, CustomStringConvertible {
    case preflight(String)
    case commandFailed(String, ToolResult)
    case differentRepository
    case commitMismatch(String, String)
    case destinationNotClean
    case sourceChanged

    var description: String {
        switch self {
        case .preflight(let detail):
            return detail.isEmpty ? "Handoff could not open the destination worktree." : detail
        case .commandFailed(let operation, let result):
            let detail = result.error ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Handoff \(operation) failed." : "Handoff \(operation) failed: \(detail)"
        case .differentRepository:
            return "Handoff requires two registered checkouts from the same Git repository."
        case .commitMismatch(let source, let destination):
            return "Handoff stopped because the checkouts are on different commits (source \(source.prefix(8)), destination \(destination.prefix(8))). Neither checkout was changed."
        case .destinationNotClean:
            return "Handoff needs a clean destination checkout or one with the exact same task changes. Commit, stash, or move different local changes first."
        case .sourceChanged:
            return "Handoff stopped because source files changed during transfer. No newly applied destination changes were retained."
        }
    }
}
