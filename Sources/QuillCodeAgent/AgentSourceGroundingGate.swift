import Foundation

/// Adds one bounded semantic audit before an explicitly source-only artifact can complete. Static
/// prompting is not enough for weaker models: the audit runs after the draft exists, when the model
/// can compare its exact claims with the source material already present in the conversation.
enum AgentSourceGroundingGate {
    static func correction(
        userMessage: String,
        writtenPaths: Set<String>,
        auditCounts: [String: Int]
    ) -> AgentArtifactTextQualityGate.Correction? {
        guard requestsSourceOnlyGrounding(in: userMessage) else { return nil }
        let required = AgentDeliverableGate.requiredDeliverables(in: userMessage).sorted()
        guard let path = required.first(where: { requiredPath in
            let path = AgentArtifactVerificationGate.normalizedPath(requiredPath)
            guard writtenPaths.contains(where: {
                AgentArtifactVerificationGate.pathsMatch(path, $0)
            }) else { return false }
            return auditCounts[path, default: 0] == 0
        }).map(AgentArtifactVerificationGate.normalizedPath) else { return nil }

        return .init(
            path: path,
            prompt: """
            The request explicitly limits facts to supplied sources. Audit every line of the \
            current ./\(path), including headings, subject \
            lines, templates, checklists, and example messages, against the user request and every \
            source read in this run before completing. Remove or label unknown every unsupported \
            factual assertion, recommendation framed as a requirement, or commitment. Check \
            especially for invented payment or compensation, meeting duration, sales intent, \
            confidentiality, deadlines, date ranges, delivery timing, scheduling promises, and \
            follow-up rules. Do not leave an unsupported claim in reusable copy merely because \
            the same topic is labeled unknown elsewhere. Preserve exact source quantities, \
            qualifiers, and attribution.

            Return exactly one tool action now: if any correction is needed, rewrite ./\(path); \
            otherwise read ./\(path) back. Do not return a final answer yet.
            """
        )
    }

    static func unsupportedSensitiveClaimPath(
        userMessage: String,
        unsupportedPaths: Set<String>
    ) -> String? {
        guard requestsSourceOnlyGrounding(in: userMessage) else { return nil }
        let required = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        return unsupportedPaths.sorted().first(where: { candidate in
            required.contains(where: { AgentArtifactVerificationGate.pathsMatch($0, candidate) })
        })
    }

    static func containsUnsupportedSensitiveClaim(
        content: String,
        path: String,
        sourceText: String
    ) -> Bool {
        unsupportedLineIndexes(content: content, path: path, sourceText: sourceText).isEmpty == false
    }

    static func removingUnsupportedSensitiveClaims(
        content: String,
        path: String,
        sourceText: String
    ) -> String? {
        let unsupported = unsupportedLineIndexes(
            content: content,
            path: path,
            sourceText: sourceText
        )
        guard !unsupported.isEmpty else { return nil }
        let repaired = content.components(separatedBy: "\n").enumerated().compactMap { index, line in
            unsupported.contains(index) ? nil : line
        }.joined(separator: "\n")
        return preservingNonemptyMarkdownBody(repaired, path: path)
    }

    static func requestsSourceOnlyGrounding(in userMessage: String) -> Bool {
        let range = NSRange(userMessage.startIndex..., in: userMessage)
        return sourceOnlyRequestRegexes.contains {
            $0.firstMatch(in: userMessage, range: range) != nil
        }
    }

