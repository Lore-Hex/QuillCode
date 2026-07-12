import Foundation
import QuillCodeCore

struct ManagedWorktreeSnapshotApplier: Sendable {
    private let runner: GitProcessRunner

    init(runner: GitProcessRunner) {
        self.runner = runner
    }

    func apply(_ snapshot: ManagedWorktreeTransferSnapshot, to destinationRoot: URL) throws -> Int {
        try preflight(snapshot.files, destinationRoot: destinationRoot)
        try apply(snapshot.stagedPatchURL, staged: true, destinationRoot: destinationRoot)
        try apply(snapshot.unstagedPatchURL, staged: false, destinationRoot: destinationRoot)
        return try copy(snapshot.files, destinationRoot: destinationRoot)
    }

    func rollback(_ snapshot: ManagedWorktreeTransferSnapshot, at destinationRoot: URL) -> ToolResult {
        let reset = runner.runGit(["reset", "--hard", "HEAD"], cwd: destinationRoot, timeoutSeconds: 30)
        var removalErrors = [String]()
        for file in snapshot.files {
            guard let destination = WorkspaceBoundary.safeURL(file.relativePath, root: destinationRoot),
                  FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: destination)
            } catch {
                removalErrors.append("\(file.relativePath): \(error.localizedDescription)")
            }
        }
        guard reset.ok, removalErrors.isEmpty else {
            let details = [reset.ok ? nil : reset.error ?? reset.stderr]
                .compactMap { $0 }
                + removalErrors
            return ToolResult(ok: false, error: details.joined(separator: "; "))
        }
        return ToolResult(ok: true)
    }

    private func preflight(_ files: [ManagedWorktreeTransferFile], destinationRoot: URL) throws {
        for file in files {
            guard let destination = WorkspaceBoundary.safeURL(file.relativePath, root: destinationRoot) else {
                throw ManagedWorktreeMaterializationError.unsafeSource(file.relativePath)
            }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw ManagedWorktreeMaterializationError.destinationAlreadyExists(file.relativePath)
            }
        }
    }

    private func apply(_ patchURL: URL, staged: Bool, destinationRoot: URL) throws {
        let size = (try? patchURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { return }
        var arguments = ["apply", "--binary", "--whitespace=nowarn"]
        if staged {
            arguments.append("--index")
        }
        arguments.append(patchURL.path)
        let result = runner.runGit(arguments, cwd: destinationRoot, timeoutSeconds: 30)
        guard result.ok else {
            throw ManagedWorktreeMaterializationError.commandFailed(
                staged ? "staged patch apply" : "unstaged patch apply",
                result
            )
        }
    }

    private func copy(_ files: [ManagedWorktreeTransferFile], destinationRoot: URL) throws -> Int {
        var copied = 0
        for file in files {
            guard let destination = WorkspaceBoundary.safeURL(file.relativePath, root: destinationRoot) else {
                throw ManagedWorktreeMaterializationError.unsafeSource(file.relativePath)
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
}
