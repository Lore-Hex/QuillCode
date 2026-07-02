import Foundation

/// Suggests likely intended paths when a tool call names a file that does not exist, so the model
/// can recover from a typo'd path in one turn instead of listing the directory first.
public enum FilePathSuggester {
    public static let maxSuggestions = 3

    /// Same-directory siblings of the missing file, ranked by name similarity. Empty when the
    /// parent directory does not exist or holds nothing close enough to suggest.
    public static func siblingSuggestions(forMissing url: URL, limit: Int = maxSuggestions) -> [String] {
        let target = url.lastPathComponent
        let directory = url.deletingLastPathComponent().path
        guard !target.isEmpty,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory)
        else {
            return []
        }
        let includeHidden = target.hasPrefix(".")
        let ranked: [(name: String, rank: Int)] = names.compactMap { name in
            guard includeHidden || !name.hasPrefix(".") else { return nil }
            guard let rank = similarityRank(target: target, candidate: name) else { return nil }
            return (name: name, rank: rank)
        }
        return ranked
            .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
            .prefix(limit)
            .map(\.name)
    }

    /// A "Did you mean: …?" clause for a missing file, with each suggestion rendered relative to
    /// the requested path's directory so the model can retry it verbatim. Nil when the directory
    /// does not exist or has no similar sibling.
    public static func didYouMeanClause(requestedPath: String, resolvedURL: URL) -> String? {
        let siblings = siblingSuggestions(forMissing: resolvedURL)
        guard !siblings.isEmpty else { return nil }
        let directory = requestedPath.lastIndex(of: "/").map { String(requestedPath[...$0]) } ?? ""
        return "Did you mean: \(siblings.map { directory + $0 }.joined(separator: ", "))?"
    }

    /// The full missing-file message for a tool result: the standard `pathNotFound` description
    /// plus sibling suggestions when there are any.
    public static func missingFileMessage(requestedPath: String, resolvedURL: URL) -> String {
        let base = FileToolError.pathNotFound(requestedPath).description
        guard let clause = didYouMeanClause(requestedPath: requestedPath, resolvedURL: resolvedURL) else {
            return base
        }
        return "\(base). \(clause)"
    }

    /// Lower rank = closer match; nil = not similar enough to suggest. Case-insensitive; favors
    /// case-only and extension-only differences, then small edit distances, then stem prefixes
    /// (`FileTool` → `FileToolExecutor`).
    static func similarityRank(target: String, candidate: String) -> Int? {
        let a = target.lowercased()
        let b = candidate.lowercased()
        if a == b { return 0 }
        let aStem = stem(a)
        let bStem = stem(b)
        if aStem == bStem { return 1 }
        let distance = editDistance(a, b)
        if distance <= max(2, min(a.count, b.count) / 3) { return 2 + distance }
        if min(aStem.count, bStem.count) >= 3,
           aStem.hasPrefix(bStem) || bStem.hasPrefix(aStem) || aStem.hasSuffix(bStem) || bStem.hasSuffix(aStem) {
            return 6 + abs(a.count - b.count)
        }
        return nil
    }

    private static func stem(_ name: String) -> Substring {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name[...] }
        return name[..<dot]
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let lhs = Array(a)
        let rhs = Array(b)
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
