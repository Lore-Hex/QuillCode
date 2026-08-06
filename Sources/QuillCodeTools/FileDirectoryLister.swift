import Foundation

struct FileDirectoryListResult: Sendable, Hashable {
    var output: FileListToolOutput
    var artifacts: [String]
}

struct FileDirectoryLister: Sendable {
    var pathResolver: FileWorkspacePathResolver

    func list(path: String, includeHidden: Bool, maxEntries: Int?) throws -> FileDirectoryListResult {
        let directoryPath = pathResolver.normalizedDirectoryPath(path)
        let directoryURL = try pathResolver.resolve(directoryPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            throw FileToolError.pathNotFound(path)
        }
        guard isDirectory.boolValue else {
            throw FileToolError.notDirectory(path)
        }

        let visibleEntries = try directoryEntries(at: directoryURL, includeHidden: includeHidden)
        let limit = FileToolLimits.boundedListEntryLimit(maxEntries)
        let entries = visibleEntries.prefix(limit).map(fileListEntry)
        let output = FileListToolOutput(
            path: pathResolver.relativePath(for: directoryURL),
            entries: entries,
            totalEntries: visibleEntries.count,
            includedHidden: includeHidden,
            truncated: visibleEntries.count > entries.count
        )
        return FileDirectoryListResult(
            output: output,
            artifacts: entries.map { pathResolver.artifactPath(for: $0.path) }
        )
    }

    private func directoryEntries(
        at directoryURL: URL,
        includeHidden: Bool
    ) throws -> [FileSystemIO.DirectoryEntry] {
        try FileSystemIO.directoryEntries(at: directoryURL)
        .filter { includeHidden || !$0.url.lastPathComponent.hasPrefix(".") }
        .sorted(by: listEntrySort)
    }

    private func listEntrySort(
        _ lhs: FileSystemIO.DirectoryEntry,
        _ rhs: FileSystemIO.DirectoryEntry
    ) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind == "directory"
        }
        return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(
            rhs.url.lastPathComponent
        ) == .orderedAscending
    }

    private func fileListEntry(_ entry: FileSystemIO.DirectoryEntry) -> FileListEntry {
        return FileListEntry(
            name: entry.url.lastPathComponent,
            path: pathResolver.relativePath(for: entry.url),
            kind: entry.kind,
            bytes: entry.bytes,
            isHidden: entry.url.lastPathComponent.hasPrefix(".")
        )
    }
}
