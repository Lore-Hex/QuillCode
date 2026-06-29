import Foundation

struct AgentFileWriteRequest: Sendable, Equatable {
    var path: String
    var content: String

    var arguments: [String: String] {
        [
            "path": path,
            "content": content
        ]
    }
}

enum AgentFileWriteRequestParser {
    static func request(from userMessage: String) -> AgentFileWriteRequest? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard containsFileWriteIntent(lower) else { return nil }

        guard let content = extractContent(from: trimmed, lowercasedRequest: lower) else {
            return nil
        }

        return AgentFileWriteRequest(
            path: extractPath(from: trimmed, lowercasedRequest: lower)
                ?? defaultPath(for: content, lowercasedRequest: lower),
            content: content.hasSuffix("\n") ? content : "\(content)\n"
        )
    }

    private static func containsFileWriteIntent(_ lower: String) -> Bool {
        lower.contains("file")
            && ["write", "create", "make", "save"].contains { lower.contains($0) }
    }

    private static func extractContent(
        from request: String,
        lowercasedRequest lower: String
    ) -> String? {
        for marker in contentMarkers {
            guard let markerRange = lower.range(of: marker) else { continue }
            let suffix = String(request[markerRange.upperBound...])
            if let quoted = firstQuotedValue(in: suffix) {
                return normalizedContent(quoted)
            }
            if let content = normalizedContent(sentencePrefix(from: suffix)) {
                return content
            }
        }

        if lower.contains("hello world") {
            return "hello world"
        }
        return nil
    }

    private static func extractPath(
        from request: String,
        lowercasedRequest lower: String
    ) -> String? {
        for marker in pathMarkers {
            guard let markerRange = lower.range(of: marker) else { continue }
            let suffix = String(request[markerRange.upperBound...])
            if let path = safeRelativeWorkspacePath(firstPathToken(in: suffix)) {
                return path
            }
            if let quoted = firstQuotedValue(in: suffix),
               let path = safeRelativeWorkspacePath(quoted) {
                return path
            }
        }

        return nil
    }

    private static func sentencePrefix(from suffix: String) -> String {
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if ".?!".contains(character) {
                let next = trimmed.index(after: index)
                if next == trimmed.endIndex || trimmed[next].isWhitespace {
                    return String(trimmed[..<index])
                }
            }
            index = trimmed.index(after: index)
        }
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

    private static func firstQuotedValue(in text: String) -> String? {
        quotedValues(in: text).first
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

    private static func normalizedContent(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’` "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private static func defaultPath(for content: String, lowercasedRequest lower: String) -> String {
        lower.contains("hello world") || content.lowercased() == "hello world"
            ? "hello.txt"
            : "note.txt"
    }

    private static let contentMarkers = [
        "that says",
        "saying",
        "says",
        "with content",
        "with text",
        "containing",
        "contents:"
    ]

    private static let pathMarkers = [
        "file named",
        "file called",
        "file at",
        "file in",
        "file to",
        "path"
    ]
}
