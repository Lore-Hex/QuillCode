import Foundation
import QuillCodeCore

extension ManagedWorktreeSnapshotStore {
    /// Removes a captured disposable worktree only when its commit, index, working tree, and local
    /// files still match the durable snapshot. Keeping verification and removal in one store API
    /// prevents callers from bypassing the final loss-prevention boundary.
    public func removeIfUnchanged(
        threadID: UUID,
        reference: WorktreeSnapshotReference,
        binding: WorktreeBinding,
        projectRoot: URL
    ) throws {
        guard binding.isDisposableManagedWorktree,
              binding.isResolvable,
              binding.snapshot == reference else {
            throw ManagedWorktreeSnapshotError.invalidBinding(binding.path)
        }
        let snapshotRoot = snapshotDirectory(reference.id)
        guard FileManager.default.fileExists(atPath: snapshotRoot.path) else {
            throw ManagedWorktreeSnapshotError.snapshotMissing(reference.id)
        }
        let manifest = try readManifest(from: snapshotRoot)
        try validate(manifest: manifest, threadID: threadID, reference: reference, binding: binding)

        let root = projectRoot.standardizedFileURL
        guard try repositoryCommonDirectory(cwd: root) == manifest.repositoryCommonDirectory else {
            throw ManagedWorktreeSnapshotError.repositoryMismatch
        }
        let sourceRoot = URL(fileURLWithPath: binding.path).standardizedFileURL
        let sourcePath = normalizedPath(sourceRoot)
        let records = try registeredWorktrees(cwd: root)
        guard let recordIndex = records.firstIndex(where: { normalizedPath($0.path) == sourcePath }),
              recordIndex > records.startIndex,
              records[recordIndex].isDetached else {
            throw ManagedWorktreeSnapshotError.unregisteredWorktree(binding.path)
        }
        guard try requiredGitOutput(
            ["rev-parse", "--verify", "HEAD"],
            cwd: sourceRoot,
            operation: "rechecking the managed worktree commit"
        ) == reference.headCommit else {
            throw ManagedWorktreeSnapshotError.sourceChanged
        }

        let expected = try transferSnapshot(from: manifest, snapshotRoot: snapshotRoot)
        try verify(expected, matches: sourceRoot, mismatchError: .sourceChanged)
        let removal = runner.runGit(
            ["worktree", "remove", "--force", "--", sourceRoot.path],
            cwd: root,
            timeoutSeconds: 45
        )
        guard removal.ok else {
            throw gitError("removing the captured managed worktree", result: removal)
        }
    }
}
