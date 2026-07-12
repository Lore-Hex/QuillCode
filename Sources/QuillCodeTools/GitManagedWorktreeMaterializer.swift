import Foundation
import QuillCodeCore

struct GitManagedWorktreeMaterializer: Sendable {
    private let runner: GitProcessRunner
    private let limits: ManagedWorktreeTransferLimits
    private let snapshotApplier: ManagedWorktreeSnapshotApplier

    init(
        runner: GitProcessRunner,
        limits: ManagedWorktreeTransferLimits = ManagedWorktreeTransferLimits()
    ) {
        self.runner = runner
        self.limits = limits
        self.snapshotApplier = ManagedWorktreeSnapshotApplier(runner: runner)
    }

    func create(cwd: URL, path: String, base: String?) -> ToolResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-managed-worktree-\(UUID().uuidString)")
        do {
            let worktreePath = try GitWorktreeToolExecutor.safePath(path, cwd: cwd)
            let baseRef = try GitInputValidator.safeName(
                GitInputValidator.trimmedNonEmpty(base) ?? "HEAD"
            )
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

            let snapshot = try ManagedWorktreeTransferSnapshot.capture(
                sourceRoot: cwd,
                temporaryDirectory: temporaryDirectory,
                runner: runner,
                limits: limits
            )
            let create = runner.runGit(
                ["worktree", "add", "--detach", worktreePath, baseRef],
                cwd: cwd,
                timeoutSeconds: 45
            )
            guard create.ok else { return create }

            do {
                let copied = try snapshotApplier.apply(
                    snapshot,
                    to: URL(fileURLWithPath: worktreePath)
                )
                let summary = transferSummary(snapshot: snapshot, copied: copied)
                return ToolResult(
                    ok: true,
                    stdout: create.stdout + summary,
                    stderr: create.stderr,
                    exitCode: create.exitCode,
                    artifacts: [worktreePath]
                )
            } catch {
                let cleanup = runner.runGit(
                    ["worktree", "remove", "--force", "--", worktreePath],
                    cwd: cwd,
                    timeoutSeconds: 30
                )
                let cleanupDetail = cleanup.ok ? "" : " Cleanup also failed: \(cleanup.error ?? cleanup.stderr)"
                return ToolResult(ok: false, error: "\(error)\(cleanupDetail)")
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func transferSummary(snapshot: ManagedWorktreeTransferSnapshot, copied: Int) -> String {
        var lines = ["Managed worktree created detached from its base."]
        if copied > 0 {
            lines.append("Copied \(copied) safe local file\(copied == 1 ? "" : "s").")
        }
        if snapshot.skippedSymlinkCount > 0 {
            lines.append("Skipped \(snapshot.skippedSymlinkCount) local symlink\(snapshot.skippedSymlinkCount == 1 ? "" : "s").")
        }
        return "\n" + lines.joined(separator: "\n") + "\n"
    }
}