    private static func unsupportedLineIndexes(
        content: String,
        path: String,
        sourceText: String
    ) -> Set<Int> {
        guard textExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else {
            return []
        }

        var unsupported = Set<Int>()
        var inFence = false
        for (index, line) in content.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence, !explicitlyMarksUnknown(line) else { continue }
            let prose = inlineCodeRegex.stringByReplacingMatches(
                in: line,
                range: NSRange(line.startIndex..., in: line),
                withTemplate: ""
            )
            let proseRange = NSRange(prose.startIndex..., in: prose)
            let hasUnsupportedEventDuration = eventDurationContextRegex.firstMatch(
                in: prose,
                range: proseRange
            ) != nil && containsUnsupportedMatch(
                for: durationRegex,
                in: prose,
                sourceText: sourceText
            )
            if hasUnsupportedEventDuration || sensitiveClaimRegexes.contains(where: {
                containsUnsupportedMatch(for: $0, in: prose, sourceText: sourceText)
            }) {
                unsupported.insert(index)
            }
        }
        return unsupported
    }

    private static func containsUnsupportedMatch(
        for regex: NSRegularExpression,
        in line: String,
        sourceText: String
    ) -> Bool {
        let lineRange = NSRange(line.startIndex..., in: line)
        let sourceRange = NSRange(sourceText.startIndex..., in: sourceText)
        let groundedClaims = Set(regex.matches(in: sourceText, range: sourceRange).compactMap {
            Range($0.range, in: sourceText).map { canonicalClaim(String(sourceText[$0])) }
        })
        return regex.matches(in: line, range: lineRange).contains { match in
            guard let range = Range(match.range, in: line) else { return false }
            return !groundedClaims.contains(canonicalClaim(String(line[range])))
        }
    }

    private static func explicitlyMarksUnknown(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return unknownQualifierRegex.firstMatch(in: line, range: range) != nil
    }

    private static func canonicalClaim(_ claim: String) -> String {
        var value = claim.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        value = value.replacingOccurrences(
            of: #"(?<=\d)\s*-\s*(?=[a-z])"#,
            with: " ",
            options: .regularExpression
        )
        for (plural, singular) in [
            ("minutes", "minute"), ("hours", "hour"),
            ("days", "day"), ("weeks", "week"),
        ] {
            value = value.replacingOccurrences(
                of: "\\b\(plural)\\b",
                with: singular,
                options: .regularExpression
            )
        }
        return value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preservingNonemptyMarkdownBody(_ content: String, path: String) -> String {
        guard markdownExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else {
            return content
        }
        let nonemptyLines = content.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !nonemptyLines.isEmpty, nonemptyLines.allSatisfy({ line in
            let range = NSRange(line.startIndex..., in: line)
            return markdownHeadingRegex.firstMatch(in: line, range: range) != nil
        }) else { return content }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\nDetails are unknown from the supplied sources.\n"
    }

    private static let sourceOnlyRequestRegexes = [
        AgentRegexCompiler.compile(
            pattern: #"(?is)\b(?:use|rely)\s+only\s+(?:on\s+)?(?:facts|information|data|evidence|content).{0,100}\b(?:sources?|inputs?|files?)\b"#
        ),
        AgentRegexCompiler.compile(
            pattern: #"(?is)\bonly\s+use\b.{0,100}\b(?:supplied|provided|attached)\s+(?:sources?|inputs?|files?|data)\b"#
        ),
    ]

    private static let textExtensions: Set<String> = [
        "csv", "html", "htm", "json", "md", "markdown", "rst", "text", "tsv", "txt", "xml", "yaml", "yml",
    ]
    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let markdownHeadingRegex = AgentRegexCompiler.compile(
        pattern: #"^\s{0,3}#{1,6}(?:\s+|$)"#
    )

    private static let sensitiveClaimRegexes = [
        AgentRegexCompiler.compile(#"(?i)\bnot\s+selling\b"#),
        AgentRegexCompiler.compile(#"(?i)\bnot\s+(?:a\s+)?sales\s+(?:call|pitch)\b"#),
        AgentRegexCompiler.compile(#"(?i)\bno\s+(?:sales\s+)?pitch\b"#),
        AgentRegexCompiler.compile(#"(?i)\bresearch\s+only\b"#),
        AgentRegexCompiler.compile(
            pattern: #"(?i)\b(?:paid|compensated)(?:\s+[\w$-]+){0,3}\s+(?:interview|call|conversation|session)\b"#
        ),
        AgentRegexCompiler.compile(#"(?i)\b(?:confidential|confidentiality|under\s+(?:an?\s+)?nda)\b"#),
        AgentRegexCompiler.compile(
            pattern: #"(?i)\b(?:next|within)\s+(?:the\s+)?(?:couple|few|\d+)\s+(?:business\s+)?(?:hours?|days?|weeks?)\b"#
        ),
        AgentRegexCompiler.compile(#"(?i)\bquick\s+(?:call|chat|conversation|meeting)\b"#),
        AgentRegexCompiler.compile(
            pattern: #"(?i)\b(?:we|i)(?:'ll|\s+will|\s+can)\s+(?:send|schedule|follow\s+up|work\s+around|confirm|provide|share)\b"#
        ),
    ]
    private static let durationRegex = AgentRegexCompiler.compile(
        pattern: #"(?i)\b\d+(?:\s*[-–—]\s*\d+)?\s*[-–—]?\s*(?:minutes?|hours?|days?|weeks?)\b"#
    )
    private static let eventDurationContextRegex = AgentRegexCompiler.compile(
        pattern: #"(?i)(?:\b\d+(?:\s*[-–—]\s*\d+)?\s*[-–—]?\s*(?:minutes?|hours?|days?|weeks?)\b.{0,40}\b(?:interview|call|conversation|session|meeting)\b|\b(?:interview|call|conversation|session|meeting)\b.{0,40}\b\d+(?:\s*[-–—]\s*\d+)?\s*[-–—]?\s*(?:minutes?|hours?|days?|weeks?)\b)"#
    )

    private static let unknownQualifierRegex = AgentRegexCompiler.compile(
        pattern: #"(?i)\b(?:unknown|not\s+(?:stated|established|supplied|provided)|to\s+be\s+confirmed)\b"#
    )
    private static let inlineCodeRegex = AgentRegexCompiler.compile(#"`[^`\n]+`"#)
}
