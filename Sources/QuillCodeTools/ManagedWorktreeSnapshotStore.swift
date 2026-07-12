import Foundation
import QuillCodeCore

public enum ManagedWorktreeSnapshotError: Error, LocalizedError, Sendable, Equatable {
    case invalidBinding(String)
    case unregisteredWorktree(String)
    case repositoryMismatch
    case snapshotMissing(UUID)
    case snapshotCorrupt(String)
    case destinationExists(String)
    case gitFailed(String, String)
    case filesystemFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBinding(let detail):
            "This task does not own a disposable worktree: \(detail)"
        case .unregisteredWorktree(let path):
            "The managed worktree is not registered with git: \(path)"
        case .repositoryMismatch:
            "The snapshot belongs to a different git repository."
        case .snapshotMissing(let id):
            "The saved worktree snapshot is missing: \(id.uuidString)"
        case .snapshotCorrupt(let detail):
            "The saved worktree snapshot is invalid: \(detail)"
        case .destinationExists(let path):
            "The worktree cannot be restored because the destination already exists: \(path)"
        case .gitFailed(let operation, let detail):
            "Git failed while \(operation): \(detail)"
        case .filesystemFailed(let detail):
            "The worktree snapshot could not be saved: \(detail)"
        }
    }
}

public struct ManagedWorktreeSnapshotRestoreResult: Sendable, Hashable {
    public var path: String
    public var restoredFileCount: Int

    public init(path: String, restoredFileCount: Int) {
        self.path = path
        self.restoredFileCount = restoredFileCount
    }
}

/// Persists the exact staged, unstaged, and safe local-file state of a disposable managed worktree.
/// Snapshots are repository-bound and restored at the captured commit, so archive cleanup cannot
/// silently move a task onto newer code or into a different checkout.
public struct ManagedWorktreeSnapshotStore: Sendable {
    private static let manifestVersion = 1

    private let directory: URL
    private let runner: GitProcessRunner
    private let limits: ManagedWorktreeTransferLimits

    public init(directory: URL, runner: GitProcessRunner = GitProcessRunner()) {
        self.directory = directory
        self.runner = runner
        self.limits = ManagedWorktreeTransferLimits()
    }

    public func capture(
        threadID: UUID,
        binding: WorktreeBinding
    ) throws -> WorktreeSnapshotReference {
        guard binding.isDisposableManagedWorktree, binding.isResolvable else {
            throw ManagedWorktreeSnapshotError.invalidBinding(binding.path)
        }

        let sourceRoot = URL(fileURLWithPath: binding.path).standardizedFileURL
        let records = try registeredWorktrees(cwd: sourceRoot)
        let sourcePath = normalizedPath(sourceRoot)
        guard let recordIndex = records.firstIndex(where: { normalizedPath($0.path) == sourcePath }),
              recordIndex > records.startIndex,
              records[recordIndex].isDetached else {
            throw ManagedWorktreeSnapshotError.unregisteredWorktree(binding.path)
        }

        let headCommit = try requiredGitOutput(
            ["rev-parse", "--verify", "HEAD"],
            cwd: sourceRoot,
            operation: "reading the managed worktree commit"
        )
        let commonDirectory = try repositoryCommonDirectory(cwd: sourceRoot)
        let snapshotID = UUID()
        let temporaryRoot = directory.appendingPathComponent(".capture-\(snapshotID.uuidString)")
        let destination = snapshotDirectory(snapshotID)

        do {
            try ensurePrivateDirectory(directory)
            try ensurePrivateDirectory(temporaryRoot)
            let transfer = try ManagedWorktreeTransferSnapshot.capture(
                sourceRoot: sourceRoot,
                temporaryDirectory: temporaryRoot,
                runner: runner,
                localFilePolicy: .managedCreation,
                limits: limits
            )
            let byteCount = try payloadByteCount(transfer)
            let reference = WorktreeSnapshotReference(
                id: snapshotID,
                capturedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
                headCommit: headCommit,
                fileCount: transfer.files.count,
                byteCount: byteCount
            )
            let manifest = Manifest(
                version: Self.manifestVersion,
                threadID: threadID,
                reference: reference,
                originalPath: sourcePath,
                repositoryCommonDirectory: commonDirectory,
                branch: binding.branch,
                base: binding.base,
                filePaths: transfer.files.map(\.relativePath),
                skippedSymlinkCount: transfer.skippedSymlinkCount
            )
            try writeManifest(manifest, to: temporaryRoot)
            try FileManager.default.moveItem(at: temporaryRoot, to: destination)
            try setPrivatePermissions(destination)
            return reference
        } catch {
            try? FileManager.default.removeItem(at: temporaryRoot)
            if let snapshotError = error as? ManagedWorktreeSnapshotError {
                throw snapshotError
            }
            throw ManagedWorktreeSnapshotError.filesystemFailed(error.localizedDescription)
        }
    }

