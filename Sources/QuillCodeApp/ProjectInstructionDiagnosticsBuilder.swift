import Foundation
import QuillCodeCore

enum ProjectInstructionDiagnosticsBuilder {
    static func diagnostics(for instructions: [ProjectInstruction]) -> [ProjectInstructionDiagnostic] {
        duplicateScopeDiagnostics(for: instructions)
            + nestedOverrideDiagnostics(for: instructions)
            + semanticConflictDiagnostics(for: instructions)
    }

    private static func duplicateScopeDiagnostics(
        for instructions: [ProjectInstruction]
    ) -> [ProjectInstructionDiagnostic] {
        orderedScopeGroups(for: instructions).compactMap { scopePath, scopedInstructions in
            guard scopedInstructions.count > 1 else { return nil }
            return ProjectInstructionDiagnostic(
                id: "instruction-duplicate-scope-\(normalizedID(scopePath))",
                title: "Shared instruction scope",
                detail: "\(ProjectInstruction.scopeLabel(for: scopePath)): \(pathList(scopedInstructions))",
                statusLabel: ProjectInstructionDiagnosticStatusLabel.review,
                sourceReferences: scopedInstructions.map {
                    ProjectInstructionDiagnosticReferenceBuilder.reference(
                        for: $0,
                        role: "same scope",
                        suggestedAction: "Merge duplicate scope guidance or remove the redundant source."
                    )
                },
                resolutionHint: "Keep one clear source of guidance for this scope, or merge the duplicated rules."
            )
        }
    }

    private static func nestedOverrideDiagnostics(
        for instructions: [ProjectInstruction]
    ) -> [ProjectInstructionDiagnostic] {
        orderedScopeGroups(for: instructions).compactMap { scopePath, scopedInstructions in
            guard scopePath != "." else { return nil }
            let broaderInstructions = instructions.filter { isBroaderScope($0.scopePath, than: scopePath) }
            guard !broaderInstructions.isEmpty else { return nil }
            if let overlapDiagnostic = nestedOverlapDiagnostic(
                scopePath: scopePath,
                scopedInstructions: scopedInstructions,
                broaderInstructions: broaderInstructions
            ) {
                return overlapDiagnostic
            }
            return explicitNestedOverrideDiagnostic(
                scopePath: scopePath,
                scopedInstructions: scopedInstructions,
                broaderInstructions: broaderInstructions
            )
        }
    }

    private static func nestedOverlapDiagnostic(
        scopePath: String,
        scopedInstructions: [ProjectInstruction],
        broaderInstructions: [ProjectInstruction]
    ) -> ProjectInstructionDiagnostic? {
        let broaderLines = broaderInstructionLines(broaderInstructions)
        guard !broaderLines.isEmpty else { return nil }

        var references: [ProjectInstructionDiagnosticSourceReference] = []
        var seenNestedLines = Set<String>()
        var seenBroaderLines = Set<String>()

        for instruction in scopedInstructions {
            for line in meaningfulInstructionLines(instruction.content) {
                guard let broaderLine = broaderLines[line.normalized] else { continue }
                let nestedKey = "\(instruction.path):\(line.number)"
                guard seenNestedLines.insert(nestedKey).inserted else { continue }
                references.append(ProjectInstructionDiagnosticSourceReference(
                    path: instruction.path,
                    lineNumber: line.number,
                    role: ProjectInstructionDiagnosticReferenceRole.repeatedNestedGuidance,
                    excerpt: line.text,
                    suggestedAction: "Remove the repeated broad line from this nested source."
                ))

                let broaderKey = "\(broaderLine.path):\(broaderLine.number)"
                if seenBroaderLines.insert(broaderKey).inserted {
                    references.append(ProjectInstructionDiagnosticSourceReference(
                        path: broaderLine.path,
                        lineNumber: broaderLine.number,
                        role: ProjectInstructionDiagnosticReferenceRole.broaderGuidance,
                        excerpt: broaderLine.text,
                        suggestedAction: "Keep this guidance in the broader source."
                    ))
                }
            }
        }

        guard references.contains(where: {
            $0.role == ProjectInstructionDiagnosticReferenceRole.repeatedNestedGuidance
        }) else {
            return nil
        }

        let detail = [
            ProjectInstruction.scopeLabel(for: scopePath),
            "repeats broader guidance in \(pathList(scopedInstructions));",
            "broader source \(pathList(broaderInstructions)) already applies"
        ].joined(separator: " ")
        return ProjectInstructionDiagnostic(
            id: "instruction-nested-overlap-\(normalizedID(scopePath))",
            title: "Nested instruction overlap",
            detail: detail,
            statusLabel: ProjectInstructionDiagnosticStatusLabel.scope,
            sourceReferences: references,
            resolutionHint: "Keep broad guidance in the broadest applicable file and leave nested files for scoped additions."
        )
    }

