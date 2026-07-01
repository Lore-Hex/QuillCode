import Foundation

/// Ranks "did you mean" candidates for a missing file name so a typo'd path costs the model one
/// glance instead of a whole recovery turn (list directory → re-read). Pure and deterministic:
/// scoring is case-insensitive edit distance with a tight budget — a suggestion that isn't obviously
/// the intended file is worse than no suggestion.
public enum FilePathSuggester {
    /// At most this many candidate names are scored; a pathological directory shouldn't stall a read.
    public static let maxCandidates = 2000

    /// The closest sibling names to `missing`, best first. Empty when nothing is plausibly close.
    public static func suggest(missing: String, candidates: [String], limit: Int = 3) -> [String] {
        let target = missing.lowercased()
        guard !target.isEmpty else { return [] }
        // A typo budget that scales with length but stays tight: 1 edit for short names, up to 3 for
        // long ones. Beyond that the candidate is a different name, not a misspelling.
        let budget = min(3, max(1, target.count / 4))
        let targetExtension = (missing as NSString).pathExtension.lowercased()

        let scored: [(name: String, distance: Int, extensionMatches: Bool)] = candidates
            .prefix(maxCandidates)
            .compactMap { candidate in
                guard candidate != missing else { return nil }   // byte-identical → exists; not a typo
                let name = candidate.lowercased()
                // A case-only difference is the best possible match (it IS the file on a case-sensitive
                // filesystem like Linux CI).
                if name == target {
                    return (candidate, 0, true)
                }
                // Cheap pre-filter: names whose lengths differ by more than the budget can't be within it.
                guard abs(name.count - target.count) <= budget else { return nil }
                let distance = editDistance(target, name, cap: budget)
                guard distance <= budget else { return nil }
                let extensionMatches = (candidate as NSString).pathExtension.lowercased() == targetExtension
                return (candidate, distance, extensionMatches)
            }

        return scored
            .sorted {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                if $0.extensionMatches != $1.extensionMatches { return $0.extensionMatches }
                return $0.name < $1.name
            }
            .prefix(limit)
            .map(\.name)
    }

    /// Damerau-Levenshtein (optimal string alignment) distance with an early-exit cap: once every
    /// value in a row exceeds `cap`, the final distance must too, so we stop. Transposition counts as
    /// ONE edit — swapping adjacent letters ("mian" → "main") is the single most common typo, and plain
    /// Levenshtein's 2 would blow the tight budget for short names. Three rolling rows, O(n) space.
    static func editDistance(_ a: String, _ b: String, cap: Int) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var beforePrevious = [Int](repeating: 0, count: bChars.count + 1)
        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            var rowMin = i
            for j in 1...bChars.count {
                let substitution = previous[j - 1] + (aChars[i - 1] == bChars[j - 1] ? 0 : 1)
                var best = min(previous[j] + 1, current[j - 1] + 1, substitution)
                if i > 1, j > 1, aChars[i - 1] == bChars[j - 2], aChars[i - 2] == bChars[j - 1] {
                    best = min(best, beforePrevious[j - 2] + 1)   // adjacent transposition
                }
                current[j] = best
                rowMin = min(rowMin, best)
            }
            if rowMin > cap { return cap + 1 }
            (beforePrevious, previous, current) = (previous, current, beforePrevious)
        }
        return previous[bChars.count]
    }
}