    public func restore(
        threadID: UUID,
        reference: WorktreeSnapshotReference,
        binding: WorktreeBinding,
        projectRoot: URL
    ) throws -> ManagedWorktreeSnapshotRestoreResult {
        guard binding.canRestoreSnapshot, binding.snapshot == reference else {
            throw ManagedWorktreeSnapshotError.invalidBinding(binding.path)
        }

        let snapshotRoot = snapshotDirectory(reference.id)
        guard FileManager.default.fileExists(atPath: snapshotRoot.path) else {
            throw ManagedWorktreeSnapshotError.snapshotMissing(reference.id)
        }
        let manifest = try readManifest(from: snapshotRoot)
        try validate(
            manifest: manifest,
            threadID: threadID,
            reference: reference,
            binding: binding
        )

        let root = projectRoot.standardizedFileURL
        guard try repositoryCommonDirectory(cwd: root) == manifest.repositoryCommonDirectory else {
            throw ManagedWorktreeSnapshotError.repositoryMismatch
        }
        let targetPath: String
        do {
            targetPath = try GitWorktreeToolExecutor.safePath(binding.path, cwd: root)
        } catch {
            throw ManagedWorktreeSnapshotError.invalidBinding(error.localizedDescription)
        }
        guard !FileManager.default.fileExists(atPath: targetPath) else {
            throw ManagedWorktreeSnapshotError.destinationExists(targetPath)
        }
        let records = try registeredWorktrees(cwd: root)
        guard !records.contains(where: { normalizedPath($0.path) == normalizedPath(targetPath) }) else {
            throw ManagedWorktreeSnapshotError.destinationExists(targetPath)
        }
        guard isCommitHash(reference.headCommit) else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("captured commit is malformed")
        }
        let commitCheck = runner.runGit(
            ["cat-file", "-e", "\(reference.headCommit)^{commit}"],
            cwd: root,
            timeoutSeconds: 15
        )
        guard commitCheck.ok else {
            throw gitError("validating the captured commit", result: commitCheck)
        }

        let create = runner.runGit(
            ["worktree", "add", "--detach", targetPath, reference.headCommit],
            cwd: root,
            timeoutSeconds: 45
        )
        guard create.ok else {
            throw gitError("restoring the managed worktree", result: create)
        }

