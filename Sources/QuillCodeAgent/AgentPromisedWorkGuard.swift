import Foundation
import QuillCodeCore

/// Why a `.say` needs to be re-driven instead of ending the run. The two kinds have DIFFERENT
/// failure semantics after the retry budget is spent, which is why this is a typed enum rather than
/// a bool:
/// - `.promisedWork` — the say claimed/started work it never did ("I'll run the tests", or a
///   trailing-off "Step 3:" heading). If the model keeps doing this it is a hard failure — throw.
/// - `.deferralToUser` — the say abandons a multi-step task by handing the next-action decision
///   back to the user ("what would you like me to do next?"). Fatal for an UNATTENDED run, where
///   nobody answers. But if, after being nudged to continue, the model still insists on asking, it
///   probably genuinely needs input — so this is ALLOWED through rather than thrown.
enum AgentSayCorrection: Sendable, Equatable {
    case promisedWork
    case deferralToUser

    /// Only unmet promised work is a hard error; a persistent, specific question is legitimate.
    var isHardFailure: Bool { self == .promisedWork }
}

enum AgentPromisedWorkGuard {
    /// The single classifier the resolver drives off of. `nil` = let the say end the run.
    static func correctionNeeded(for assistantText: String, tools: [ToolDefinition]) -> AgentSayCorrection? {
        guard !tools.isEmpty else { return nil }
        if promisesExecutableWork(assistantText) || endsWithUnfinishedNarration(assistantText) {
            return .promisedWork
        }
        if defersNextStepToUser(assistantText) {
            return .deferralToUser
        }
        return nil
    }

    static func shouldRequestCorrection(for assistantText: String, tools: [ToolDefinition]) -> Bool {
        correctionNeeded(for: assistantText, tools: tools) != nil
    }

    /// A say that ABANDONS a multi-step task by asking the user to choose the next action —
    /// "what would you like me to do next?", "how should I proceed?". In an unattended run this
    /// stalls forever: no one answers.
    ///
    /// Deliberately high-precision to avoid re-driving a legitimately-finished task:
    /// - Only strong "you choose my next step" interrogatives count. A polite completion closer
    ///   ("let me know if you'd like anything else") is NOT here — that follows a finished task.
    /// - `asksForPermission` ("should I delete…?") is a SPECIFIC confirmation the safety layer
    ///   already gates; it is not a whole-task deferral and is intentionally excluded.
    static func defersNextStepToUser(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        return deferralPhrases.contains { normalized.contains($0) }
    }

    private static let deferralPhrases = [
        "what would you like me to do next",
        "what would you like me to do?",
        "what do you want me to do next",
        "what do you want me to do?",
        "what should i do next",
        "what would you like to do next",
        "how would you like me to proceed",
        "how would you like to proceed",
        "how do you want me to proceed",
        "how should i proceed",
        "let me know how you'd like me to proceed",
        "let me know how you would like me to proceed",
        "let me know what you'd like me to do",
        "let me know what you would like me to do",
        "shall i proceed with"
    ]

    static func shouldSuppressStreamingPreview(for assistantText: String) -> Bool {
        let normalized = normalizedText(assistantText)
        guard canContainActionablePromise(normalized) else { return false }

        return containsFutureWorkPhrase(in: normalized)
            || containsUnresolvedFutureWorkStarter(in: normalized)
    }

    static func correctionPrompt(
        for correction: AgentSayCorrection,
        assistantText: String,
        userMessage: String
    ) -> String {
        switch correction {
        case .promisedWork:
            return promisedWorkCorrectionPrompt(assistantText: assistantText, userMessage: userMessage)
        case .deferralToUser:
            return deferralCorrectionPrompt(assistantText: assistantText, userMessage: userMessage)
        }
    }

    /// Back-compat overload for callers/tests that predate the typed correction.
    static func correctionPrompt(assistantText: String, userMessage: String) -> String {
        promisedWorkCorrectionPrompt(assistantText: assistantText, userMessage: userMessage)
    }

    private static func promisedWorkCorrectionPrompt(assistantText: String, userMessage: String) -> String {
        """
        Your previous response promised to perform work but did not return a QuillCode tool action.

        Original user request:
        \(userMessage)

        Previous response:
        \(assistantText)

        Return exactly one QuillCode JSON action now. If you intended to perform the promised work,
        return the appropriate {"type":"tool",...} action with complete arguments. If no tool is
        needed, return {"type":"say","text":"..."} with a direct final answer and no future-tense promise.
        If the evidence is already collected, immediately update and verify the final deliverable
        instead of merely announcing that the data is ready.
        """
    }

