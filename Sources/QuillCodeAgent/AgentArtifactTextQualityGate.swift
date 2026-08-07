import Foundation

/// Prevents a named prose deliverable from completing with serialized line-break escapes such as
/// `\n- item` in its visible text. Code fences and inline code are excluded because escape examples
/// are legitimate there. The runner first requests a natural rewrite, then can fall back to a
/// deterministic blank-field replacement when the model ignores that bounded correction.
enum AgentArtifactTextQualityGate {
    struct Correction: Equatable {
        var path: String
        var prompt: String
    }

    static func correction(
        userMessage: String,
        malformedPaths: Set<String>
    ) -> Correction? {
        let required = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        guard let path = malformedPaths.sorted().first(where: { malformed in
            required.contains(where: { AgentArtifactVerificationGate.pathsMatch($0, malformed) })
        }) else { return nil }

        return Correction(
            path: path,
            prompt: """
            The named text deliverable ./\(path) contains a literal escaped line break or tab in \
            visible prose. Rewrite that same file with real line breaks and clean formatting, \
            preserving its substantive content. Then read the corrected file back before finishing.
            """
        )
    }

    static func placeholderCorrection(
        userMessage: String,
        placeholderPaths: Set<String>
    ) -> Correction? {
        guard requestsPlaceholderFreeArtifact(in: userMessage) else { return nil }
        let required = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        guard let path = placeholderPaths.sorted().first(where: { candidate in
            required.contains(where: { AgentArtifactVerificationGate.pathsMatch($0, candidate) })
        }) else { return nil }

        return Correction(
            path: path,
            prompt: """
            The named text deliverable ./\(path) still contains a bracketed substitution or \
            fill-in token even though the user explicitly requested a placeholder-free artifact. \
            Rewrite that same file so prose reads naturally without tokens such as `[company]` or \
            `[their words]`. In reusable forms, use blank lines, empty cells, or checkboxes for \
            future-entry fields. Preserve the substantive content, then read the corrected file \
            back before finishing.
            """
        )
    }

    static func containsMalformedLiteralEscape(content: String, path: String) -> Bool {
        guard let prose = visibleProse(content: content, path: path) else { return false }
        let range = NSRange(prose.startIndex..., in: prose)
        return malformedEscapeRegex.firstMatch(in: prose, range: range) != nil
    }

    static func containsBracketedPlaceholder(content: String, path: String) -> Bool {
        guard let prose = visibleProse(content: content, path: path) else { return false }
        let range = NSRange(prose.startIndex..., in: prose)
        return bracketedFieldRegex.matches(in: prose, range: range).contains { match in
            guard let fieldRange = Range(match.range(at: 1), in: prose) else { return false }
            return isPlaceholderField(String(prose[fieldRange]))
        }
    }

    static func replacingBracketedPlaceholders(content: String, path: String) -> String? {
        guard textExtensions.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()
        ) else { return nil }

        var inFence = false
        var replacedAny = false
        let lines = content.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return line
            }
            guard !inFence else { return line }

            let mutable = NSMutableString(string: line)
            let fullRange = NSRange(location: 0, length: mutable.length)
            let inlineCodeRanges = inlineCodeRegex.matches(
                in: line,
                range: fullRange
            ).map(\.range)
            let replacements = bracketedFieldRegex.matches(in: line, range: fullRange).filter {
                match in
                guard !inlineCodeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      let fieldRange = Range(match.range(at: 1), in: line)
                else { return false }
                return isPlaceholderField(String(line[fieldRange]))
            }
            for match in replacements.reversed() {
                mutable.replaceCharacters(in: match.range, with: "________")
                replacedAny = true
            }
            return mutable as String
        }
        return replacedAny ? lines.joined(separator: "\n") : nil
    }

    private static func requestsPlaceholderFreeArtifact(in userMessage: String) -> Bool {
        let range = NSRange(userMessage.startIndex..., in: userMessage)
        return placeholderFreeRequestRegexes.contains {
            $0.firstMatch(in: userMessage, range: range) != nil
        }
    }

    private static func visibleProse(content: String, path: String) -> String? {
        guard textExtensions.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()
        ) else { return nil }

        var inFence = false
        var proseLines: [String] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            proseLines.append(removingInlineCode(from: line))
        }
        return proseLines.joined(separator: "\n")
    }

    private static func removingInlineCode(from line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        return inlineCodeRegex.stringByReplacingMatches(
            in: line,
            range: range,
            withTemplate: ""
        )
    }

    private static func isPlaceholderField(_ rawField: String) -> Bool {
        let field = rawField.trimmingCharacters(in: .whitespacesAndNewlines)
        if field.isEmpty || field.lowercased() == "x" {
            return false
        }
        if field.allSatisfy(\.isNumber) || field.hasPrefix("^") {
            return false
        }
        return true
    }

    private static let textExtensions: Set<String> = ["md", "markdown", "txt"]
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`[^`]*`"#)
    private static let malformedEscapeRegex = try! NSRegularExpression(
        pattern: #"\\[nrt](?=\s*(?:#{1,6}\s|[-*+>]\s|\d+[.)]\s|[A-Za-z]))"#
    )
    private static let bracketedFieldRegex = try! NSRegularExpression(
        pattern: #"\[([^\]\n]{0,120})\](?!\()"#
    )
    private static let placeholderFreeRequestRegexes = [
        try! NSRegularExpression(pattern: #"(?i)\bplaceholder[- ]free\b"#),
        try! NSRegularExpression(
            pattern: #"(?is)\bdo\s+not\s+leave\b.{0,60}\bbracketed\b.{0,60}\b(?:field|prompt|placeholder|token)"#
        ),
    ]
}
