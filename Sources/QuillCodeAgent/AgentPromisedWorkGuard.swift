import Foundation
import QuillCodeCore

enum AgentPromisedWorkGuard {
    static func shouldRequestCorrection(for assistantText: String, tools: [ToolDefinition]) -> Bool {
        guard !tools.isEmpty else { return false }
        return promisesExecutableWork(assistantText)
    }

    static func shouldSuppressStreamingPreview(for assistantText: String) -> Bool {
        let normalized = normalizedText(assistantText)
        guard canContainActionablePromise(normalized) else { return false }

        return containsFutureWorkPhrase(in: normalized)
            || containsUnresolvedFutureWorkStarter(in: normalized)
    }

    static func correctionPrompt(assistantText: String, userMessage: String) -> String {
        """
        Your previous response promised to perform work but did not return a QuillCode tool action.

        Original user request:
        \(userMessage)

        Previous response:
        \(assistantText)

        Return exactly one QuillCode JSON action now. If you intended to perform the promised work,
        return the appropriate {"type":"tool",...} action with complete arguments. If no tool is
        needed, return {"type":"say","text":"..."} with a direct final answer and no future-tense promise.
        """
    }

    private static func promisesExecutableWork(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        guard canContainActionablePromise(normalized) else { return false }

        return containsFutureWorkPhrase(in: normalized)
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "’", with: "'")
    }

    private static func canContainActionablePromise(_ text: String) -> Bool {
        !asksForPermission(text) && !containsNegativePromise(text)
    }

    private static func asksForPermission(_ text: String) -> Bool {
        containsAnyPhrase(in: text, phrases: [
            "do you want me",
            "would you like me",
            "should i ",
            "can i ",
            "may i "
        ])
    }

    private static func containsNegativePromise(_ text: String) -> Bool {
        containsAnyPhrase(in: text, phrases: [
            "i will not",
            "i won't",
            "i cannot",
            "i can't",
            "i do not",
            "i don't"
        ])
    }

    private static func containsAnyPhrase(in text: String, phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func containsFutureWorkPhrase(in text: String) -> Bool {
        actionableStarterRanges(in: text).contains { range in
            containsWorkVerb(in: text[range.upperBound...].prefix(64))
        }
    }

    private static func containsUnresolvedFutureWorkStarter(in text: String) -> Bool {
        actionableStarterRanges(in: text).contains { range in
            trimmedText(after: range, in: text).count < unresolvedStarterPreviewCharacterLimit
        }
    }

    private static func actionableStarterRanges(in text: String) -> [Range<String.Index>] {
        futureWorkStarters.flatMap { starter in
            ranges(of: starter, in: text)
        }.filter { range in
            !isLetMeKnowCourtesy(text, after: range)
        }
    }

    private static func isLetMeKnowCourtesy(_ text: String, after range: Range<String.Index>) -> Bool {
        text[range] == "let me" && trimmedText(after: range, in: text).hasPrefix("know")
    }

    private static func trimmedText(after range: Range<String.Index>, in text: String) -> String {
        text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ranges(of starter: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: starter, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func containsWorkVerb(in text: Substring) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .contains { workVerbs.contains(String($0)) }
    }

    private static let futureWorkStarters = [
        "i'll",
        "i will",
        "i'm going to",
        "i am going to",
        "let me"
    ]

    private static let unresolvedStarterPreviewCharacterLimit = 8

    private static let workVerbs: Set<String> = [
        "apply", "build", "check", "commit", "create", "delete", "download",
        "edit", "execute", "fetch", "fix", "inspect", "install", "list",
        "merge", "open", "push", "read", "review", "run", "search", "test",
        "update", "write"
    ]
}
