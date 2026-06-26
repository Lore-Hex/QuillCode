import Foundation

public enum GitHubPullRequestOutputParser {
    public static func extractURLs(from output: String) -> [String] {
        let pattern = #"https?://[^\s"'<>)\]},]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        return regex.matches(in: output, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: output) else { return nil }
            return String(output[matchRange])
        }
    }
}
