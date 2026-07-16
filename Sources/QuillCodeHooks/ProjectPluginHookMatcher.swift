import Foundation

public enum ProjectPluginHookMatcher {
    public static let maximumPatternCharacters = 512
    public static let maximumCandidateCharacters = 256

    public static func isValid(_ matcher: String?) -> Bool {
        guard let matcher, !matcher.isEmpty, matcher != "*" else { return true }
        guard matcher.count <= maximumPatternCharacters else { return false }
        return (try? NSRegularExpression(pattern: matcher)) != nil
    }

    public static func matches(_ matcher: String?, candidates: [String]) -> Bool {
        guard let matcher, !matcher.isEmpty, matcher != "*" else { return true }
        guard matcher.count <= maximumPatternCharacters,
              let expression = try? NSRegularExpression(pattern: matcher)
        else { return false }
        return candidates.contains { candidate in
            let bounded = String(candidate.prefix(maximumCandidateCharacters))
            let range = NSRange(bounded.startIndex..<bounded.endIndex, in: bounded)
            return expression.firstMatch(in: bounded, range: range) != nil
        }
    }
}
