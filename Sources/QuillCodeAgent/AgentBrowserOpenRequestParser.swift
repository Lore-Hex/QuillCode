import Foundation

enum AgentBrowserOpenRequestParser {
    static func request(from text: String) -> String? {
        let lower = text.lowercased()
        guard !isDownloadIntent(lower) else { return nil }

        if isBrowserIntent(lower) {
            if let quoted = AgentRequestTextScanner.backtickQuotedValues(in: text)
                .first(where: looksLikeBrowserTarget) {
                return normalizedBrowserTarget(quoted)
            }

            if let target = browserTokens(in: text)
                .first(where: looksLikeBrowserTarget)
                .map(normalizedBrowserTarget) {
                return target
            }
        }

        return knownSaaSTarget(in: lower)
    }

    private static func isBrowserIntent(_ lower: String) -> Bool {
        browserIntentPhrases.contains { lower.contains($0) }
    }

    private static func knownSaaSTarget(in lower: String) -> String? {
        guard knownSaaSIntentPhrases.contains(where: { lower.contains($0) }) else { return nil }
        return knownSaaSTargets.first { lower.contains($0.phrase) }?.url
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

    private static let knownSaaSIntentPhrases = browserIntentPhrases + [
        "find ",
        "pull ",
        "walk through ",
        "log into ",
        "login to ",
        "sign into ",
        "sign in to ",
        "build ",
        "create "
    ]

    private static let downloadIntentPhrases = [
        "download ",
        "save ",
        "fetch "
    ]

    private static let knownWebTLDs: Set<String> = [
        "ai", "app", "cloud", "co", "com", "dev", "edu", "gov", "io", "net", "org", "so"
    ]

    private static let knownSaaSTargets: [(phrase: String, url: String)] = [
        ("linkedin campaign manager", "https://www.linkedin.com/campaignmanager/"),
        ("google analytics", "https://analytics.google.com/"),
        ("google ads", "https://ads.google.com/"),
        ("google drive", "https://drive.google.com/"),
        ("google sheet", "https://sheets.google.com/"),
        ("google sheets", "https://sheets.google.com/"),
        ("hubspot", "https://app.hubspot.com/"),
        ("salesforce", "https://login.salesforce.com/"),
        ("mailchimp", "https://login.mailchimp.com/"),
        ("asana", "https://app.asana.com/"),
        ("zendesk", "https://www.zendesk.com/login/"),
        ("confluence", "https://id.atlassian.com/login"),
        ("jira", "https://id.atlassian.com/login"),
        ("notion", "https://www.notion.so/"),
        ("concur", "https://www.concursolutions.com/"),
    ]
}
