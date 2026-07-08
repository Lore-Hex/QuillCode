import Foundation
import QuillCodeCore

public struct WorkspaceMonitorRequest: Codable, Sendable, Hashable {
    public var kind: QuillAutomationEventSourceKind
    public var path: String

    public init(kind: QuillAutomationEventSourceKind, path: String) {
        self.kind = kind
        self.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SlashMonitorCommandParser {
    static let usage = "Usage: /monitor file path, /monitor directory path, /monitor last-modified https://example.com, or /monitor feed https://example.com/feed.xml"

    static func parse(_ argument: String) -> SlashCommand {
        let parts = argument
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let rawKind = parts.first?.lowercased(), parts.count == 2 else {
            return .invalid(usage)
        }
        let path = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return .invalid(usage)
        }
        switch rawKind {
        case "file", "path":
            return .monitor(WorkspaceMonitorRequest(kind: .fileChange, path: path))
        case "directory", "dir", "folder":
            return .monitor(WorkspaceMonitorRequest(kind: .directoryChange, path: path))
        case "last-modified", "lastmodified", "header", "url":
            return .monitor(WorkspaceMonitorRequest(kind: .urlLastModified, path: path))
        case "feed", "rss", "atom":
            return .monitor(WorkspaceMonitorRequest(kind: .urlFeedUpdate, path: path))
        default:
            return .invalid(usage)
        }
    }
}
