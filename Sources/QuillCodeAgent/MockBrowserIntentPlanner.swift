import Foundation

enum MockBrowserIntentPlanner {
    static func isInspectionRequest(_ lowercasedRequest: String) -> Bool {
        let browserTerms = lowercasedRequest.contains("browser")
            || lowercasedRequest.contains("page")
            || lowercasedRequest.contains("preview")
            || lowercasedRequest.contains("localhost")
        let inspectionTerms = lowercasedRequest.contains("inspect")
            || lowercasedRequest.contains("look at")
            || lowercasedRequest.contains("what is on")
            || lowercasedRequest.contains("summarize")
            || lowercasedRequest.contains("snapshot")
        return browserTerms && inspectionTerms
    }

    static func openTarget(from request: String, lowercasedRequest: String) -> String? {
        let navigationTerms = [
            "open ",
            "browse ",
            "go to ",
            "visit ",
            "preview ",
            "show "
        ]
        guard navigationTerms.contains(where: { lowercasedRequest.contains($0) }) else {
            return nil
        }

        if let quoted = AgentRequestTextScanner.backtickQuotedValues(in: request).first,
           looksLikeBrowserTarget(quoted) {
            return quoted
        }

        let tokenSeparators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'(),<>[]{}"))
        return request
            .components(separatedBy: tokenSeparators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".:;!?")) }
            .filter { !$0.isEmpty }
            .first(where: looksLikeBrowserTarget)
    }

    private static func looksLikeBrowserTarget(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("file://")
            || lower.hasPrefix("localhost")
            || lower.hasPrefix("127.0.0.1")
            || lower.hasPrefix("./")
            || lower.hasPrefix("/")
            || lower.hasSuffix(".html")
            || lower.hasSuffix(".htm")
            || (lower.contains(".") && !lower.contains("@"))
    }
}
