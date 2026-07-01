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
            artifacts: entries.map { pathResolver.workspaceRoot.appendingPathComponent($0.path).path }
        )
    }

    private func directoryEntries(at directoryURL: URL, includeHidden: Bool) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: []
        )
        .filter { includeHidden || !$0.lastPathComponent.hasPrefix(".") }
        .sorted(by: listEntrySort)
    }

    private func listEntrySort(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsKind = fileListEntryKind(lhs)
        let rhsKind = fileListEntryKind(rhs)
        if lhsKind != rhsKind {
            return lhsKind == "directory"
        }
        return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
    }

    private func fileListEntry(_ url: URL) -> FileListEntry {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        let kind = fileListEntryKind(url, values: values)
        return FileListEntry(
            name: url.lastPathComponent,
            path: pathResolver.relativePath(for: url),
            kind: kind,
            bytes: kind == "file" ? values?.fileSize : nil,
            isHidden: url.lastPathComponent.hasPrefix(".")
        )
    }

    private func fileListEntryKind(_ url: URL, values: URLResourceValues? = nil) -> String {
        let values = values ?? (try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]))
        if values?.isSymbolicLink == true {
            return "symlink"
        }
        if values?.isDirectory == true {
            return "directory"
        }
        if values?.isRegularFile == true {
            return "file"
        }
        return "other"
    }
}