    /// The nudge for a task-abandoning deferral. It does NOT scold; it re-establishes that the run
    /// is autonomous and that continuing is the expectation. Crucially it leaves an escape hatch: a
    /// GENUINE blocker, stated specifically, is allowed — which is how a real question survives the
    /// retry (a specific blocker is not one of the deferral phrases, so it passes through).
    private static func deferralCorrectionPrompt(assistantText: String, userMessage: String) -> String {
        """
        You asked what to do next, but you are running this task autonomously — the user is not
        available to answer, so asking will stall the run. Do not ask the user to choose the next
        step.

        Original task:
        \(userMessage)

        Continue the task yourself using what you already know. Make a reasonable decision and act on
        it. Only if a step is genuinely blocked — a required credential is missing, or an action is
        destructive and truly needs confirmation — state the SPECIFIC blocker and exactly what you
        tried. Otherwise return exactly one QuillCode JSON tool action that makes progress now.
        """
    }

    private static func promisesExecutableWork(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        guard canContainActionablePromise(normalized) else { return false }

        return containsFutureWorkPhrase(in: normalized)
            || declaresReadinessToProceed(in: normalized)
            || declaresEvidenceReadyWithoutResult(in: normalized)
            || declaresImmediateWorkInProgress(in: normalized)
            || declaresUnfinishedNextStep(in: normalized)
    }

