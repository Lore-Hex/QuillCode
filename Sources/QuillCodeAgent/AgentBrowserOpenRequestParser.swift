import Foundation

enum AgentBrowserOpenRequestParser {
    static func request(from text: String) -> String? {
        let lower = text.lowercased()
        guard isBrowserIntent(lower), !isDownloadIntent(lower) else { return nil }

        if let quoted = AgentRequestTextScanner.backtickQuotedValues(in: text)
            .first(where: looksLikeBrowserTarget) {
            return normalizedBrowserTarget(quoted)
        }

        return browserTokens(in: text)
            .first(where: looksLikeBrowserTarget)
            .map(normalizedBrowserTarget)
    }

    private static func isBrowserIntent(_ lower: String) -> Bool {
        browserIntentPhrases.contains { lower.contains($0) }
    }

    private static func isDownloadIntent(_ lower: String) -> Bool {
        downloadIntentPhrases.contains { lower.contains($0) }
    }

    private static func browserTokens(in text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "`\"'(),<>[]{}"))
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".:;!?")) }
            .filter { !$0.isEmpty }
    }

    private static func looksLikeBrowserTarget(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("file://")
            || lower.hasPrefix("localhost")
            || lower.hasPrefix("127.0.0.1")
            || lower.hasPrefix("./") {
            return true
        }
        guard !lower.hasPrefix("/"),
              !lower.contains("@")
        else {
            return false
        }
        let firstPathComponent = lower.split(separator: "/", maxSplits: 1).first ?? ""
        return firstPathComponent.split(separator: ".").last.map { knownWebTLDs.contains(String($0)) } == true
    }

    private static func normalizedBrowserTarget(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("file://")
            || lower.hasPrefix("localhost")
            || lower.hasPrefix("127.0.0.1")
            || lower.hasPrefix("./") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private static let browserIntentPhrases = [
        "open ",
        "inspect ",
        "check ",
        "view ",
        "look at ",
        "review ",
        "visit ",
        "go to ",
        "navigate to ",
        "use "
    ]

    private static let downloadIntentPhrases = [
        "download ",
        "save ",
        "fetch "
    ]

    private static let knownWebTLDs: Set<String> = [
        "ai", "app", "cloud", "co", "com", "dev", "edu", "gov", "io", "net", "org", "so"
    ]
}
