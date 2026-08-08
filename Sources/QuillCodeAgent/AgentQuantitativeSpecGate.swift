import Foundation

/// F30 — word-budget adherence for tasks that name an explicit length.
///
/// Live failure: "Turn my notes into a 300-word Monday exec update…" produced 222 words on one
/// model and 185 on another — both content-complete, both treating the only quantitative spec in
/// the task as a vibe. No guard checked it: the deliverable existed (F23 satisfied) and cited
/// nothing (F29 silent). Same enforcement lesson as the other gates: an explicit number in the
/// task needs a mechanical check, not prompt hope.
///
/// Scope is deliberately tight: only an explicit whole-deliverable `N-word` / `N word(s)` phrase
/// arms the gate, only task-named `.md` deliverables are measured, and compliance is a generous
/// ±25% band. Per-item and maximum-only constraints are excluded because this gate measures the
/// complete artifact and cannot safely infer item boundaries.
enum AgentQuantitativeSpecGate {
    struct WordBudget: Equatable {
        var words: Int
        var minimum: Int { Int((Double(words) * 0.75).rounded(.down)) }
        var maximum: Int { Int((Double(words) * 1.25).rounded(.up)) }
    }

    /// An explicit whole-deliverable word-count phrase in the request ("300-word", "300 words").
    /// Bounded to 50–20000 so figures like "3 words" in prose or huge IDs never arm the gate.
    static func wordBudget(in userMessage: String) -> WordBudget? {
        let pattern = #"\b(\d{2,5})[-\s]words?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: userMessage,
                range: NSRange(userMessage.startIndex..., in: userMessage)
              ),
              let range = Range(match.range(at: 1), in: userMessage),
              let words = Int(userMessage[range]),
              (50...20_000).contains(words)
        else { return nil }

        // "Each note under 120 words" is not a 120-word artifact. Applying the global ±25% gate
        // there destroys valid repeated-item output. Maximum-only budgets also cannot use this
        // symmetric target without inventing a minimum that the user never requested.
        let sentenceRange = sentenceRange(containing: match.range, in: userMessage)
        let sentence = String(userMessage[sentenceRange]).lowercased()
        let localOrMaximumPatterns = [
            #"\b(?:each|every)\b[^.!?\n]{0,100}\b\d{2,5}[-\s]words?\b"#,
            #"\b\d{2,5}[-\s]words?\b[^.!?\n]{0,60}\bper\b"#,
            #"\b(?:under|at\s+most|no\s+more\s+than|not\s+more\s+than|max(?:imum)?|up\s+to|less\s+than)\b[^.!?\n]{0,60}\b\d{2,5}[-\s]words?\b"#,
            #"\b\d{2,5}[-\s]words?\b[^.!?\n]{0,30}\b(?:or\s+less|maximum|max)\b"#,
        ]
        if localOrMaximumPatterns.contains(where: { matches($0, in: sentence) }) {
            return nil
        }
        return WordBudget(words: words)
    }

    private static func sentenceRange(containing range: NSRange, in text: String) -> Range<String.Index> {
        let fullRange = Range(range, in: text) ?? text.startIndex..<text.endIndex
        let boundaries: Set<Character> = [".", "!", "?", "\n"]
        let start = text[..<fullRange.lowerBound].lastIndex(where: { boundaries.contains($0) })
            .map { text.index(after: $0) } ?? text.startIndex
        let end = text[fullRange.upperBound...].firstIndex(where: { boundaries.contains($0) })
            ?? text.endIndex
        return start..<end
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    struct Violation: Equatable {
        var deliverable: String
        var actual: Int
        var budget: WordBudget
    }

    /// Measures each existing task-named `.md` deliverable against the budget. Non-markdown
    /// deliverables (CSV, PDF…) are data, not prose — never measured.
    static func violations(
        userMessage: String,
        workspaceRoot: URL
    ) -> [Violation] {
        guard let budget = wordBudget(in: userMessage) else { return [] }
        var found: [Violation] = []
        for name in AgentDeliverableGate.requiredDeliverables(in: userMessage)
        where name.lowercased().hasSuffix(".md") {
            let url = workspaceRoot.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let actual = wordCount(of: text)
            if actual < budget.minimum || actual > budget.maximum {
                found.append(Violation(deliverable: name, actual: actual, budget: budget))
            }
        }
        return found
    }

    static func correctionPrompt(violations: [Violation]) -> String {
        let details = violations
            .map { "\($0.deliverable) has \($0.actual) words but the task asks for about \($0.budget.words)" }
            .joined(separator: "; ")
        return """
        Length check: \(details). Rewrite the deliverable to within 25% of the requested length \
        (\(violations[0].budget.minimum)–\(violations[0].budget.maximum) words) using host.file.write \
        with the full revised content — expand with substance from the source material (or tighten), \
        never with filler. Then give your final answer. If the source material cannot support the \
        requested length, write exactly what is missing.
        """
    }

    static func lengthNotice(violations: [Violation]) -> String {
        let details = violations
            .map { "\($0.deliverable): \($0.actual) words vs ~\($0.budget.words) requested" }
            .joined(separator: "; ")
        return "⚠ Length: the deliverable does not meet the requested word count (\(details))."
    }
}
