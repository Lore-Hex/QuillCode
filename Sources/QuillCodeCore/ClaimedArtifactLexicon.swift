import Foundation

/// Detects a claim, in the assistant's OWN words, of having PRODUCED a specific file — "wrote X",
/// "created X", "saved to X", "outputs written to X and Y" — and extracts the file paths it names.
/// The integrity scanner cross-checks each claimed path against the run's real file-mutation tool
/// calls and tool output; a file the assistant says it wrote that NO tool ever wrote, patched, ran, or
/// named is a fabricated artifact (observed live: an agent that wrote a `clean.py` script, never ran
/// it, then reported "outputs written to data/sales_clean.csv and findings.md" — neither of which any
/// tool created).
///
/// High-precision by construction, three ways:
/// 1. Only PAST / PERFECT creation verbs anchor a claim ("wrote", "created", "written to"). A future
///    "I will write findings.md" or "let me create X" is a plan, not a claim, and is guarded out by a
///    modal/future lead-in check on the words just before the verb.
/// 2. Only tokens that read as a real file — a basename with an extension, optionally with directory
///    components — are captured. "wrote the handler" or "created a new endpoint" never fires.
/// 3. Capture stops at the first word that is neither a path nor a short list connector, so
///    "created Foo.swift by reading Bar.swift and Baz.swift" claims only `Foo.swift`.
public enum ClaimedArtifactLexicon {
    /// A parsed artifact claim: the file paths the assistant said it produced, first-seen order,
    /// original case (so the reason string reads back exactly what the model wrote).
    public struct ArtifactClaim: Sendable, Hashable {
        public var paths: [String]
        public init(paths: [String]) { self.paths = paths }
    }

    /// Max assistant text scanned per message (claims live up top; keep the scan bounded and linear).
    static let maxScan = 20_000
    /// Max characters consumed after a creation verb while gathering the claimed-path list.
    static let captureWindow = 140
    /// Max claimed paths harvested from a single verb occurrence (a runaway-list backstop).
    static let maxPathsPerVerb = 8

    /// Past / perfect creation verbs. Longer multi-word forms come FIRST so "written to" wins over the
    /// bare "written" at the same position (both are fine — paths dedupe — but the longer match skips
    /// the "to" connector cleanly). Present-tense forms ("write", "create", "save") are deliberately
    /// absent: they read as intent, not completion.
    static let creationVerbs: [String] = [
        "written out to", "output written to", "outputs written to", "wrote out to",
        "written to", "saved to", "wrote to", "saved out to", "written into", "saved into",
        "wrote", "created", "saved", "generated", "produced", "written", "regenerated",
    ]

    /// Words allowed BETWEEN a creation verb and its path, or between sibling paths in a list, without
    /// breaking the claim. Anything else ends the capture. Lowercased.
    static let connectors: Set<String> = [
        "to", "the", "file", "files", "a", "an", "new", "at", "into", "in", "out",
        "and", "both", "as", "well", "results", "result", "output", "outputs", "them",
        "updated", "final", "cleaned", "two", "three", "all",
    ]

    /// Modal / future lead-ins that turn a nearby verb into a PLAN rather than a completed action. If
    /// any appears in the short window immediately before the verb, the occurrence is skipped.
    static let futureMarkers: [String] = [
        "will ", "'ll ", "going to ", "gonna ", "let me ", "plan to ", "planning to ",
        "need to ", "want to ", "about to ", "should ", "would ", "intend to ", "next i",
    ]

    /// Merged claim across ALL assistant messages: every distinct file path the assistant said it
    /// produced. The scanner checks each against the run's real artifacts and reports the first one
    /// nothing backs, so collecting them all (backing is a whole-run property) is correct.
    public static func mergedClaim(inAssistantMessagesOf thread: ChatThread) -> ArtifactClaim {
        var paths: [String] = []
        for message in thread.messages where message.role == .assistant {
            for path in claimedPaths(in: String(message.content.prefix(maxScan))) {
                if !paths.contains(path) { paths.append(path) }
            }
        }
        return ArtifactClaim(paths: paths)
    }

