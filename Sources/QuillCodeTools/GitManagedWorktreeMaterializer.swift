import Foundation
import QuillCodeCore

struct GitManagedWorktreeMaterializer: Sendable {
    private let runner: GitProcessRunner
    private let limits: ManagedWorktreeTransferLimits

    init(
        runner: GitProcessRunner,
        limits: ManagedWorktreeTransferLimits = ManagedWorktreeTransferLimits()
    ) {
        self.runner = runner
        self.limits = limits
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
                try apply(snapshot.stagedPatchURL, staged: true, worktreePath: worktreePath)
                try apply(snapshot.unstagedPatchURL, staged: false, worktreePath: worktreePath)
                let copied = try copy(snapshot.files, worktreePath: worktreePath)
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

    private func apply(_ patchURL: URL, staged: Bool, worktreePath: String) throws {
        let size = (try? patchURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { return }
        var arguments = ["apply", "--binary", "--whitespace=nowarn"]
        if staged {
            arguments.append("--index")
        }
        arguments.append(patchURL.path)
        let result = runner.runGit(
            arguments,
            cwd: URL(fileURLWithPath: worktreePath),
            timeoutSeconds: 30
        )
        guard result.ok else {
            throw ManagedWorktreeMaterializationError.commandFailed(
                staged ? "staged patch apply" : "unstaged patch apply",
                result
            )
        }
    }

    private func copy(_ files: [ManagedWorktreeTransferFile], worktreePath: String) throws -> Int {
        let destinationRoot = URL(fileURLWithPath: worktreePath).standardizedFileURL
        var copied = 0
        for file in files {
            guard let destination = WorkspaceBoundary.safeURL(file.relativePath, root: destinationRoot) else {
                throw ManagedWorktreeMaterializationError.unsafeSource(file.relativePath)
            }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw ManagedWorktreeMaterializationError.destinationAlreadyExists(file.relativePath)
            }
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: file.snapshotURL, to: destination)
                copied += 1
            } catch {
                throw ManagedWorktreeMaterializationError.fileCopyFailed(
                    file.relativePath,
                    error.localizedDescription
                )
            }
        }
        return copied
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
