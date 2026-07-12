import Foundation
import QuillCodeCore

struct GitWorktreeHandoffHistoryTransfer: Sendable {
    private let runner: GitProcessRunner

    init(runner: GitProcessRunner) {
        self.runner = runner
    }

    func apply(_ transition: GitWorktreeHandoffHistoryTransition, at destinationRoot: URL) throws {
        guard case .fastForward(_, let target) = transition else { return }
        let result = runner.runGit(
            ["merge", "--ff-only", "--no-edit", target],
            cwd: destinationRoot,
            timeoutSeconds: 45
        )
        guard result.ok else {
            throw GitWorktreeHandoffError.commandFailed("history fast-forward", result)
        }
        guard try revision(at: destinationRoot) == target else {
            throw GitWorktreeHandoffError.checkoutChanged("destination")
        }
    }

    func rollback(_ transition: GitWorktreeHandoffHistoryTransition, at destinationRoot: URL) -> ToolResult {
        guard case .fastForward(let original, let target) = transition else {
            return ToolResult(ok: true)
        }
        do {
            let current = try revision(at: destinationRoot)
            if current == original {
                return ToolResult(ok: true)
            }
            guard current == target else {
                return ToolResult(
                    ok: false,
                    error: "Destination history changed again during Handoff; refusing to rewrite it during rollback."
                )
            }
            let result = runner.runGit(
                ["reset", "--hard", original],
                cwd: destinationRoot,
                timeoutSeconds: 30
            )
            guard result.ok else {
                return ToolResult(
                    ok: false,
                    error: "Could not restore the destination commit after Handoff failed: "
                        + (result.error ?? result.stderr)
                )
            }
            return ToolResult(ok: true)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    func summary(for transition: GitWorktreeHandoffHistoryTransition) -> String {
        switch transition {
        case .unchanged:
            return "Committed history was already aligned."
        case .fastForward(let original, let target):
            return "Fast-forwarded committed history from \(original.prefix(8)) to \(target.prefix(8))."
        }
    }

    private func revision(at root: URL) throws -> String {
        let result = runner.runGit(["rev-parse", "HEAD"], cwd: root, timeoutSeconds: 20)
        guard result.ok else {
            throw GitWorktreeHandoffError.commandFailed("commit inspection", result)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