    private static func explicitNestedOverrideDiagnostic(
        scopePath: String,
        scopedInstructions: [ProjectInstruction],
        broaderInstructions: [ProjectInstruction]
    ) -> ProjectInstructionDiagnostic? {
        let scopedOverrides = scopedInstructions.filter { containsExplicitOverrideLanguage($0.content) }
        guard !scopedOverrides.isEmpty else { return nil }
        let detail = [
            ProjectInstruction.scopeLabel(for: scopePath),
            "from \(pathList(scopedOverrides))",
            "explicitly references overriding broader guidance in \(pathList(broaderInstructions))"
        ].joined(separator: " ")

        return ProjectInstructionDiagnostic(
            id: "instruction-nested-override-\(normalizedID(scopePath))",
            title: "Nested instruction override",
            detail: detail,
            statusLabel: ProjectInstructionDiagnosticStatusLabel.scope,
            sourceReferences: scopedOverrides.map {
                ProjectInstructionDiagnosticReferenceBuilder.reference(
                    for: $0,
                    role: ProjectInstructionDiagnosticReferenceRole.nestedOverride,
                    suggestedAction: "Clarify whether this nested rule intentionally overrides broader guidance."
                )
            } + broaderInstructions.map {
                ProjectInstructionDiagnosticReferenceBuilder.reference(
                    for: $0,
                    role: ProjectInstructionDiagnosticReferenceRole.broaderGuidance,
                    suggestedAction: "Clarify how this broader rule should interact with nested guidance."
                )
            },
            resolutionHint: "State the override explicitly or edit the nested rule so it extends broader guidance."
        )
    }

    private static func semanticConflictDiagnostics(
        for instructions: [ProjectInstruction]
    ) -> [ProjectInstructionDiagnostic] {
        let claims = ProjectInstructionSemanticConflictDetector.claims(for: instructions)
        var diagnostics: [ProjectInstructionDiagnostic] = []
        var seenIDs = Set<String>()

        for firstIndex in claims.indices {
            let first = claims[firstIndex]
            for second in claims[(firstIndex + 1)...] {
                guard first.intent == second.intent,
                      first.polarity != second.polarity,
                      scopesOverlap(first.instruction.scopePath, second.instruction.scopePath) else {
                    continue
                }

                let id = semanticConflictID(first, second)
                guard seenIDs.insert(id).inserted else { continue }
                let displayName = first.intent.displayName
                let detail = [
                    "\(displayName): \(first.instruction.path) says \(first.polarity.detailLabel);",
                    "\(second.instruction.path) says \(second.polarity.detailLabel)"
                ].joined(separator: " ")
                let resolutionHint = [
                    "Choose one intent for \(displayName.lowercased()) guidance",
                    "and edit the conflicting lines so they agree."
                ].joined(separator: " ")

                diagnostics.append(ProjectInstructionDiagnostic(
                    id: id,
                    title: "Conflicting instruction intent",
                    detail: detail,
                    statusLabel: ProjectInstructionDiagnosticStatusLabel.conflict,
                    sourceReferences: [
                        ProjectInstructionDiagnosticReferenceBuilder.reference(
                            for: first.instruction,
                            match: first.match,
                            role: first.polarity.referenceRole(for: first.intent),
                            suggestedAction: first.polarity.suggestedAction(for: first.intent)
                        ),
                        ProjectInstructionDiagnosticReferenceBuilder.reference(
                            for: second.instruction,
                            match: second.match,
                            role: second.polarity.referenceRole(for: second.intent),
                            suggestedAction: second.polarity.suggestedAction(for: second.intent)
                        )
                    ],
                    resolutionHint: resolutionHint
                ))
            }
        }

        return diagnostics
    }

