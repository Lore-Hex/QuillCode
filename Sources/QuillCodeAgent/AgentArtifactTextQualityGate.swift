import Foundation

/// Prevents a named prose deliverable from completing with serialized line-break escapes such as
/// `\n- item` in its visible text. Code fences and inline code are excluded because escape examples
/// are legitimate there. The runner issues at most one correction per path.
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

    static func containsMalformedLiteralEscape(content: String, path: String) -> Bool {
        guard Self.textExtensions.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()
        ) else { return false }

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

        let prose = proseLines.joined(separator: "\n")
        let range = NSRange(prose.startIndex..., in: prose)
        return malformedEscapeRegex.firstMatch(in: prose, range: range) != nil
    }

    private static func removingInlineCode(from line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        return inlineCodeRegex.stringByReplacingMatches(
            in: line,
            range: range,
            withTemplate: ""
        )
    }

    private static let textExtensions: Set<String> = ["md", "markdown", "txt"]
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`[^`]*`"#)
    private static let malformedEscapeRegex = try! NSRegularExpression(
        pattern: #"\\[nrt](?=\s*(?:#{1,6}\s|[-*+>]\s|\d+[.)]\s|[A-Za-z]))"#
    )
}
