import Foundation
import QuillCodeCore

public enum FileToolError: Error, CustomStringConvertible {
    case outsideWorkspace(String)
    case invalidUTF8(String)
    case emptySearchQuery
    case pathNotFound(String)
    case notDirectory(String)

    public var description: String {
        switch self {
        case .outsideWorkspace(let path):
            return "Path is outside the workspace: \(path)"
        case .invalidUTF8(let path):
            return "File is not valid UTF-8 text: \(path)"
        case .emptySearchQuery:
            return "File search query must not be empty."
        case .pathNotFound(let path):
            return "Path does not exist in the workspace: \(path)"
        case .notDirectory(let path):
            return "Path is not a directory in the workspace: \(path)"
        }
    }
}

public struct FileListToolOutput: Codable, Sendable, Hashable {
    public var path: String
    public var entries: [FileListEntry]
    public var totalEntries: Int
    public var includedHidden: Bool
    public var truncated: Bool

    public init(
        path: String,
        entries: [FileListEntry],
        totalEntries: Int,
        includedHidden: Bool,
        truncated: Bool
    ) {
        self.path = path
        self.entries = entries
        self.totalEntries = totalEntries
        self.includedHidden = includedHidden
        self.truncated = truncated
    }
}

public struct FileListEntry: Codable, Sendable, Hashable {
    public var name: String
    public var path: String
    public var kind: String
    public var bytes: Int?
    public var isHidden: Bool

    public init(name: String, path: String, kind: String, bytes: Int?, isHidden: Bool) {
        self.name = name
        self.path = path
        self.kind = kind
        self.bytes = bytes
        self.isHidden = isHidden
    }
}

public struct FileSearchToolOutput: Codable, Sendable, Hashable {
    public var query: String
    public var path: String
    public var matches: [FileSearchMatch]
    public var scannedFiles: Int
    public var skippedFiles: Int
    public var truncated: Bool

    public init(
        query: String,
        path: String,
        matches: [FileSearchMatch],
        scannedFiles: Int,
        skippedFiles: Int,
        truncated: Bool
    ) {
        self.query = query
        self.path = path
        self.matches = matches
        self.scannedFiles = scannedFiles
        self.skippedFiles = skippedFiles
        self.truncated = truncated
    }
}

public struct FileSearchMatch: Codable, Sendable, Hashable {
    public var path: String
    public var line: Int
    public var preview: String

    public init(path: String, line: Int, preview: String) {
        self.path = path
        self.line = line
        self.preview = preview
    }
}

private struct FileSearchScan: Sendable, Hashable {
    var scannedFiles = 0
    var skippedFiles = 0
    var truncated = false
}

public struct FileToolExecutor: Sendable {
    public var workspaceRoot: URL

