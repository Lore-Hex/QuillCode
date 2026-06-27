import Foundation
import QuillCodeCore

enum AgentPromisedWorkGuard {
    static func shouldRequestCorrection(for assistantText: String, tools: [ToolDefinition]) -> Bool {
        guard !tools.isEmpty else { return false }
        return promisesExecutableWork(assistantText)
    }

    static func correctionPrompt(assistantText: String, userMessage: String) -> String {
        """
        Your previous response promised to perform work but did not return a QuillCode tool action.

        Original user request:
        \(userMessage)

        Previous response:
        \(assistantText)

        Return exactly one QuillCode JSON action now. If you intended to perform the promised work, return the appropriate {"type":"tool",...} action with complete arguments. If no tool is needed, return {"type":"say","text":"..."} with a direct final answer and no future-tense promise.
        """
    }

    private static func promisesExecutableWork(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "’", with: "'")

        guard !asksForPermission(normalized),
              !containsNegativePromise(normalized)
        else {
            return false
        }

        return containsFutureWorkPhrase(in: normalized)
    }

    private static func asksForPermission(_ text: String) -> Bool {
        [
            "do you want me",
            "would you like me",
            "should i ",
            "can i ",
            "may i "
        ].contains { text.contains($0) }
    }

    private static func containsNegativePromise(_ text: String) -> Bool {
        [
            "i will not",
            "i won't",
            "i cannot",
            "i can't",
            "i do not",
            "i don't"
        ].contains { text.contains($0) }
    }

    private static func containsFutureWorkPhrase(in text: String) -> Bool {
        for starter in futureWorkStarters {
            var searchStart = text.startIndex
            while let range = text.range(of: starter, range: searchStart..<text.endIndex) {
                let tail = text[range.upperBound...].prefix(64)
                if containsWorkVerb(in: tail) {
                    return true
                }
                searchStart = range.upperBound
            }
        }
        return false
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

    private static let workVerbs: Set<String> = [
        "apply", "build", "check", "commit", "create", "delete", "download",
        "edit", "execute", "fetch", "fix", "inspect", "install", "list",
        "merge", "open", "push", "read", "review", "run", "search", "test",
        "update", "write"
    ]
}
