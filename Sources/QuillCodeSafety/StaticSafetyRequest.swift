import Foundation

struct StaticSafetyRequest: Sendable {
    private let text: String

    init(_ text: String) {
        self.text = text.lowercased()
    }

    var significantWords: [String] {
        tokens.filter { $0.count >= 3 }
    }

    var requestedDownloadHosts: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`()[]{}<>"))
        return text
            .components(separatedBy: separators)
            .compactMap(Self.normalizedHostCandidate)
    }

    var requestedDownloadFileURLs: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`()[]{}<>"))
        return text
            .components(separatedBy: separators)
            .compactMap(Self.normalizedFileURLCandidate)
    }

    func containsAffirmedAny(_ phrases: [String]) -> Bool {
        phrases.contains { containsAffirmed($0) }
    }

    func containsToken(_ token: String) -> Bool {
        let normalized = token.lowercased()
        return tokens.contains { $0 == normalized }
    }

    private var tokens: [String] {
        indexedTokens.map(\.value)
    }

    private var indexedTokens: [IndexedToken] {
        Self.tokenizeWithClauseStarts(text)
    }

    private func containsAffirmed(_ phrase: String) -> Bool {
        guard text.contains(phrase.lowercased()) else {
            return false
        }
        let phraseTokens = Self.tokenize(phrase)
        guard !phraseTokens.isEmpty else {
            return false
        }
        let requestTokens = indexedTokens
        guard requestTokens.count >= phraseTokens.count else {
            return false
        }
        for start in 0...(requestTokens.count - phraseTokens.count) {
            let end = start + phraseTokens.count
            let tokenValues = requestTokens[start..<end].map(\.value)
            guard tokenValues == phraseTokens else {
                continue
            }
            if !hasNegationBefore(start, in: requestTokens) {
                return true
            }
        }
        return false
    }

    private func hasNegationBefore(_ index: Int, in tokens: [IndexedToken]) -> Bool {
        guard index > 0 else {
            return false
        }
        let clauseStart = stride(from: index, through: 0, by: -1)
            .first { tokens[$0].startsClause } ?? 0
        let start = max(clauseStart, index - 4)
        let prefix = tokens[start..<index].map(\.value)
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

    private struct IndexedToken: Sendable {
        var value: String
        var startsClause: Bool
    }

    private func containsAdjacent(_ first: String, _ second: String, in tokens: [String]) -> Bool {
        guard tokens.count >= 2 else {
            return false
        }
        return zip(tokens, tokens.dropFirst()).contains { $0 == first && $1 == second }
    }

    private static func tokenize(_ value: String) -> [String] {
        tokenizeWithClauseStarts(value).map(\.value)
    }

    private static func tokenizeWithClauseStarts(_ value: String) -> [IndexedToken] {
        var tokens: [IndexedToken] = []
        var current = ""
        var nextStartsClause = true
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")

        func flushToken() {
            guard !current.isEmpty else {
                return
            }
            tokens.append(.init(value: current, startsClause: nextStartsClause))
            current = ""
            nextStartsClause = false
        }

        for character in normalized {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                flushToken()
                if isClauseBoundary(character) {
                    nextStartsClause = true
                }
            }
        }
        flushToken()
        return tokens
    }

    private static func isClauseBoundary(_ character: Character) -> Bool {
        character == ";" || character == "." || character == "!" || character == "?" || character == "\n"
    }

    private static func normalizedHostCandidate(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: ",:;!?"))
        let lowerCandidate = candidate.lowercased()
        guard !lowerCandidate.hasPrefix("file://"),
              candidate.contains("."),
              !candidate.contains("@")
        else {
            return nil
        }
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard let host = URL(string: candidate)?.host?.lowercased(),
              host.contains(".")
        else {
            return nil
        }
        return normalizedHost(host)
    }

    /// Normalizes a host for comparison: strips a leading `www.` and a trailing FQDN-root `.`, then
    /// requires the result still be a non-empty dotted domain. Guarding the POST-strip value is what
    /// keeps a dangling `www.` from collapsing to the empty string (which would otherwise let the
    /// gate's `hasSuffix(".\(requested)")` clause wildcard every trailing-dot host). Used on BOTH the
    /// requested side and the command-URL side so `169.254.169.254.` and `169.254.169.254` compare equal.
    static func normalizedHost(_ rawHost: String) -> String? {
        var host = rawHost.lowercased()
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        if host.hasSuffix(".") {
            host = String(host.dropLast())
        }
        guard host.contains("."), !host.hasPrefix(".") else {
            return nil
        }
        return host
    }

    private static func normalizedFileURLCandidate(_ value: String) -> String? {
        let candidate = value
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;!?"))
            .lowercased()
        return candidate.hasPrefix("file://") ? candidate : nil
    }
}