    /// Collecting the inputs is not completion when the run still owes synthesis or an artifact.
    /// Keep this exact and short so a real completion statement that goes on to name the verified
    /// deliverable is allowed through.
    private static func declaresEvidenceReadyWithoutResult(in normalizedText: String) -> Bool {
        let bareStatus = normalizedText.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "[](){}*_`#:.!-")
            )
        )
        return evidenceReadyStatuses.contains(bareStatus)
    }

    private static let evidenceReadyStatuses = [
        "i have all the data needed",
        "i have all the evidence needed",
        "i have all the information needed",
        "all required data is collected",
        "all required evidence is collected",
    ]

    /// A say that ENDS the turn by announcing the model is ABOUT to work rather than working — the
    /// verbose-planner stall a fast orchestrator falls into: after exploring the repo it wrote
    /// "I am fully prepared to proceed with the execution steps" and stopped, with no tool call.
    /// No "I'll…"/"Let's…" starter appears, so the promise lexicon misses it; the signal is the
    /// readiness-to-<act> phrase itself.
    ///
    /// Matched on the "ready/prepared/about + to + <act>" shape, so "the report is ready to send"
    /// (a completed result) does NOT fire — only readiness to PROCEED / BEGIN / EXECUTE / RUN /
    /// START / CONTINUE the task does.
    private static func declaresReadinessToProceed(in normalizedText: String) -> Bool {
        readinessToProceedPhrases.contains { normalizedText.contains($0) }
    }

    private static let readinessToProceedPhrases = [
        "ready to proceed",
        "prepared to proceed",
        "ready to begin",
        "prepared to begin",
        "ready to execute",
        "ready to run the",
        "ready to start",
        "ready to continue",
        "about to proceed",
        "about to begin",
        "about to run the",
        "will now proceed",
        "will now begin",
        "will now execute",
        "proceeding to run",
        "proceeding to execute"
    ]

    /// A terminal present-progress narration is the same stall as a future-tense promise when it
    /// says the work is happening "now" but emits no tool action. Keep this deliberately narrow:
    /// the clause must start with a concrete work gerund and end on the token "now", so completed
    /// observations such as "Reading the report now shows three gaps" remain valid final answers.
    private static func declaresImmediateWorkInProgress(in normalizedText: String) -> Bool {
        let bareStatus = normalizedText.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "[](){}*_`#:-")
            )
        )
        if bareInProgressStatuses.contains(bareStatus) {
            return true
        }
        let terminalClause = normalizedText
            .replacingOccurrences(
                of: #"[.!?]\s+"#,
                with: "\n",
                options: .regularExpression
            )
            .split(whereSeparator: \.isNewline)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if declaresShortTerminalProgress(terminalClause) {
            return true
        }
        let words = terminalClause.split(whereSeparator: { !$0.isLetter && $0 != "'" })
        guard words.last.map(String.init) == "now" else { return false }
        return immediateWorkGerunds.contains { gerund in
            terminalClause.hasPrefix("\(gerund) ")
                || terminalClause.hasPrefix("i'm \(gerund) ")
                || terminalClause.hasPrefix("i am \(gerund) ")
        }
    }

    /// Delegated workers sometimes end on a short status such as "Starting research on X" or
    /// "Continuing research". These are unambiguously progress reports, not completed findings.
    private static func declaresShortTerminalProgress(_ terminalClause: String) -> Bool {
        let words = terminalClause.split(whereSeparator: { !$0.isLetter && $0 != "'" })
        guard words.count <= 12 else { return false }
        guard terminalProgressGerunds.contains(where: { terminalClause.hasPrefix("\($0) ") }) else {
            return false
        }
        return containsWorkVerb(in: Substring(terminalClause))
    }

    private static let bareInProgressStatuses = [
        "analysis in progress",
        "research in progress",
        "task in progress",
        "work in progress",
    ]

    private static let immediateWorkGerunds = [
        "reading", "writing", "creating", "opening", "inspecting", "checking", "reviewing",
        "running", "fetching", "searching", "updating", "editing", "building", "testing",
        "starting", "continuing",
    ]

    private static let terminalProgressGerunds = ["starting", "continuing"]

    /// A terminal answer can describe unfinished work without future tense. Delegated research
    /// workers produced both of these live shapes and were incorrectly reported as complete:
    /// "Now I need Q2 ... to complete" and "Next: re-fetch the filing". Require both a narrow
    /// unfinished-work marker and a concrete work verb so completed handoff notes such as
    /// "the parent can merge these findings" remain valid.
    private static func declaresUnfinishedNextStep(in normalizedText: String) -> Bool {
        if normalizedText.ranges(of: "i need ").contains(where: { range in
            let remainder = normalizedText[range.upperBound...].prefix(120)
            return containsWorkVerb(in: remainder)
                && (remainder.contains(" to finish") || remainder.contains(" to complete"))
        }) {
            return true
        }

        if let terminalClause = normalizedText
            .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" || $0.isNewline })
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           terminalClause.contains(" next"),
           immediateWorkGerunds.contains(where: { terminalClause.hasPrefix("\($0) ") }) {
            return true
        }

        if remainingWorkStarters.contains(where: { starter in
            guard let range = normalizedText.range(of: starter) else { return false }
            return containsWorkVerb(in: normalizedText[range.upperBound...].prefix(96))
        }) {
            return true
        }

        return nextStepLabels.contains { label in
            ranges(of: label, in: normalizedText).contains { range in
                containsWorkVerb(in: normalizedText[range.upperBound...].prefix(96))
            }
        }
    }

    private static let remainingWorkStarters = [
        "now i need ",
        "i still need to ",
        "we still need to ",
        "still need to ",
    ]

    private static let nextStepLabels = [
        "next:",
        "next step:",
        "next steps:",
    ]

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
        !asksForPermission(text)
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
                && !isNegativePromise(text, after: range)
        }
    }

    /// Negation belongs to one promise clause, not the whole response. A status update can
    /// legitimately say "I will not retry the blocked browser" and then stall on "I will complete
    /// the research". Filtering the first starter locally preserves the refusal while allowing the
    /// later executable promise to be re-driven.
    private static func isNegativePromise(_ text: String, after range: Range<String.Index>) -> Bool {
        let remainder = trimmedText(after: range, in: text)
        return remainder == "not"
            || remainder.hasPrefix("not ")
            || remainder.hasPrefix("not\n")
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
        "let me",
        // Collaborative framing is the same stall in a different voice: "Let's design and run the
        // evaluation…" is a promise of work with no tool action. The trailing work-verb requirement
        // (containsWorkVerb) keeps a bare "Let's see …" final answer from firing.
        "let's",
        "let us"
    ]

    private static let unresolvedStarterPreviewCharacterLimit = 8

    private static let workVerbs: Set<String> = [
        "add", "analyze", "apply", "archive", "build", "chart", "check", "clean",
        "commit", "complete", "condense", "conduct", "convert", "create", "dedupe",
        "continue",
        "delete", "document", "download", "draft", "edit", "execute", "extract", "fetch",
        "finish", "fix", "flag", "highlight", "inspect", "install", "inventory",
        "investigate", "list", "maintain", "mark", "merge", "normalize", "open", "pull",
        "push", "read", "research", "review", "run", "save", "search", "standardize",
        "summarize", "sync", "test", "triage", "update", "validate", "verify", "write"
    ]
}
