import Foundation

/// Detects an EVALUATION-result claim in the assistant's own words and extracts the specific figures
/// it cites, so the integrity scanner can check those figures against the run's tool output.
///
/// High-precision by construction, three ways: (1) the message must contain eval-result LANGUAGE
/// (pass^1, pass rate, reward, accuracy, "tasks passed", benchmark) — an incidental derived percentage
/// in ordinary coding prose is ignored; (2) only COLLISION-RESISTANT figures count — percentages
/// (`100%`) and pass-count ratios (`5/5`), never a bare decimal like `1.0` that shows up in version
/// strings; (3) the scanner treats the claim as backed if ANY cited figure appears in tool output, so
/// a legitimately-derived figure never reddens a real result.
public enum ResultFigureLexicon {
    /// A parsed result claim: the specific figures the assistant cited.
    public struct ResultClaim: Sendable, Hashable {
        public var figures: [String]
    }

    /// Eval-result vocabulary. Deliberately benchmark-specific (not a generic "passed"/"done") so this
    /// only engages for reported evaluation results.
    public static let resultLanguage: [String] = [
        "pass^1", "pass@1", "pass rate", "success rate", "passrate",
        "reward", "accuracy", "benchmark", "tasks passed", "tasks pass",
        "% pass", "pass^",
    ]

    /// Max assistant text scanned per message (claims live up top; keep the scan bounded).
    static let maxScan = 20_000

    /// The first assistant message that reads as a result claim, with its cited figures, or nil.
    public static func firstResultClaim(inAssistantMessagesOf thread: ChatThread) -> ResultClaim? {
        for message in thread.messages where message.role == .assistant {
            let raw = String(message.content.prefix(maxScan))
            let lowered = raw.lowercased()
            guard resultLanguage.contains(where: { lowered.contains($0) }) else { continue }
            let figures = extractFigures(from: raw)
            guard !figures.isEmpty else { continue }
            return ResultClaim(figures: figures)
        }
        return nil
    }

    /// Collision-resistant result figures: percentages and pass-count ratios, in first-seen order.
    static func extractFigures(from text: String) -> [String] {
        var figures: [String] = []
        for pattern in [percentPattern, ratioPattern] {
            for match in matches(of: pattern, in: text) {
                let normalized = match.replacingOccurrences(of: " ", with: "")
                if !figures.contains(normalized) { figures.append(normalized) }
            }
        }
        return figures
    }

    // `100%`, `80.5%` — 1-3 digit integer or decimal followed by `%`.
    private static let percentPattern = "\\b\\d{1,3}(?:\\.\\d+)?%"
    // `5/5`, `3 / 5` — a pass-count ratio (whitespace tolerated, normalized out).
    private static let ratioPattern = "\\b\\d{1,4}\\s*/\\s*\\d{1,4}\\b"

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, range: full).map { ns.substring(with: $0.range) }
    }
}