    private static let defaultSearchMaxResults = 20
    private static let absoluteSearchMaxResults = 100
    private static let defaultListMaxEntries = 200
    private static let absoluteListMaxEntries = 500
    private static let maxSearchFileBytes = 1_000_000
    private static let maxSearchScannedFiles = 2_000
    private static let maxSearchPreviewCharacters = 240
    private static let excludedSearchDirectoryNames: Set<String> = [
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

    public func read(path: String) -> ToolResult {
        do {
            let url = try resolve(path)
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileToolError.invalidUTF8(path)
            }
            return ToolResult(ok: true, stdout: text, artifacts: [url.path])
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func write(path: String, content: String) -> ToolResult {
        do {
            let url = try resolve(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return ToolResult(ok: true, stdout: "Wrote \(url.path)\n", artifacts: [url.path])
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func list(path: String = ".", includeHidden: Bool = false, maxEntries: Int? = nil) -> ToolResult {
        do {
            let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            let directoryURL = try resolve(normalizedPath.isEmpty ? "." : normalizedPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
                throw FileToolError.pathNotFound(path)
            }
            guard isDirectory.boolValue else {
                throw FileToolError.notDirectory(path)
            }

            let allEntries = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            )
            let visibleEntries = allEntries
                .filter { includeHidden || !$0.lastPathComponent.hasPrefix(".") }
                .sorted(by: listEntrySort)
            let limit = boundedListEntryLimit(maxEntries)
            let entries = visibleEntries.prefix(limit).map(fileListEntry)
            let output = FileListToolOutput(
                path: relativePath(for: directoryURL),
                entries: entries,
                totalEntries: visibleEntries.count,
                includedHidden: includeHidden,
                truncated: visibleEntries.count > entries.count
            )
            return ToolResult(
                ok: true,
                stdout: encode(output),
                artifacts: entries.map { workspaceRoot.appendingPathComponent($0.path).path }
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func search(query: String, path: String = ".", maxResults: Int? = nil) -> ToolResult {
        do {
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedQuery.isEmpty else {
                throw FileToolError.emptySearchQuery
            }

            let searchRoot = try resolve(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "." : path)
            guard FileManager.default.fileExists(atPath: searchRoot.path) else {
                throw FileToolError.pathNotFound(path)
            }
            let limit = boundedSearchResultLimit(maxResults)
            var matches: [FileSearchMatch] = []
            let scan = scanSearchableFiles(
                startingAt: searchRoot,
                query: normalizedQuery,
                limit: limit,
                matches: &matches
            )

            let output = FileSearchToolOutput(
                query: normalizedQuery,
                path: relativePath(for: searchRoot),
                matches: matches,
                scannedFiles: scan.scannedFiles,
                skippedFiles: scan.skippedFiles,
                truncated: scan.truncated
            )
            return ToolResult(
                ok: true,
                stdout: encode(output),
                artifacts: Array(Set(matches.map { workspaceRoot.appendingPathComponent($0.path).path })).sorted()
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
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
            path: relativePath(for: url),
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

    public func resolve(_ path: String) throws -> URL {
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path)
        } else {
            candidate = workspaceRoot.appendingPathComponent(path)
        }
        let standardized = candidate.standardizedFileURL
        let rootPath = workspaceRoot.path.hasSuffix("/") ? workspaceRoot.path : "\(workspaceRoot.path)/"
        guard standardized.path == workspaceRoot.path || standardized.path.hasPrefix(rootPath) else {
            throw FileToolError.outsideWorkspace(path)
        }
        return standardized
    }

    private func scanSearchableFiles(
        startingAt url: URL,
        query: String,
        limit: Int,
        matches: inout [FileSearchMatch]
    ) -> FileSearchScan {
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        var scan = FileSearchScan()
        guard isDirectory.boolValue else {
            _ = scanFile(url, query: query, limit: limit, matches: &matches, scan: &scan)
            return scan
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return scan
        }

        for case let candidate as URL in enumerator {
            if shouldSkipSearchDescendant(candidate) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory != true else { continue }
            guard scanFile(candidate, query: query, limit: limit, matches: &matches, scan: &scan) else {
                break
            }
        }
        return scan
    }

    private func scanFile(
        _ fileURL: URL,
        query: String,
        limit: Int,
        matches: inout [FileSearchMatch],
        scan: inout FileSearchScan
    ) -> Bool {
        if scan.scannedFiles >= Self.maxSearchScannedFiles || matches.count >= limit {
            scan.truncated = true
            return false
        }

        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else {
            scan.skippedFiles += 1
            return true
        }
        if (values?.fileSize ?? 0) > Self.maxSearchFileBytes {
            scan.skippedFiles += 1
            return true
        }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            scan.skippedFiles += 1
            return true
        }

        scan.scannedFiles += 1
        appendMatches(in: text, fileURL: fileURL, query: query, limit: limit, matches: &matches)
        if matches.count >= limit {
            scan.truncated = true
            return false
        }
        return true
    }

    private func shouldSkipSearchDescendant(_ url: URL) -> Bool {
        guard Self.excludedSearchDirectoryNames.contains(url.lastPathComponent) else {
            return false
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func appendMatches(
        in text: String,
        fileURL: URL,
        query: String,
        limit: Int,
        matches: inout [FileSearchMatch]
    ) {
        let lowerQuery = query.lowercased()
        for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
            guard matches.count < limit else { return }
            guard line.lowercased().contains(lowerQuery) else { continue }
            matches.append(FileSearchMatch(
                path: relativePath(for: fileURL),
                line: offset + 1,
                preview: boundedSearchPreview(line)
            ))
        }
    }

    private func boundedSearchResultLimit(_ value: Int?) -> Int {
        min(max(value ?? Self.defaultSearchMaxResults, 1), Self.absoluteSearchMaxResults)
    }

    private func boundedListEntryLimit(_ value: Int?) -> Int {
        min(max(value ?? Self.defaultListMaxEntries, 1), Self.absoluteListMaxEntries)
    }

    private func boundedSearchPreview(_ line: String) -> String {
        let collapsed = line
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > Self.maxSearchPreviewCharacters else {
            return collapsed
        }
        return "\(collapsed.prefix(Self.maxSearchPreviewCharacters))..."
    }

    private func relativePath(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        let rootPath = workspaceRoot.path.hasSuffix("/") ? workspaceRoot.path : "\(workspaceRoot.path)/"
        guard standardized.path.hasPrefix(rootPath) else {
            return "."
        }
        let relative = String(standardized.path.dropFirst(rootPath.count))
        return relative.isEmpty ? "." : relative
    }

    private func encode<T: Encodable>(_ output: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

public extension ToolDefinition {
    static let fileRead = ToolDefinition(
        name: "host.file.read",
        description: "Read a UTF-8 file inside the project workspace.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .read
    )

    static let fileList = ToolDefinition(
        name: "host.file.list",
        description: "List immediate files and directories inside a workspace directory. Returns bounded structured entries with name, path, kind, size, and hidden-file metadata.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string","description":"Optional workspace-relative directory to list. Defaults to the workspace root."},"includeHidden":{"type":"boolean","description":"Whether to include dotfiles and other hidden entries. Defaults to false."},"maxEntries":{"type":"integer","minimum":1,"maximum":500,"description":"Maximum number of directory entries to return. Defaults to 200."}}}"#,
        host: .local,
        risk: .read
    )

    static let fileSearch = ToolDefinition(
        name: "host.file.search",
        description: "Search UTF-8 text files inside the project workspace for a literal query. Returns bounded file, line, and preview matches; skips heavy dependency/build directories and large or binary files.",
        parametersJSON: #"{"type":"object","properties":{"query":{"type":"string","description":"Literal text to search for."},"path":{"type":"string","description":"Optional workspace-relative file or directory to search. Defaults to the workspace root."},"maxResults":{"type":"integer","minimum":1,"maximum":100,"description":"Maximum number of matches to return. Defaults to 20."}},"required":["query"]}"#,
        host: .local,
        risk: .read
    )

    static let fileWrite = ToolDefinition(
        name: "host.file.write",
        description: "Write a UTF-8 file inside the project workspace.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}"#,
        host: .local,
        risk: .append
    )
}
