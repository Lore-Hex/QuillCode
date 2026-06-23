public enum GitHubPullRequestOutputParser {
    public static func extractURLs(from output: String) -> [String] {
        output
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
    }
}
