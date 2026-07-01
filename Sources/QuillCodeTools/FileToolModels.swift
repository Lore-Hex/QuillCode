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

struct FileSearchScan: Sendable, Hashable {
    var scannedFiles = 0
    var skippedFiles = 0
    var truncated = false
}
