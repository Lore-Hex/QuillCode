import Foundation
import QuillCodeCore

struct GitWorktreeHandoffPreflight: Sendable {
    private let runner: GitProcessRunner

    init(runner: GitProcessRunner) {
        self.runner = runner
    }

    func plan(sourceRoot: URL, destinationPath: String) throws -> GitWorktreeHandoffPlan {
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
        let historyTransition: GitWorktreeHandoffHistoryTransition
        if sourceCommit == destinationCommit {
            historyTransition = .unchanged
        } else if try isAncestor(destinationCommit, of: sourceCommit, in: sourceRoot) {
            historyTransition = .fastForward(from: destinationCommit, to: sourceCommit)
        } else if try isAncestor(sourceCommit, of: destinationCommit, in: sourceRoot) {
            throw GitWorktreeHandoffError.destinationAhead(sourceCommit, destinationCommit)
        } else {
            throw GitWorktreeHandoffError.divergedHistory(sourceCommit, destinationCommit)
        }
        return GitWorktreeHandoffPlan(
            destinationRoot: destinationRoot,
            sourceCommit: sourceCommit,
            destinationCommit: destinationCommit,
            historyTransition: historyTransition
        )
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

    func revision(_ root: URL) throws -> String {
        let result = runner.runGit(["rev-parse", "HEAD"], cwd: root, timeoutSeconds: 20)
        guard result.ok else {
            throw GitWorktreeHandoffError.commandFailed("commit inspection", result)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAncestor(_ ancestor: String, of descendant: String, in root: URL) throws -> Bool {
        let result = runner.runGit(
            ["merge-base", "--is-ancestor", ancestor, descendant],
            cwd: root,
            timeoutSeconds: 20
        )
        if result.ok { return true }
        if result.exitCode == 1 { return false }
        throw GitWorktreeHandoffError.commandFailed("history inspection", result)
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

struct GitWorktreeHandoffPlan: Sendable, Hashable {
    var destinationRoot: URL
    var sourceCommit: String
    var destinationCommit: String
    var historyTransition: GitWorktreeHandoffHistoryTransition
}

enum GitWorktreeHandoffHistoryTransition: Sendable, Hashable {
    case unchanged
    case fastForward(from: String, to: String)

    var requiresAdvance: Bool {
        if case .fastForward = self { return true }
        return false
    }
}

enum GitWorktreeHandoffError: Error, CustomStringConvertible {
    case preflight(String)
    case commandFailed(String, ToolResult)
    case differentRepository
    case destinationAhead(String, String)
    case divergedHistory(String, String)
    case destinationNotClean
    case destinationNotCleanForHistory
    case checkoutChanged(String)
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
        case .destinationAhead(let source, let destination):
            return "Handoff stopped because the destination is ahead of the source "
                + "(source \(source.prefix(8)), destination \(destination.prefix(8))). "
                + "Move the newer task state in the other direction or reconcile the history first. "
                + "Neither checkout was changed."
        case .divergedHistory(let source, let destination):
            return "Handoff stopped because the checkouts have diverged "
                + "(source \(source.prefix(8)), destination \(destination.prefix(8))). "
                + "Reconcile the commits explicitly before handing off. Neither checkout was changed."
        case .destinationNotClean:
            return "Handoff needs a clean destination checkout or one with the exact same task changes. "
                + "Commit, stash, or move different local changes first."
        case .destinationNotCleanForHistory:
            return "Handoff can move committed history only into a clean destination checkout. "
                + "Commit, stash, or move the destination changes first."
        case .checkoutChanged(let checkout):
            return "Handoff stopped because the \(checkout) checkout changed during preflight. "
                + "Neither checkout was intentionally changed."
        case .sourceChanged:
            return "Handoff stopped because source files changed during transfer. "
                + "No newly applied destination changes were retained."
        }
    }
}
