import Foundation

/// Adds one bounded semantic audit before an explicitly source-only artifact can complete. Static
/// prompting is not enough for weaker models: the audit runs after the draft exists, when the model
/// can compare its exact claims with the source material already present in the conversation.
enum AgentSourceGroundingGate {
    static func correction(
        userMessage: String,
        writtenPaths: Set<String>,
        auditedPaths: Set<String>
    ) -> AgentArtifactTextQualityGate.Correction? {
        guard requestsSourceOnlyGrounding(in: userMessage) else { return nil }
        let required = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        guard let path = writtenPaths.sorted().first(where: { written in
            !auditedPaths.contains(written)
                && required.contains(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, written)
                })
        }) else { return nil }

        return .init(
            path: path,
            prompt: """
            The request explicitly limits facts to supplied sources. Audit the current ./\(path) \
            against the user request and every source read in this run before completing. Remove \
            or label unknown every unsupported factual assertion, recommendation framed as a \
            requirement, or commitment. Check especially for invented payment or compensation, \
            meeting duration, sales intent, confidentiality, deadlines, delivery timing, and \
            follow-up rules. Preserve exact source quantities, qualifiers, and attribution.

            Return exactly one tool action now: if any correction is needed, rewrite ./\(path); \
            otherwise read ./\(path) back. Do not return a final answer yet.
            """
        )
    }

    private static func requestsSourceOnlyGrounding(in userMessage: String) -> Bool {
        let range = NSRange(userMessage.startIndex..., in: userMessage)
        return sourceOnlyRequestRegexes.contains {
            $0.firstMatch(in: userMessage, range: range) != nil
        }
    }

    private static let sourceOnlyRequestRegexes = [
        try! NSRegularExpression(
            pattern: #"(?is)\b(?:use|rely)\s+only\s+(?:on\s+)?(?:facts|information|data|evidence|content).{0,100}\b(?:sources?|inputs?|files?)\b"#
        ),
        try! NSRegularExpression(
            pattern: #"(?is)\bonly\s+use\b.{0,100}\b(?:supplied|provided|attached)\s+(?:sources?|inputs?|files?|data)\b"#
        ),
    ]
}
