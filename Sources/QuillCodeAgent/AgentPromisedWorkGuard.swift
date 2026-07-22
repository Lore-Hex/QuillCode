import Foundation
import QuillCodeCore

enum AgentPromisedWorkGuard {
    static func shouldRequestCorrection(for assistantText: String, tools: [ToolDefinition]) -> Bool {
        guard !tools.isEmpty else { return false }
        return promisesExecutableWork(assistantText) || endsWithUnfinishedNarration(assistantText)
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

    // MARK: - Trailing-off narration (structural, no first-person phrase required)

    /// A say that STOPS mid-narration — the live trailing-off failure driving coworker tasks: the
    /// model narrates "Step 1: … (done) … Step 2: … (content) …" and then ends its turn on a bare
    /// "**Step 3: Setting up virtualenv with uv**" heading — no content, no tool call. No "I'll…"
    /// phrase appears, so the promise lexicon misses it; the STRUCTURE is the signal. Two
    /// high-precision shapes:
    ///
    /// 1. The message's last non-empty line is a step-heading ("Step N: …") and an EARLIER
    ///    step-heading exists — mid-way truncation of a numbered walkthrough. (The prior-step
    ///    requirement keeps a one-line "Step 1: do X" answer from firing.)
    /// 2. The last non-empty line ends with a colon — a lead-in ("Next steps:") whose promised
    ///    content never arrived.
    ///
    /// Streaming previews deliberately do NOT use this check (a mid-stream text always ends
    /// mid-something); it only judges the COMPLETE say via `shouldRequestCorrection`.
    static func endsWithUnfinishedNarration(_ text: String) -> Bool {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else { return false }
        let stripped = strippedMarkdownDecoration(last)

        if isStepHeading(stripped) {
            let hasEarlierStep = lines.dropLast().contains { isStepHeading(strippedMarkdownDecoration($0)) }
            if hasEarlierStep { return true }
        }
        if stripped.hasSuffix(":") && stripped.count >= 4 {
            return true
        }
        return false
    }

    /// Strips the markdown decoration a heading line wears (`**Step 3: …**`, `### Step 3`) without
    /// touching interior punctuation.
    private static func strippedMarkdownDecoration(_ line: String) -> String {
        var slice = Substring(line)
        while let first = slice.first, first == "#" || first == "*" || first == "_" || first == " " {
            slice = slice.dropFirst()
        }
        while let lastCharacter = slice.last,
              lastCharacter == "*" || lastCharacter == "_" || lastCharacter == " " {
            slice = slice.dropLast()
        }
        return String(slice)
    }

    private static func isStepHeading(_ line: String) -> Bool {
        let lowered = line.lowercased()
        guard lowered.hasPrefix("step ") else { return false }
        return lowered.dropFirst("step ".count).first?.isNumber == true
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
