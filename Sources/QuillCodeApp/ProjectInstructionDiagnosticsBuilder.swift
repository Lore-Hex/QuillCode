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
                statusLabel: "review",
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
            let detail = [
                ProjectInstruction.scopeLabel(for: scopePath),
                "from \(pathList(scopedInstructions))",
                "may override \(pathList(broaderInstructions))"
            ].joined(separator: " ")

            return ProjectInstructionDiagnostic(
                id: "instruction-nested-override-\(normalizedID(scopePath))",
                title: "Nested instruction override",
                detail: detail,
                statusLabel: "scope",
                sourceReferences: scopedInstructions.map {
                    ProjectInstructionDiagnosticReferenceBuilder.reference(
                        for: $0,
                        role: "nested scope",
                        suggestedAction: "Clarify whether this nested rule intentionally overrides broader guidance."
                    )
                } + broaderInstructions.map {
                    ProjectInstructionDiagnosticReferenceBuilder.reference(
                        for: $0,
                        role: "broader scope",
                        suggestedAction: "Clarify how this broader rule should interact with nested guidance."
                    )
                },
                resolutionHint: "State the override explicitly or merge the broader and nested rules."
            )
        }
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
                    statusLabel: "conflict",
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