    private static func orderedScopeGroups(
        for instructions: [ProjectInstruction]
    ) -> [(scopePath: String, instructions: [ProjectInstruction])] {
        var order: [String] = []
        var grouped: [String: [ProjectInstruction]] = [:]

        for instruction in instructions {
            if grouped[instruction.scopePath] == nil {
                order.append(instruction.scopePath)
            }
            grouped[instruction.scopePath, default: []].append(instruction)
        }

        return order.map { scopePath in
            (scopePath: scopePath, instructions: grouped[scopePath] ?? [])
        }
    }

    private static func isBroaderScope(_ candidate: String, than scopePath: String) -> Bool {
        if candidate == "." {
            return scopePath != "."
        }
        return scopePath.hasPrefix(candidate + "/")
    }

    private static func scopesOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || isBroaderScope(lhs, than: rhs) || isBroaderScope(rhs, than: lhs)
    }

    private static func broaderInstructionLines(
        _ instructions: [ProjectInstruction]
    ) -> [String: InstructionLine] {
        var lines: [String: InstructionLine] = [:]
        for instruction in instructions {
            for line in meaningfulInstructionLines(instruction.content) where lines[line.normalized] == nil {
                lines[line.normalized] = InstructionLine(
                    path: instruction.path,
                    number: line.number,
                    text: line.text,
                    normalized: line.normalized
                )
            }
        }
        return lines
    }

    private static func meaningfulInstructionLines(_ content: String) -> [InstructionLine] {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .enumerated()
            .compactMap { index, rawLine -> InstructionLine? in
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = normalizedInstructionLine(trimmed)
                guard isMeaningfulRepeatedGuidance(normalized) else { return nil }
                return InstructionLine(
                    path: "",
                    number: index + 1,
                    text: rawLine,
                    normalized: normalized
                )
            }
    }

    private static func normalizedInstructionLine(_ line: String) -> String {
        line
            .lowercased()
            .replacingOccurrences(of: #"^[\-\*\d\.\)\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .;:"))
    }

    private static func isMeaningfulRepeatedGuidance(_ normalizedLine: String) -> Bool {
        normalizedLine.count >= 16
            && normalizedLine.split(separator: " ").count >= 3
    }

    private static func containsExplicitOverrideLanguage(_ content: String) -> Bool {
        let normalized = content.lowercased()
        return [
            "override broader",
            "overrides broader",
            "ignore broader",
            "ignore parent",
            "ignore root",
            "supersede broader",
            "supersedes broader",
            "instead of broader",
            "instead of parent",
            "do not follow broader",
            "do not follow parent"
        ].contains { normalized.contains($0) }
    }

    private static func pathList(_ instructions: [ProjectInstruction]) -> String {
        instructions.map(\.path).joined(separator: ", ")
    }

    private static func semanticConflictID(
        _ first: ProjectInstructionSemanticClaim,
        _ second: ProjectInstructionSemanticClaim
    ) -> String {
        [
            "instruction-semantic-conflict",
            first.intent.id,
            normalizedSemanticID(first.instruction.path),
            normalizedSemanticID(second.instruction.path)
        ].joined(separator: "-")
    }

    private static func normalizedID(_ scopePath: String) -> String {
        scopePath == "." ? "root" : scopePath.replacingOccurrences(of: "/", with: "-")
    }

    private static func normalizedSemanticID(_ scopePath: String) -> String {
        let normalized = scopePath
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty || scopePath == "." ? "root" : normalized
    }

}

enum ProjectInstructionDiagnosticReferenceRole {
    static let broaderGuidance = "broader guidance"
    static let nestedOverride = "nested override"
    static let repeatedNestedGuidance = "repeated nested guidance"
}

private struct InstructionLine: Sendable, Hashable {
    var path: String
    var number: Int
    var text: String
    var normalized: String
}