        do {
            let transfer = try transferSnapshot(from: manifest, snapshotRoot: snapshotRoot)
            let restoredFileCount = try ManagedWorktreeSnapshotApplier(runner: runner).apply(
                transfer,
                to: URL(fileURLWithPath: targetPath)
            )
            return ManagedWorktreeSnapshotRestoreResult(
                path: targetPath,
                restoredFileCount: restoredFileCount
            )
        } catch {
            _ = runner.runGit(
                ["worktree", "remove", "--force", "--", targetPath],
                cwd: root,
                timeoutSeconds: 30
            )
            throw error
        }
    }

    public func delete(_ reference: WorktreeSnapshotReference) throws {
        let snapshotRoot = snapshotDirectory(reference.id)
        guard FileManager.default.fileExists(atPath: snapshotRoot.path) else { return }
        do {
            try FileManager.default.removeItem(at: snapshotRoot)
        } catch {
            throw ManagedWorktreeSnapshotError.filesystemFailed(error.localizedDescription)
        }
    }

    private func validate(
        manifest: Manifest,
        threadID: UUID,
        reference: WorktreeSnapshotReference,
        binding: WorktreeBinding
    ) throws {
        guard manifest.version == Self.manifestVersion else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("unsupported manifest version")
        }
        guard manifest.reference == reference else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("thread metadata does not match the manifest")
        }
        guard manifest.threadID == threadID else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("snapshot belongs to a different task")
        }
        guard manifest.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              binding.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManagedWorktreeSnapshotError.invalidBinding("named branches are permanent")
        }
        guard normalizedPath(manifest.originalPath) == normalizedPath(binding.path) else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("original worktree path changed")
        }
    }

    private func transferSnapshot(
        from manifest: Manifest,
        snapshotRoot: URL
    ) throws -> ManagedWorktreeTransferSnapshot {
        let stagedPatchURL = snapshotRoot.appendingPathComponent("staged.patch")
        let unstagedPatchURL = snapshotRoot.appendingPathComponent("unstaged.patch")
        try validateRegularFile(stagedPatchURL, inside: snapshotRoot)
        try validateRegularFile(unstagedPatchURL, inside: snapshotRoot)
        let filesRoot = snapshotRoot.appendingPathComponent("files")
        let files = try manifest.filePaths.map { relativePath -> ManagedWorktreeTransferFile in
            guard let fileURL = WorkspaceBoundary.safeURL(relativePath, root: filesRoot) else {
                throw ManagedWorktreeSnapshotError.snapshotCorrupt("unsafe file path: \(relativePath)")
            }
            try validateRegularFile(fileURL, inside: filesRoot)
            return ManagedWorktreeTransferFile(relativePath: relativePath, snapshotURL: fileURL)
        }
        let transfer = ManagedWorktreeTransferSnapshot(
            stagedPatchURL: stagedPatchURL,
            unstagedPatchURL: unstagedPatchURL,
            files: files,
            skippedSymlinkCount: manifest.skippedSymlinkCount
        )
        guard files.count == manifest.reference.fileCount,
              try payloadByteCount(transfer) == manifest.reference.byteCount else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("snapshot payload size changed")
        }
        return transfer
    }

    private func validateRegularFile(_ url: URL, inside root: URL) throws {
        guard WorkspaceBoundary.isWithin(url, root: root) else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("payload escaped its snapshot directory")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("payload is missing or not a regular file")
        }
    }

    private func registeredWorktrees(cwd: URL) throws -> [GitWorktreeRecord] {
        let result = runner.runGit(["worktree", "list", "--porcelain"], cwd: cwd, timeoutSeconds: 20)
        guard result.ok else {
            throw gitError("listing worktrees", result: result)
        }
        return GitWorktreePorcelainParser.parse(result.stdout)
    }

    private func repositoryCommonDirectory(cwd: URL) throws -> String {
        normalizedPath(try requiredGitOutput(
            ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            cwd: cwd,
            operation: "identifying the repository"
        ))
    }

    private func requiredGitOutput(
        _ arguments: [String],
        cwd: URL,
        operation: String
    ) throws -> String {
        let result = runner.runGit(arguments, cwd: cwd, timeoutSeconds: 15)
        guard result.ok else { throw gitError(operation, result: result) }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw ManagedWorktreeSnapshotError.gitFailed(operation, "git returned no value")
        }
        return value
    }

    private func gitError(_ operation: String, result: ToolResult) -> ManagedWorktreeSnapshotError {
        .gitFailed(operation, result.error ?? result.stderr.nonEmpty ?? "unknown git error")
    }

    private func payloadByteCount(_ snapshot: ManagedWorktreeTransferSnapshot) throws -> Int64 {
        try ([snapshot.stagedPatchURL, snapshot.unstagedPatchURL] + snapshot.files.map(\.snapshotURL))
            .reduce(Int64(0)) { total, url in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                return total + Int64(size)
            }
    }

    private func writeManifest(_ manifest: Manifest, to snapshotRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: snapshotRoot.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func readManifest(from snapshotRoot: URL) throws -> Manifest {
        let url = snapshotRoot.appendingPathComponent("manifest.json")
        do {
            try validateRegularFile(url, inside: snapshotRoot)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Manifest.self, from: Data(contentsOf: url))
        } catch let error as ManagedWorktreeSnapshotError {
            throw error
        } catch {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt(error.localizedDescription)
        }
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try setPrivatePermissions(url)
    }

    private func setPrivatePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func snapshotDirectory(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString.lowercased())
    }

    private func normalizedPath(_ path: String) -> String {
        normalizedPath(URL(fileURLWithPath: path))
    }

    private func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func isCommitHash(_ value: String) -> Bool {
        (7...64).contains(value.count) && value.allSatisfy(\.isHexDigit)
    }

    private struct Manifest: Codable, Sendable, Hashable {
        var version: Int
        var threadID: UUID
        var reference: WorktreeSnapshotReference
        var originalPath: String
        var repositoryCommonDirectory: String
        var branch: String
        var base: String?
        var filePaths: [String]
        var skippedSymlinkCount: Int
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
