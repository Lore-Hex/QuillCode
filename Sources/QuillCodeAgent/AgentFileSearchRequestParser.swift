import Foundation

enum AgentFileSearchRequestParser {
    static func request(from userMessage: String) -> AgentFileSearchRequest? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard containsSearchIntent(lower) else { return nil }
        guard let query = explicitQuery(from: trimmed, lowercasedRequest: lower) else { return nil }

        return AgentFileSearchRequest(
            query: query,
            path: scopedPath(from: trimmed, lowercasedRequest: lower)
        )
    }

    private static func containsSearchIntent(_ lower: String) -> Bool {
        lower.hasPrefix("find ")
            || lower.hasPrefix("search ")
            || lower.hasPrefix("grep ")
            || lower.contains(" search for ")
            || lower.contains(" find ")
            || lower.contains(" where is ")
            || lower.contains(" where are ")
            || lower.contains(" defined")
            || lower.contains(" used")
    }

    private static func explicitQuery(from request: String, lowercasedRequest lower: String) -> String? {
        if let quoted = quotedValues(in: request).first {
            return normalizedQuery(quoted)
        }

        for marker in queryMarkers {
            guard let range = lower.range(of: marker) else { continue }
            let suffix = String(request[range.upperBound...])
            if let query = normalizedQuery(queryPrefix(from: suffix)) {
                return query
            }
        }

        if lower.hasPrefix("grep ") || lower.hasPrefix("find ") || lower.hasPrefix("search ") {
            let pieces = request.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if pieces.count == 2 {
                return normalizedQuery(queryPrefix(from: String(pieces[1])))
            }
        }

        return nil
    }

    private static func queryPrefix(from suffix: String) -> String {
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        for delimiter in [" in ", " under ", " inside ", " within "] {
            if let range = trimmed.range(of: delimiter, options: [.caseInsensitive]) {
                return String(trimmed[..<range.lowerBound])
            }
        }
        return trimmed
    }

    private static func scopedPath(from request: String, lowercasedRequest lower: String) -> String? {
        for marker in pathMarkers {
            guard let range = lower.range(of: marker) else { continue }
            let suffix = String(request[range.upperBound...])
            if let path = safeRelativeWorkspacePath(firstPathToken(in: suffix)) {
                return path
            }
            if let quoted = quotedValues(in: suffix).first,
               let path = safeRelativeWorkspacePath(quoted) {
                return path
            }
        }
        return nil
    }

    private static func normalizedQuery(_ value: String) -> String? {
        var trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`.:;!?"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in trailingQueryNoise {
            if trimmed.lowercased().hasSuffix(suffix) {
                trimmed = String(trimmed.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`.:;!?"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard !reservedQueryTerms.contains(lower) else { return nil }
        return trimmed
    }

    private static func firstPathToken(in suffix: String) -> String {
        suffix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { separator in
                separator.isWhitespace || "\"'“”‘’(),<>[]{}".contains(separator)
            })
            .first
            .map(String.init) ?? ""
    }

    private static func safeRelativeWorkspacePath(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`.:;!?"))
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !lower.hasPrefix("http://"),
              !lower.hasPrefix("https://"),
              !lower.hasPrefix("file://"),
              !trimmed.split(separator: "/").contains("..")
        else {
            return nil
        }
        return trimmed
    }

    private static func quotedValues(in text: String) -> [String] {
        var values: [String] = []
        collectDelimitedValues(in: text, opener: "`", closer: "`", into: &values)
        collectDelimitedValues(in: text, opener: "\"", closer: "\"", into: &values)
        collectDelimitedValues(in: text, opener: "'", closer: "'", into: &values)
        collectDelimitedValues(in: text, opener: "“", closer: "”", into: &values)
        collectDelimitedValues(in: text, opener: "‘", closer: "’", into: &values)
        return values
    }

    private static func collectDelimitedValues(
        in text: String,
        opener: Character,
        closer: Character,
        into values: inout [String]
    ) {
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let first = text[cursor...].firstIndex(of: opener) {
            let afterFirst = text.index(after: first)
            guard afterFirst < text.endIndex,
                  let last = text[afterFirst...].firstIndex(of: closer)
            else {
                break
            }
            let value = String(text[afterFirst..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                values.append(value)
            }
            cursor = text.index(after: last)
        }
    }

    private static let queryMarkers = [
        "search for ",
        "find ",
        "grep ",
        "where is ",
        "where are ",
        "defined",
        "used"
    ]

    private static let pathMarkers = [
        " in ",
        " under ",
        " inside ",
        " within "
    ]

    private static let trailingQueryNoise = [
        " is defined",
        " are defined",
        " defined",
        " is used",
        " are used",
        " used"
    ]

    private static let reservedQueryTerms: Set<String> = [
        "files",
        "file",
        "where",
        "defined",
        "used"
    ]
}

struct AgentFileSearchRequest: Sendable, Equatable {
    var query: String
    var path: String?

    var arguments: [String: Any] {
        var values: [String: Any] = ["query": query]
        if let path {
            values["path"] = path
        }
        return values
    }
}
