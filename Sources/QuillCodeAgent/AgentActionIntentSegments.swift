import Foundation

enum AgentActionIntentSegments {
    static func actionableSegments(in request: String) -> [String] {
        clauses(in: request)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !containsNegatedActionIntent($0) }
    }

    static func isOnlyNegatedActionRequest(_ request: String) -> Bool {
        let segments = clauses(in: request)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard segments.contains(where: containsNegatedActionIntent) else {
            return false
        }
        return !segments
            .filter { !containsNegatedActionIntent($0) }
            .contains(where: containsActionIntent)
    }

    private static func clauses(in request: String) -> [String] {
        var output: [String] = []
        var start = request.startIndex
        var index = start
        var quotedCloser: Character?

        func appendClause(endingAt end: String.Index) {
            output.append(String(request[start..<end]))
            start = request.index(after: end)
        }

        while index < request.endIndex {
            let character = request[index]
            let next = request.index(after: index)
            if let closer = quotedCloser {
                if character == closer,
                   !(closer == "'" && isWordApostrophe(at: index, in: request)) {
                    quotedCloser = nil
                }
                index = next
                continue
            }
            if let closer = quoteCloser(
                for: character,
                at: index,
                in: request
            ) {
                quotedCloser = closer
                index = next
                continue
            }
            let isBoundary = character == ";"
                || character == "?"
                || character == "!"
                || character == "\n"
                || (character == "." && (next == request.endIndex || request[next].isWhitespace))
            if isBoundary {
                appendClause(endingAt: index)
            }
            index = next
        }

        if start < request.endIndex {
            output.append(String(request[start..<request.endIndex]))
        }
        return output
    }

    private static func quoteCloser(
        for character: Character,
        at index: String.Index,
        in request: String
    ) -> Character? {
        switch character {
        case "`", "\"":
            return character
        case "'":
            return isWordApostrophe(at: index, in: request) ? nil : character
        case "“":
            return "”"
        case "‘":
            return "’"
        default:
            return nil
        }
    }

    private static func isWordApostrophe(at index: String.Index, in request: String) -> Bool {
        guard index > request.startIndex else { return false }
        let next = request.index(after: index)
        guard next < request.endIndex else { return false }
        return request[request.index(before: index)].isLetter && request[next].isLetter
    }

    private static func containsNegatedActionIntent(_ segment: String) -> Bool {
        let tokens = tokenized(segment)
        guard let actionIndex = tokens.firstIndex(where: actionTokens.contains) else {
            return false
        }
        let prefix = Array(tokens[max(0, actionIndex - 6)..<actionIndex])
        if prefix.contains(where: { ["dont", "never", "without"].contains($0) }) {
            return true
        }
        if prefix.last == "no" {
            return true
        }
        return containsAdjacent("do", "not", in: prefix)
            || containsAdjacent("does", "not", in: prefix)
            || containsAdjacent("did", "not", in: prefix)
    }

    static func containsActionIntent(_ segment: String) -> Bool {
        tokenized(segment).contains(where: actionTokens.contains)
    }

    private static let actionTokens: Set<String> = [
        "check",
        "create",
        "download",
        "execute",
        "fetch",
        "list",
        "make",
        "read",
        "run",
        "save",
        "show",
        "write"
    ]

    private static func tokenized(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current = ""
        }

        for character in normalized {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func containsAdjacent(_ first: String, _ second: String, in tokens: [String]) -> Bool {
        guard tokens.count >= 2 else {
            return false
        }
        return zip(tokens, tokens.dropFirst()).contains { $0 == first && $1 == second }
    }
}
