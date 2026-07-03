import Foundation

extension TestCommandLexicon {
    /// Splits a command line into segments separated by shell control operators.
    ///
    /// Quote-aware: an operator inside single/double quotes or backticks does not
    /// split, so runner names inside quoted arguments of non-runner commands do
    /// not become synthetic command segments.
    static func commandSegments(in lowered: String) -> [String] {
        let scalars = Array(lowered)
        guard quotesAreBalanced(scalars) else {
            let trimmed = lowered.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        var segments: [String] = []
        var current = ""
        var quote: Character?
        var i = 0
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { segments.append(trimmed) }
            current = ""
        }
        while i < scalars.count {
            let c = scalars[i]
            if let open = quote {
                current.append(c)
                if c == open { quote = nil }
                i += 1
                continue
            }
            if isQuoteChar(c) {
                quote = c
                current.append(c)
                i += 1
                continue
            }
            let next: Character? = i + 1 < scalars.count ? scalars[i + 1] : nil
            if (c == "&" && next == "&") || (c == "|" && next == "|") {
                flush()
                i += 2
                continue
            }
            if c == ";" || c == "|" || c == "&" || c == "\n" {
                flush()
                i += 1
                continue
            }
            current.append(c)
            i += 1
        }
        flush()
        return segments
    }

    static func isQuoteChar(_ c: Character) -> Bool {
        c == "'" || c == "\"" || c == "`"
    }

    /// Whether single/double quotes and backticks are balanced.
    static func quotesAreBalanced(_ scalars: [Character]) -> Bool {
        var quote: Character?
        for c in scalars {
            if let open = quote {
                if c == open { quote = nil }
            } else if isQuoteChar(c) {
                quote = c
            }
        }
        return quote == nil
    }

    /// Substring match with cheap word-ish boundaries.
    static func containsToken(_ token: String, in haystack: String) -> Bool {
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: token, options: [], range: searchRange) {
            let beforeOK = found.lowerBound == haystack.startIndex
                || !isWordScalar(haystack[haystack.index(before: found.lowerBound)])
            let afterOK = found.upperBound == haystack.endIndex
                || !isWordScalar(haystack[found.upperBound])
            if beforeOK && afterOK { return true }
            if found.upperBound >= haystack.endIndex { break }
            searchRange = haystack.index(after: found.lowerBound)..<haystack.endIndex
        }
        return false
    }

    static func isWordScalar(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
