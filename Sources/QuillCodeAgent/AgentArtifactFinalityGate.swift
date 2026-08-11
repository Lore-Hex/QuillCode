import Foundation

/// Prevents an internal research checkpoint from being mistaken for the requested final artifact.
/// The detector is deliberately limited to explicit document labels and completion disclaimers so
/// ordinary analysis of drafts, pending items, or next steps remains valid report content.
enum AgentArtifactFinalityGate {
    static func requestAllowsProvisionalArtifact(_ userMessage: String) -> Bool {
        matches(
            userMessage,
            patterns: [
                #"(?is)\b(?:create|write|produce|prepare|save|deliver|return)\s+(?:an?\s+|the\s+)?(?:initial\s+|rough\s+|working\s+|provisional\s+|interim\s+|checkpoint\s+)?draft\b"#,
                #"(?is)\b(?:deliverable|artifact|document|report|memo|proposal)\s+(?:may|can|should|must|will)\s+(?:be|remain)\s+(?:an?\s+)?(?:draft|provisional|interim|checkpoint|work[ -]in[ -]progress)\b"#,
                #"(?is)\b(?:save|write|create|produce)\s+(?:an?\s+|the\s+)?(?:research\s+)?checkpoint\b"#,
            ]
        )
    }

    static func containsProvisionalCompletionLanguage(content: String, path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard ["html", "md", "txt"].contains(ext) else { return false }

        let bounded = String(content.prefix(8_000))
        return matches(
            bounded,
            patterns: [
                #"(?im)^\s{0,3}#{1,6}\s+[^\n]{0,100}\b(?:checkpoint|work[ -]in[ -]progress|provisional|interim|incomplete|checkpoint\s+draft|draft\s+checkpoint)\b"#,
                #"(?im)^\s*(?:\*{0,2}|_{0,2})(?:status|completion\s+status)(?:\*{0,2}|_{0,2})\s*:\s*(?:\*{0,2}|_{0,2})?[^\n]{0,120}\b(?:checkpoint|work[ -]in[ -]progress|provisional|interim|incomplete|not\s+(?:yet\s+)?(?:final|complete|verified))\b"#,
                #"(?is)\b(?:this|the)\s+(?:artifact|deliverable|document|report|analysis|draft)\s+(?:is|remains)\s+(?:an?\s+)?(?:checkpoint|work[ -]in[ -]progress|provisional|interim|incomplete)\b"#,
                #"(?is)\b(?:this|the)\s+(?:artifact|deliverable|document|report|analysis|draft)\s+(?:will|must|needs?\s+to)\s+be\s+(?:rewritten|completed|finalized|updated|replaced)\b"#,
                #"(?is)\b(?:not\s+(?:yet\s+)?(?:final|complete|verified)|subject\s+to\s+(?:further\s+)?(?:verification|research|revision))\b"#,
                #"(?im)^\s*(?:[-*]\s*)?(?:next\s+pass|remaining\s+work|pending\s+(?:research|verification|validation|completion))\s*:"#,
            ]
        )
    }

    private static func matches(_ text: String, patterns: [String]) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: text, range: range) != nil
        }
    }
}
