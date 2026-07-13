import Foundation
import QuillCodeCore

/// Persists the exact staged, unstaged, and safe local-file state of a disposable managed worktree.
/// Snapshots are repository-bound and restored at the captured commit, so archive cleanup cannot
/// silently move a task onto newer code or into a different checkout.
public struct ManagedWorktreeSnapshotStore: Sendable {
    private static let manifestVersion = 2

    let directory: URL
    let runner: GitProcessRunner
    let limits: ManagedWorktreeTransferLimits

    public init(directory: URL, runner: GitProcessRunner = GitProcessRunner()) {
        self.directory = directory
        self.runner = runner
        self.limits = ManagedWorktreeTransferLimits()
    }

    public func capture(
        threadID: UUID,
        binding: WorktreeBinding,
        managedRoot: URL? = nil
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
        let mainRoot = URL(fileURLWithPath: records[records.startIndex].path).standardizedFileURL
        let authorizedRoot = try authorizedManagedRoot(
            binding: binding,
            configuredRoot: managedRoot,
            sourceRoot: sourceRoot,
            mainRoot: mainRoot
        )

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
                managedRoot: normalizedPath(authorizedRoot),
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
            let authorizedRoot = manifest.managedRoot.map(URL.init(fileURLWithPath:))
                ?? root.deletingLastPathComponent()
            targetPath = try GitWorktreeToolExecutor.safeManagedPath(
                binding.path,
                cwd: root,
                managedRoot: authorizedRoot
            )
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
        let transfer = try transferSnapshot(from: manifest, snapshotRoot: snapshotRoot)
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
            let restoredFileCount = try ManagedWorktreeSnapshotApplier(runner: runner).apply(
                transfer,
                to: URL(fileURLWithPath: targetPath)
            )
            try verify(
                transfer,
                matches: URL(fileURLWithPath: targetPath),
                mismatchError: .snapshotCorrupt("restored state did not match the saved payload")
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

    func validate(
        manifest: Manifest,
        threadID: UUID,
        reference: WorktreeSnapshotReference,
        binding: WorktreeBinding
    ) throws {
        guard (1...Self.manifestVersion).contains(manifest.version) else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("unsupported manifest version")
        }
        guard manifest.reference == reference else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("thread metadata does not match the manifest")
        }
        guard isCommitHash(reference.headCommit),
              Set(manifest.filePaths).count == manifest.filePaths.count else {
            throw ManagedWorktreeSnapshotError.snapshotCorrupt("manifest contains invalid object identifiers or paths")
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
        if let bindingRoot = binding.managedRoot, let manifestRoot = manifest.managedRoot {
            guard normalizedPath(bindingRoot) == normalizedPath(manifestRoot) else {
                throw ManagedWorktreeSnapshotError.snapshotCorrupt("managed worktree root changed")
            }
        }
    }

    func transferSnapshot(
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

    func registeredWorktrees(cwd: URL) throws -> [GitWorktreeRecord] {
        let result = runner.runGit(["worktree", "list", "--porcelain"], cwd: cwd, timeoutSeconds: 20)
        guard result.ok else {
            throw gitError("listing worktrees", result: result)
        }
        return GitWorktreePorcelainParser.parse(result.stdout)
    }

    private func authorizedManagedRoot(
        binding: WorktreeBinding,
        configuredRoot: URL?,
        sourceRoot: URL,
        mainRoot: URL
    ) throws -> URL {
        let roots = [
            binding.managedRoot.map(URL.init(fileURLWithPath:)),
            configuredRoot,
            mainRoot.deletingLastPathComponent()
        ].compactMap { $0 }
        for root in roots {
            guard let validated = try? GitWorktreeToolExecutor.safeManagedPath(
                sourceRoot.path,
                cwd: mainRoot,
                managedRoot: root
            ) else { continue }
            if normalizedPath(validated) == normalizedPath(sourceRoot) {
                return root.standardizedFileURL
            }
        }
        throw ManagedWorktreeSnapshotError.invalidBinding("managed root does not own \(binding.path)")
    }

    func repositoryCommonDirectory(cwd: URL) throws -> String {
        normalizedPath(try requiredGitOutput(
            ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            cwd: cwd,
            operation: "identifying the repository"
        ))
    }

    func requiredGitOutput(
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

    func gitError(_ operation: String, result: ToolResult) -> ManagedWorktreeSnapshotError {
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

    func readManifest(from snapshotRoot: URL) throws -> Manifest {
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

    func verify(
        _ expected: ManagedWorktreeTransferSnapshot,
        matches worktreeRoot: URL,
        mismatchError: ManagedWorktreeSnapshotError
    ) throws {
        let verificationRoot = directory.appendingPathComponent(".verify-\(UUID().uuidString)")
        try ensurePrivateDirectory(verificationRoot)
        defer { try? FileManager.default.removeItem(at: verificationRoot) }
        let actual = try ManagedWorktreeTransferSnapshot.capture(
            sourceRoot: worktreeRoot,
            temporaryDirectory: verificationRoot,
            runner: runner,
            localFilePolicy: .managedCreation,
            limits: limits
        )
        guard try expected.hasSameContent(as: actual) else {
            throw mismatchError
        }
    }

    private func setPrivatePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func snapshotDirectory(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString.lowercased())
    }

    func normalizedPath(_ path: String) -> String {
        normalizedPath(URL(fileURLWithPath: path))
    }

    func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func isCommitHash(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64) && value.allSatisfy(\.isHexDigit)
    }

    struct Manifest: Codable, Sendable, Hashable {
        var version: Int
        var threadID: UUID
        var reference: WorktreeSnapshotReference
        var originalPath: String
        var repositoryCommonDirectory: String
        var managedRoot: String?
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
