import Foundation
import QuillCodeCore

/// Materializes Codex-compatible marketplace repositories without running repository code.
///
/// Git is invoked with argument arrays and interactive credential prompts disabled. Every cloned
/// tree is bounded and validated through the shared data-only marketplace reader before it can
/// replace an active marketplace root.
public struct CodexMarketplaceMaterializer: Sendable {
    public static let maximumEntries = 25_000
    public static let maximumBytes: Int64 = 500 * 1_024 * 1_024
    public static let maximumFileBytes: Int64 = 100 * 1_024 * 1_024
    public static let maximumSparsePaths = 64
    public static let maximumSparsePathBytes = 1_024
    public static let gitTimeoutSeconds: TimeInterval = 120

    public var home: URL
    public var currentDirectory: URL
    public var gitRunner: GitProcessRunner

    public init(
        home: URL,
        currentDirectory: URL,
        gitRunner: GitProcessRunner = GitProcessRunner()
    ) {
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
        self.currentDirectory = currentDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.gitRunner = gitRunner
    }

    public var installedRoot: URL {
        home
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent("marketplaces", isDirectory: true)
    }

    public func prepare(
        source rawSource: String,
        refName rawRefName: String?,
        sparsePaths rawSparsePaths: [String]
    ) throws -> CodexPreparedMarketplace {
        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !source.contains("\0"), source.utf8.count <= 4_096 else {
            throw CodexMarketplaceMaterializationError.invalidSource
        }
        let refName = try CodexMarketplaceValidator.validatedRef(rawRefName)
        let sparsePaths = try CodexMarketplaceValidator.validatedSparsePaths(rawSparsePaths)

        if let localRoot = localDirectory(source),
           refName == nil,
           sparsePaths.isEmpty {
            try CodexMarketplaceValidator.validateTree(at: localRoot)
            let marketplace = try CodexMarketplaceValidator.validatedMarketplace(at: localRoot)
            return CodexPreparedMarketplace(
                name: marketplace.name,
                root: localRoot,
                sourceType: .local,
                source: localRoot.path,
                refName: nil,
                sparsePaths: [],
                revision: nil,
                managed: false
            )
        }

        let gitSource = try CodexMarketplaceValidator.normalizedGitSource(
            source,
            currentDirectory: currentDirectory
        )
        try FileManager.default.createDirectory(at: installedRoot, withIntermediateDirectories: true)
        let staging = installedRoot.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try runGit(
                ["clone", "--no-checkout", "--filter=blob:none", "--no-tags", "--", gitSource, staging.path],
                cwd: installedRoot
            )
            if !sparsePaths.isEmpty {
                try runGit(["-C", staging.path, "sparse-checkout", "init", "--no-cone"], cwd: installedRoot)
                try runGit(
                    ["-C", staging.path, "sparse-checkout", "set", "--no-cone", "--"] + sparsePaths,
                    cwd: installedRoot
                )
            }
            try runGit(
                ["-C", staging.path, "checkout", "--detach", refName ?? "HEAD"],
                cwd: installedRoot
            )
            let revision = try gitOutput(["-C", staging.path, "rev-parse", "HEAD"], cwd: installedRoot)
            try CodexMarketplaceValidator.validateTree(at: staging)
            let marketplace = try CodexMarketplaceValidator.validatedMarketplace(at: staging)
            return CodexPreparedMarketplace(
                name: marketplace.name,
                root: staging,
                sourceType: .git,
                source: gitSource,
                refName: refName,
                sparsePaths: sparsePaths,
                revision: revision,
                managed: true
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func activate(
        _ prepared: CodexPreparedMarketplace,
        replacingExisting: Bool
    ) throws -> CodexMarketplaceActivation {
        guard prepared.managed else {
            return CodexMarketplaceActivation(
                name: prepared.name,
                installedRoot: prepared.root,
                backupRoot: nil,
                managed: false
            )
        }
        let destination = try destination(for: prepared.name)
        var backup: URL?
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                guard replacingExisting else {
                    throw CodexMarketplaceMaterializationError.destinationExists(prepared.name)
                }
                let candidate = installedRoot.appendingPathComponent(
                    ".backup-\(prepared.name)-\(UUID().uuidString)",
                    isDirectory: true
                )
                try FileManager.default.moveItem(at: destination, to: candidate)
                backup = candidate
            }
            try FileManager.default.moveItem(at: prepared.root, to: destination)
            return CodexMarketplaceActivation(
                name: prepared.name,
                installedRoot: destination,
                backupRoot: backup,
                managed: true
            )
        } catch {
            if !FileManager.default.fileExists(atPath: destination.path), let backup {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    public func finalize(_ activation: CodexMarketplaceActivation) throws {
        if let backup = activation.backupRoot,
           FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.removeItem(at: backup)
        }
    }

    public func rollback(_ activation: CodexMarketplaceActivation) throws {
        guard activation.managed else { return }
        guard let backup = activation.backupRoot,
              FileManager.default.fileExists(atPath: backup.path)
        else {
            if FileManager.default.fileExists(atPath: activation.installedRoot.path) {
                try FileManager.default.removeItem(at: activation.installedRoot)
            }
            return
        }
        let failed = installedRoot.appendingPathComponent(
            ".rollback-\(activation.name)-\(UUID().uuidString)",
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: activation.installedRoot.path) {
            try FileManager.default.moveItem(at: activation.installedRoot, to: failed)
        }
        do {
            try FileManager.default.moveItem(at: backup, to: activation.installedRoot)
            try? FileManager.default.removeItem(at: failed)
        } catch {
            if FileManager.default.fileExists(atPath: failed.path),
               !FileManager.default.fileExists(atPath: activation.installedRoot.path) {
                try? FileManager.default.moveItem(at: failed, to: activation.installedRoot)
            }
            throw error
        }
    }

    public func discard(_ prepared: CodexPreparedMarketplace) {
        guard prepared.managed,
              WorkspaceBoundary.isWithin(prepared.root, root: installedRoot),
              prepared.root.lastPathComponent.hasPrefix(".staging-")
        else { return }
        try? FileManager.default.removeItem(at: prepared.root)
    }

    public func stageRemoval(named name: String) throws -> CodexMarketplaceRemoval? {
        let destination = try destination(for: name)
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        let staged = installedRoot.appendingPathComponent(
            ".removed-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.moveItem(at: destination, to: staged)
            return CodexMarketplaceRemoval(installedRoot: destination, stagedRoot: staged)
        } catch {
            throw CodexMarketplaceMaterializationError.filesystem(
                "failed to stage marketplace removal: \(error.localizedDescription)"
            )
        }
    }

    public func finalize(_ removal: CodexMarketplaceRemoval) throws {
        guard FileManager.default.fileExists(atPath: removal.stagedRoot.path) else { return }
        try FileManager.default.removeItem(at: removal.stagedRoot)
    }

    public func rollback(_ removal: CodexMarketplaceRemoval) throws {
        guard FileManager.default.fileExists(atPath: removal.stagedRoot.path) else { return }
        guard !FileManager.default.fileExists(atPath: removal.installedRoot.path) else {
            throw CodexMarketplaceMaterializationError.filesystem(
                "cannot restore removed marketplace because its destination is occupied"
            )
        }
        try FileManager.default.moveItem(at: removal.stagedRoot, to: removal.installedRoot)
    }

    public static func managedMarketplaceRoots(in home: URL) -> [URL] {
        let root = home.standardizedFileURL
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent("marketplaces", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(64).compactMap {
            let candidate = root.appendingPathComponent($0.lastPathComponent, isDirectory: true)
            let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true,
                  values?.isSymbolicLink != true,
                  candidate.resolvingSymlinksInPath().path == candidate.path,
                  WorkspaceBoundary.isWithin(candidate, root: root)
            else { return nil }
            return candidate
        }
    }

    /// Resolves and validates one managed marketplace that is already active on disk.
    ///
    /// Idempotent add requests use this instead of trusting directory existence. A damaged or
    /// replaced checkout must fail closed rather than being reported as a healthy installation.
    public func validateInstalledMarketplace(named name: String) throws -> URL {
        let root = try destination(for: name)
        let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true,
              root.resolvingSymlinksInPath().path == root.path
        else {
            throw CodexMarketplaceMaterializationError.invalidMarketplace(
                "installed marketplace `\(name)` is missing or is not a regular directory"
            )
        }
        try CodexMarketplaceValidator.validateTree(at: root)
        let marketplace = try CodexMarketplaceValidator.validatedMarketplace(at: root)
        guard marketplace.name == name else {
            throw CodexMarketplaceMaterializationError.invalidMarketplace(
                "installed catalog name changed from `\(name)` to `\(marketplace.name)`"
            )
        }
        return root
    }

    private func destination(for name: String) throws -> URL {
        let normalized = try BoundedPluginPackageInstaller.normalizedIdentifier(name)
        let destination = installedRoot.appendingPathComponent(normalized, isDirectory: true)
        guard destination.deletingLastPathComponent().path == installedRoot.path else {
            throw CodexMarketplaceMaterializationError.invalidMarketplace("invalid destination")
        }
        return destination
    }

    private func localDirectory(_ source: String) -> URL? {
        let candidate = NSString(string: source).isAbsolutePath
            ? URL(fileURLWithPath: source, isDirectory: true)
            : currentDirectory.appendingPathComponent(source, isDirectory: true)
        let root = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
        return root
    }

    private func runGit(_ arguments: [String], cwd: URL) throws {
        let result = gitRunner.runGit(
            arguments,
            cwd: cwd,
            timeoutSeconds: Self.gitTimeoutSeconds,
            environment: Self.gitEnvironment
        )
        guard result.ok else {
            throw CodexMarketplaceMaterializationError.gitFailed(Self.gitFailure(result))
        }
    }

    private func gitOutput(_ arguments: [String], cwd: URL) throws -> String {
        let result = gitRunner.runGit(
            arguments,
            cwd: cwd,
            timeoutSeconds: Self.gitTimeoutSeconds,
            environment: Self.gitEnvironment
        )
        guard result.ok else {
            throw CodexMarketplaceMaterializationError.gitFailed(Self.gitFailure(result))
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, output.utf8.count <= 256 else {
            throw CodexMarketplaceMaterializationError.gitFailed("Git returned an invalid revision.")
        }
        return output
    }

    private static let gitEnvironment = [
        "GIT_TERMINAL_PROMPT": "0",
        "GCM_INTERACTIVE": "Never",
        "GIT_LFS_SKIP_SMUDGE": "1"
    ]

    private static func gitFailure(_ result: ToolResult) -> String {
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let bounded = String(detail.prefix(2_000))
        return bounded.isEmpty ? (result.error ?? "Git command failed.") : "Git command failed: \(bounded)"
    }

}
