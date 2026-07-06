import Foundation

enum AgentFileReadRequestParser {
    static func path(from request: String) -> String? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard isReadRequest(lower) else { return nil }

        if let quotedPath = AgentRequestTextScanner.backtickQuotedValues(in: trimmed)
            .compactMap(safeRelativeWorkspacePath)
            .first {
            return quotedPath
        }

        return tokens(in: trimmed)
            .compactMap(safeRelativeWorkspacePath)
            .first
    }

    private static func isReadRequest(_ lower: String) -> Bool {
        lower.hasPrefix("read ")
            || lower.hasPrefix("cat ")
            || lower.hasPrefix("show ")
            || lower.contains(" contents of ")
            || lower.contains(" content of ")
            || lower.contains("what is in ")
            || lower.contains("what's in ")
    }

    private static func tokens(in request: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'(),<>[]{}"))
        return request
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`.:;!?")) }
            .filter { !$0.isEmpty }
    }

    private static func safeRelativeWorkspacePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !lower.hasPrefix("http://"),
              !lower.hasPrefix("https://"),
              !lower.hasPrefix("file://"),
              !trimmed.split(separator: "/").contains(".."),
              looksLikeFilePath(trimmed)
        else {
            return nil
        }
        return trimmed
    }

    private static func looksLikeFilePath(_ value: String) -> Bool {
        value.contains("/") || value.split(separator: "/").last?.contains(".") == true
    }
}
