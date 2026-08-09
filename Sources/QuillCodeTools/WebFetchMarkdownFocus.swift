import Foundation

/// Selects compact source-order windows around query matches before fetched markdown is
/// added to the agent context. The full response is still decoded locally; only the relevant
/// evidence windows are returned to the model.
public enum WebFetchMarkdownFocus {
    public static let defaultMaxSelectedLines = 240

    private static let stopWords: Set<String> = [
        "about", "after", "before", "company", "each", "from", "have", "into",
        "most", "page", "reported", "result", "results", "that", "their", "this",
        "using", "with",
    ]

    public static func select(
        _ text: String,
        query: String,
        maxSelectedLines: Int = defaultMaxSelectedLines
    ) -> (text: String, focused: Bool) {
        let terms = Set(words(in: query).filter { $0.count >= 2 && !stopWords.contains($0) })
        guard !terms.isEmpty else { return (text, false) }

        let lines = text.components(separatedBy: "\n")
        let scored = lines.enumerated().compactMap { index, line -> (Int, Int)? in
            let matches = terms.intersection(words(in: line)).count
            return matches > 0 ? (index, matches) : nil
        }
        guard !scored.isEmpty else { return (text, false) }

        let lineLimit = max(24, maxSelectedLines)
        var selected = Set(0..<min(12, lines.count))
        for (index, _) in scored.sorted(by: { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
        }) {
            for candidate in max(0, index - 2)...min(lines.count - 1, index + 2) {
                selected.insert(candidate)
            }
            if selected.count >= lineLimit { break }
        }

        let ordered = selected.sorted().prefix(lineLimit)
        var output: [String] = []
        var previous: Int?
        for index in ordered {
            if let previous, index > previous + 1 {
                output.append("[... \(index - previous - 1) non-matching lines omitted ...]")
            }
            output.append(lines[index])
            previous = index
        }
        return (output.joined(separator: "\n"), true)
    }

    private static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
    }
}
