import Foundation

struct AgentFileListRequest: Equatable, Sendable {
    var path: String
    var includeHidden: Bool

    var arguments: [String: Any] {
        var output: [String: Any] = ["path": path]
        if includeHidden {
            output["includeHidden"] = true
        }
        return output
    }
}

enum AgentFileListRequestParser {
    static func request(from text: String) -> AgentFileListRequest? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard isFileListingRequest(lower) else { return nil }

        return AgentFileListRequest(
            path: extractedPath(from: trimmed) ?? ".",
            includeHidden: shouldIncludeHidden(lower)
        )
    }

    private static func isFileListingRequest(_ lower: String) -> Bool {
        let tokens = tokenizeWords(lower)
        if lower.contains("list files")
            || lower.contains("list the files")
            || lower.contains("list all files")
            || lower.contains("show files")
            || lower.contains("show the files")
            || lower.contains("list directory")
            || lower.contains("show directory")
            || lower.contains("list folder")
            || lower.contains("show folder") {
            return true
        }

        let asksForEntries = tokens.contains("files")
            || tokens.contains("folder")
            || tokens.contains("folders")
            || tokens.contains("directory")
            || tokens.contains("directories")
        let asksForListing = tokens.contains("list")
            || tokens.contains("show")
            || tokens.contains("what")
            || tokens.contains("what's")
        let scopesWorkspace = tokens.contains("here")
            || tokens.contains("workspace")
            || tokens.contains("project")
            || tokens.contains("repo")
            || tokens.contains("directory")
            || tokens.contains("folder")
            || tokens.contains("in")
            || tokens.contains("under")
            || tokens.contains("inside")
            || tokens.contains("within")
            || tokens.contains("from")

        return asksForEntries && asksForListing && scopesWorkspace
    }

    private static func extractedPath(from request: String) -> String? {
        if let quoted = backtickQuotedValues(in: request).compactMap(safeRelativeWorkspacePath).first {
            return quoted
        }

        let lower = request.lowercased()
        for marker in [" inside ", " within ", " under ", " from ", " in "] {
            guard let range = lower.range(of: marker) else { continue }
            let raw = String(request[range.upperBound...])
            if let path = candidatePath(from: raw) {
                return path
            }
        }
        return nil
    }

    private static func candidatePath(from raw: String) -> String? {
        let candidate = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'“”‘’.,;:!?"))
        let firstToken = candidate
            .split(separator: " ", maxSplits: 1)
            .first
            .map(String.init) ?? candidate
        return safeRelativeWorkspacePath(firstToken)
    }

    private static func safeRelativeWorkspacePath(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'“”‘’.,;:!?"))
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty,
              !["here", "workspace", "project", "repo", "directory", "folder", "files"].contains(lower),
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !lower.hasPrefix("http://"),
              !lower.hasPrefix("https://"),
              !lower.hasPrefix("file://"),
              !trimmed.split(separator: "/").contains(".."),
              trimmed.range(of: #"^[A-Za-z0-9_./@+-]+$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return trimmed
    }

    private static func shouldIncludeHidden(_ lower: String) -> Bool {
        lower.contains("hidden")
            || lower.contains("dotfiles")
            || lower.contains("dot files")
            || lower.contains("all files")
            || lower.contains("including hidden")
    }

    private static func tokenizeWords(_ lower: String) -> Set<String> {
        Set(lower.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init))
    }

    private static func backtickQuotedValues(in request: String) -> [String] {
        var values: [String] = []
        var cursor = request.startIndex
        while let first = request[cursor...].firstIndex(of: "`"),
              let last = request[request.index(after: first)...].firstIndex(of: "`") {
            let value = String(request[request.index(after: first)..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                values.append(value)
            }
            cursor = request.index(after: last)
        }
        return values
    }
}
