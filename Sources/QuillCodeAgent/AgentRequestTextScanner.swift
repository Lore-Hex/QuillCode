import Foundation

/// Shared text-scanning primitives for the natural-language Agent request parsers — the mock /
/// simulated tool-call path that turns a prose instruction into a structured tool call. Each parser
/// had copy-pasted these, so they live here once to keep the scanning rules consistent.
enum AgentRequestTextScanner {
    /// Every non-empty, trimmed value enclosed in a pair of backticks, in order of appearance.
    static func backtickQuotedValues(in request: String) -> [String] {
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

    /// The set of maximal alphanumeric runs in a (typically lowercased) string — the word tokens used
    /// for keyword matching. NOTE: this splits on apostrophes too; parsers that must keep contractions
    /// intact (file listing) keep their own tokenizer.
    static func alphanumericWordTokens(in text: String) -> Set<String> {
        Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}
