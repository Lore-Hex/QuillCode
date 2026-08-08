import Foundation

/// Prevents a named prose deliverable from completing with serialized line-break escapes such as
/// `\n- item` in its visible text. Code fences and inline code are excluded because escape examples
/// are legitimate there. The runner first requests a natural rewrite, then can fall back to a
/// deterministic formatting repair when the model ignores that bounded correction.
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

    static func enumeratedCountCorrection(
        userMessage: String,
        contradictoryPaths: Set<String>
    ) -> Correction? {
        let required = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        guard let path = contradictoryPaths.sorted().first(where: { candidate in
            required.contains(where: { AgentArtifactVerificationGate.pathsMatch($0, candidate) })
        }) else { return nil }

        return Correction(
            path: path,
            prompt: """
            The named text deliverable ./\(path) contains a stated item count that conflicts with \
            the source record IDs enumerated beside it. Reconcile every derived count against the \
            listed records, correct or remove unsupported analysis, then read the corrected file \
            back before finishing.
            """
        )
    }

    static func markdownCompletenessCorrection(
        userMessage: String,
        incompletePaths: Set<String>
    ) -> Correction? {
        let required = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        guard let path = incompletePaths.sorted().first(where: { candidate in
            required.contains(where: { AgentArtifactVerificationGate.pathsMatch($0, candidate) })
        }) else { return nil }

        return Correction(
            path: path,
            prompt: """
            The named Markdown deliverable ./\(path) contains one or more headings with no \
            substantive content. Rewrite that same file so every retained section is complete, or \
            remove headings that are not needed. Preserve grounded content and then read the \
            corrected file back before finishing.
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

    static func containsContradictoryEnumeratedCount(content: String, path: String) -> Bool {
        guard let prose = visibleProse(content: content, path: path) else { return false }
        return prose.components(separatedBy: .newlines).contains {
            !enumeratedCountReplacements(in: $0).isEmpty
        }
    }

    static func emptyMarkdownSectionTitles(content: String, path: String) -> [String] {
        markdownSections(content: content, path: path)
            .filter(\.isEmpty)
            .map(\.title)
    }

    static func replacingMalformedLiteralEscapes(content: String, path: String) -> String? {
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
            let replacements = malformedEscapeRunRegex.matches(in: line, range: fullRange).filter {
                match in
                !inlineCodeRanges.contains(where: {
                    NSIntersectionRange($0, match.range).length > 0
                })
            }
            for match in replacements.reversed() {
                let raw = mutable.substring(with: match.range)
                let decoded = raw
                    .replacingOccurrences(of: "\\r\\n", with: "\n")
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\r", with: "\n")
                    .replacingOccurrences(of: "\\t", with: "\t")
                mutable.replaceCharacters(in: match.range, with: decoded)
                replacedAny = true
            }
            return mutable as String
        }
        return replacedAny ? lines.joined(separator: "\n") : nil
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

    static func replacingContradictoryEnumeratedCounts(content: String, path: String) -> String? {
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
            let inlineCodeRanges = inlineCodeRegex.matches(in: line, range: fullRange).map(\.range)
            let replacements = enumeratedCountReplacements(in: line).filter { replacement in
                !inlineCodeRanges.contains(where: {
                    NSIntersectionRange($0, replacement.matchRange).length > 0
                })
            }
            for replacement in replacements.reversed() {
                mutable.replaceCharacters(in: replacement.countRange, with: replacement.value)
                replacedAny = true
            }
            return mutable as String
        }
        return replacedAny ? lines.joined(separator: "\n") : nil
    }

    static func removingEmptyMarkdownSections(content: String, path: String) -> String? {
        let emptySections = markdownSections(content: content, path: path).filter(\.isEmpty)
        guard !emptySections.isEmpty else { return nil }

        let removedLineIndexes = Set(emptySections.map(\.lineIndex))
        let lines = content.components(separatedBy: "\n")
        return lines.enumerated().compactMap { index, line in
            removedLineIndexes.contains(index) ? nil : line
        }.joined(separator: "\n")
    }

    private struct MarkdownSection {
        var lineIndex: Int
        var level: Int
        var title: String
        var isEmpty: Bool
    }

    private static func markdownSections(content: String, path: String) -> [MarkdownSection] {
        let markdownExtensions: Set<String> = ["md", "markdown"]
        guard markdownExtensions.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()
        ) else { return [] }

        let lines = content.components(separatedBy: "\n")
        var headings: [(lineIndex: Int, level: Int, title: String)] = []
        var fenceDelimiterIndexes = Set<Int>()
        var inFence = false
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fenceDelimiterIndexes.insert(index)
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }

            let range = NSRange(line.startIndex..., in: line)
            guard let match = markdownHeadingRegex.firstMatch(in: line, range: range),
                  let markerRange = Range(match.range(at: 1), in: line),
                  let titleRange = Range(match.range(at: 2), in: line)
            else { continue }
            var title = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
            title = markdownClosingHashesRegex.stringByReplacingMatches(
                in: title,
                range: NSRange(title.startIndex..., in: title),
                withTemplate: ""
            )
            headings.append((index, line[markerRange].count, title))
        }

        let headingIndexes = Set(headings.map(\.lineIndex))
        return headings.enumerated().map { headingOffset, heading in
            let end = headings.dropFirst(headingOffset + 1).first(where: {
                $0.level <= heading.level
            })?.lineIndex ?? lines.count
            let hasSubstantiveContent = lines.indices.contains(where: { index in
                guard index > heading.lineIndex, index < end,
                      !headingIndexes.contains(index),
                      !fenceDelimiterIndexes.contains(index)
                else { return false }
                return !lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
            return MarkdownSection(
                lineIndex: heading.lineIndex,
                level: heading.level,
                title: heading.title,
                isEmpty: !hasSubstantiveContent
            )
        }
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

    private static func enumeratedCountReplacements(
        in line: String
    ) -> [(matchRange: NSRange, countRange: NSRange, value: String)] {
        let range = NSRange(line.startIndex..., in: line)
        return enumeratedCountRegex.matches(in: line, range: range).compactMap { match in
            guard let declaredRange = Range(match.range(at: 1), in: line),
                  let declaredCount = Int(line[declaredRange]),
                  let identifiersRange = Range(match.range(at: 2), in: line)
            else { return nil }
            let identifiers = line[identifiersRange].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard identifiers.count >= 2,
                  identifiers.allSatisfy({ identifier in
                    let identifierRange = NSRange(identifier.startIndex..., in: identifier)
                    return recordIdentifierRegex.firstMatch(
                        in: identifier,
                        range: identifierRange
                    )?.range == identifierRange
                  }),
                  declaredCount != identifiers.count
            else { return nil }
            return (match.range, match.range(at: 1), String(identifiers.count))
        }
    }

    private static let textExtensions: Set<String> = ["md", "markdown", "txt"]
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`[^`]*`"#)
    private static let malformedEscapeRegex = try! NSRegularExpression(
        pattern: #"\\[nrt](?=\s*(?:#{1,6}\s|[-*+>]\s|\d+[.)]\s|[A-Za-z]))"#
    )
    private static let malformedEscapeRunRegex = try! NSRegularExpression(
        pattern: #"(?:\\[nrt])+(?=\s*(?:#{1,6}\s|[-*+>]\s|\d+[.)]\s|[A-Za-z]))"#
    )
    private static let bracketedFieldRegex = try! NSRegularExpression(
        pattern: #"\[([^\]\n]{0,120})\](?!\()"#
    )
    private static let enumeratedCountRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(\d+)\s+(?:records?|items?|accounts?|entries?|rows?|cases?)\s*\(([^()\n]+)\)"#
    )
    private static let recordIdentifierRegex = try! NSRegularExpression(
        pattern: #"(?i)^[a-z][a-z0-9_-]*\d+[a-z0-9_-]*$"#
    )
    private static let markdownHeadingRegex = try! NSRegularExpression(
        pattern: #"^\s{0,3}(#{1,6})[ \t]+(.+?)\s*$"#
    )
    private static let markdownClosingHashesRegex = try! NSRegularExpression(
        pattern: #"\s+#+\s*$"#
    )
    private static let placeholderFreeRequestRegexes = [
        try! NSRegularExpression(pattern: #"(?i)\bplaceholder[- ]free\b"#),
        try! NSRegularExpression(
            pattern: #"(?is)\bdo\s+not\s+leave\b.{0,60}\bbracketed\b.{0,60}\b(?:field|prompt|placeholder|token)"#
        ),
    ]
}