    /// The file paths a single message claims to have produced.
    static func claimedPaths(in text: String) -> [String] {
        let lower = text.lowercased()
        let chars = Array(text)
        let lowerChars = Array(lower)
        var found: [String] = []
        for verb in creationVerbs {
            var searchStart = lower.startIndex
            while let range = lower.range(of: verb, range: searchStart..<lower.endIndex) {
                searchStart = range.upperBound
                let verbStartOffset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let verbEndOffset = lower.distance(from: lower.startIndex, to: range.upperBound)
                // Word-boundary before the verb (so "rewrote"/"discovered" don't match "wrote"/…).
                if verbStartOffset > 0 {
                    let prev = lowerChars[verbStartOffset - 1]
                    if prev.isLetter || prev.isNumber { continue }
                }
                if hasFutureLeadIn(lowerChars, before: verbStartOffset) { continue }
                for path in gatherPaths(chars, from: verbEndOffset) where !found.contains(path) {
                    found.append(path)
                }
            }
        }
        return found
    }

    /// Whether a modal/future marker sits in the ~24-char window immediately before the verb.
    static func hasFutureLeadIn(_ lowerChars: [Character], before verbStart: Int) -> Bool {
        let windowStart = max(0, verbStart - 24)
        let window = String(lowerChars[windowStart..<verbStart])
        return futureMarkers.contains { window.contains($0) }
    }

    /// From just after a creation verb, walk tokens gathering claimed paths. Filler connectors are
    /// skipped; the first token that is neither a path nor a connector ends the list.
    static func gatherPaths(_ chars: [Character], from start: Int) -> [String] {
        let end = min(chars.count, start + captureWindow)
        var paths: [String] = []
        var i = start
        while i < end {
            // Skip separators between tokens.
            while i < end, chars[i] == " " || chars[i] == "\t" || chars[i] == "\n"
                || chars[i] == "\r" { i += 1 }
            guard i < end else { break }
            var j = i
            while j < end, !(chars[j] == " " || chars[j] == "\t" || chars[j] == "\n"
                || chars[j] == "\r") { j += 1 }
            let raw = String(chars[i..<j])
            i = j
            let token = trimWrapping(raw)
            if token.isEmpty { continue }
            if isPathToken(token) {
                paths.append(token)
                if paths.count >= maxPathsPerVerb { break }
                continue
            }
            if connectors.contains(token.lowercased()) { continue }
            break
        }
        return paths
    }

    /// Strip wrapping punctuation/quotes without touching a filename's internal dots and slashes. A
    /// trailing sentence period ("findings.md.") is removed because an extension never ends in `.`.
    static func trimWrapping(_ raw: String) -> String {
        let leading: Set<Character> = ["`", "'", "\"", "(", "[", "{", "*", "_", "“", "‘"]
        let trailing: Set<Character> = ["`", "'", "\"", ")", "]", "}", ",", ";", ":",
                                        "!", "?", ".", "*", "_", "”", "’"]
        var s = Substring(raw)
        while let f = s.first, leading.contains(f) { s = s.dropFirst() }
        while let l = s.last, trailing.contains(l) { s = s.dropLast() }
        return String(s)
    }

    /// Whether a token reads as a real file path: a basename with an extension (letters/digits, 1–6
    /// chars), optionally with directory components. Rejects dotted abbreviations ("e.g", "i.e") and
    /// single-letter stems so ordinary prose can't masquerade as a file.
    static func isPathToken(_ token: String) -> Bool {
        guard token.count <= 200 else { return false }
        guard let dot = token.lastIndex(of: ".") else { return false }
        let ext = token[token.index(after: dot)...]
        guard (1...6).contains(ext.count), ext.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return false
        }
        let afterSlash = token.split(separator: "/").last.map(String.init) ?? token
        guard let localDot = afterSlash.lastIndex(of: ".") else { return false }
        let stem = afterSlash[..<localDot]
        // A real filename stem, or a directory path — never a bare abbreviation like "e.g".
        let hasDir = token.contains("/")
        guard hasDir || stem.count >= 2 else { return false }
        guard stem.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." })
        else { return false }
        // Whole path may only contain path-safe characters.
        return token.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." || $0 == "/"
                || $0 == "~"
        }
    }
}
