import Foundation

/// A single workspace-relative file discovered by ``WorkspaceFileIndexer``.
public struct WorkspaceFileIndexEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    /// Workspace-relative path using forward slashes, for example `Sources/App.swift`.
    public var path: String
    /// Last path component, for example `App.swift`.
    public var name: String
    /// Workspace-relative parent directory, or `""` for files at the workspace root.
    public var directory: String

    public init(path: String, name: String, directory: String) {
        self.path = path
        self.name = name
        self.directory = directory
    }
}

/// A bounded snapshot of the regular files inside a workspace, used to power
/// composer file mentions and other path-completion surfaces without scanning
/// heavy dependency or build directories.
public struct WorkspaceFileIndex: Codable, Sendable, Hashable {
    public var entries: [WorkspaceFileIndexEntry]
    /// Whether the scan stopped early because the file cap was reached.
    public var truncated: Bool

    public init(entries: [WorkspaceFileIndexEntry] = [], truncated: Bool = false) {
        self.entries = entries
        self.truncated = truncated
    }

    public var isEmpty: Bool { entries.isEmpty }
}

/// Enumerates the regular files inside a workspace root in a bounded, deterministic
/// way. It skips the same heavy dependency/build directories as ``FileToolExecutor``
/// search, skips hidden entries by default, and caps the number of returned files so
/// large repositories cannot stall path-completion surfaces.
public struct WorkspaceFileIndexer: Sendable {
    public var workspaceRoot: URL

    static let defaultMaxFiles = 4_000
    static let absoluteMaxFiles = 20_000
    static let excludedDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "build",
        "node_modules"
    ]

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
    }

    /// Returns a bounded, path-sorted index of the workspace's regular files.
    ///
    /// - Parameters:
    ///   - includeHidden: When `false` (the default) dotfiles and files nested
    ///     inside dot-directories are skipped.
    ///   - maxFiles: Optional override for the file cap. Bounded to a safe range.
    public func index(includeHidden: Bool = false, maxFiles: Int? = nil) -> WorkspaceFileIndex {
        let limit = boundedMaxFiles(maxFiles)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspaceRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return WorkspaceFileIndex()
        }

        guard let enumerator = FileManager.default.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return WorkspaceFileIndex()
        }

        var entries: [WorkspaceFileIndexEntry] = []
        var truncated = false

        for case let candidate as URL in enumerator {
            let name = candidate.lastPathComponent

            if shouldSkipDirectory(candidate, name: name, includeHidden: includeHidden) {
                enumerator.skipDescendants()
                continue
            }

            if !includeHidden, name.hasPrefix(".") {
                continue
            }

            let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            guard values?.isDirectory != true else { continue }
            guard values?.isRegularFile == true else { continue }

            guard let relative = relativePath(for: candidate) else { continue }
            entries.append(WorkspaceFileIndexEntry(
                path: relative,
                name: name,
                directory: parentDirectory(of: relative)
            ))

            if entries.count >= limit {
                truncated = true
                break
            }
        }

        entries.sort { $0.path < $1.path }
        return WorkspaceFileIndex(entries: entries, truncated: truncated)
    }

    private func shouldSkipDirectory(_ url: URL, name: String, includeHidden: Bool) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { return false }
        if Self.excludedDirectoryNames.contains(name) { return true }
        if !includeHidden, name.hasPrefix(".") { return true }
        return false
    }

    private func boundedMaxFiles(_ value: Int?) -> Int {
        min(max(value ?? Self.defaultMaxFiles, 1), Self.absoluteMaxFiles)
    }

    private func relativePath(for url: URL) -> String? {
        let standardized = url.standardizedFileURL
        let rootPath = workspaceRoot.path.hasSuffix("/") ? workspaceRoot.path : "\(workspaceRoot.path)/"
        guard standardized.path.hasPrefix(rootPath) else { return nil }
        let relative = String(standardized.path.dropFirst(rootPath.count))
        return relative.isEmpty ? nil : relative
    }

    private func parentDirectory(of relativePath: String) -> String {
        guard let slashIndex = relativePath.lastIndex(of: "/") else { return "" }
        return String(relativePath[relativePath.startIndex..<slashIndex])
    }
}
