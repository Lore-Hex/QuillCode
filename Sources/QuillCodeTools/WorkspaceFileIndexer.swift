import Foundation

/// A single workspace-relative file or directory discovered by ``WorkspaceFileIndexer``.
public struct WorkspaceFileIndexEntry: Codable, Sendable, Hashable, Identifiable {
    public enum EntryKind: String, Codable, Sendable, Hashable {
        case file
        case directory
    }

    public var id: String { path }
    /// Workspace-relative path using forward slashes, for example `Sources/App.swift`.
    public var path: String
    /// Last path component, for example `App.swift`.
    public var name: String
    /// Workspace-relative parent directory, or `""` for entries at the workspace root.
    public var directory: String
    /// Whether this entry is a regular file or a directory.
    public var kind: EntryKind

    public init(path: String, name: String, directory: String, kind: EntryKind = .file) {
        self.path = path
        self.name = name
        self.directory = directory
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.name = try container.decode(String.self, forKey: .name)
        self.directory = try container.decode(String.self, forKey: .directory)
        // Older snapshots predate `kind`; default a missing value to a file.
        self.kind = try container.decodeIfPresent(EntryKind.self, forKey: .kind) ?? .file
    }
}

/// A bounded snapshot of the regular files inside a workspace, used to power
/// composer file mentions and other path-completion surfaces without scanning
/// heavy dependency or build directories.
public struct WorkspaceFileIndex: Codable, Sendable, Hashable {
    public var entries: [WorkspaceFileIndexEntry]
    /// Whether the scan stopped early because the file cap was reached.
    public var truncated: Bool
    /// Whether the directory cap was reached (independent of the file cap).
    public var directoriesTruncated: Bool

    public init(entries: [WorkspaceFileIndexEntry] = [], truncated: Bool = false, directoriesTruncated: Bool = false) {
        self.entries = entries
        self.truncated = truncated
        self.directoriesTruncated = directoriesTruncated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entries = try container.decode([WorkspaceFileIndexEntry].self, forKey: .entries)
        self.truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        self.directoriesTruncated = try container.decodeIfPresent(Bool.self, forKey: .directoriesTruncated) ?? false
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
    /// Directories are capped independently of files so a directory-heavy tree can never
    /// reduce the number of indexed files.
    static let defaultMaxDirectories = 1_000
    static let excludedDirectoryNames = FileToolLimits.excludedWorkspaceDirectoryNames

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
        guard !Task.isCancelled else { return WorkspaceFileIndex() }
        let limit = boundedMaxFiles(maxFiles)
        let dirLimit = Self.defaultMaxDirectories

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspaceRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return WorkspaceFileIndex()
        }

        var entries: [WorkspaceFileIndexEntry] = []
        var directories: [WorkspaceFileIndexEntry] = []
        var pendingDirectories = [workspaceRoot]
        var pendingIndex = 0
        var scannedDirectories = 0
        var truncated = false
        var directoriesTruncated = false

        while pendingIndex < pendingDirectories.count {
            guard !Task.isCancelled else { return WorkspaceFileIndex() }
            guard scannedDirectories < dirLimit else {
                directoriesTruncated = true
                break
            }
            let parent = pendingDirectories[pendingIndex]
            pendingIndex += 1
            scannedDirectories += 1
            guard let candidates = try? FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for candidate in candidates.sorted(by: { $0.path < $1.path }) {
                guard !Task.isCancelled else { return WorkspaceFileIndex() }
                let name = candidate.lastPathComponent
                if !includeHidden, name.hasPrefix(".") { continue }
                let values = try? candidate.resourceValues(
                    forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values?.isSymbolicLink != true else { continue }

                if values?.isDirectory == true {
                    guard !shouldSkipDirectory(named: name, includeHidden: includeHidden) else { continue }
                    guard directories.count < dirLimit else {
                        directoriesTruncated = true
                        continue
                    }
                    if let relative = relativePath(for: candidate) {
                        directories.append(WorkspaceFileIndexEntry(
                            path: relative,
                            name: name,
                            directory: parentDirectory(of: relative),
                            kind: .directory
                        ))
                    }
                    pendingDirectories.append(candidate)
                    continue
                }

                guard values?.isRegularFile == true,
                      let relative = relativePath(for: candidate)
                else { continue }
                entries.append(WorkspaceFileIndexEntry(
                    path: relative,
                    name: name,
                    directory: parentDirectory(of: relative)
                ))
                if entries.count >= limit {
                    truncated = true
                    directoriesTruncated = true
                    break
                }
            }
            if truncated { break }
        }

        var merged = entries
        merged.append(contentsOf: directories)
        merged.sort { $0.path < $1.path }
        return WorkspaceFileIndex(entries: merged, truncated: truncated, directoriesTruncated: directoriesTruncated)
    }

    private func shouldSkipDirectory(named name: String, includeHidden: Bool) -> Bool {
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
