import Foundation
import QuillCodeCore

struct ProjectInstructionDiagnostic: Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var statusLabel: String
}

enum ProjectInstructionDiagnosticsBuilder {
    static func diagnostics(for instructions: [ProjectInstruction]) -> [ProjectInstructionDiagnostic] {
        duplicateScopeDiagnostics(for: instructions)
            + nestedOverrideDiagnostics(for: instructions)
            + semanticConflictDiagnostics(for: instructions)
    }

    private static func duplicateScopeDiagnostics(for instructions: [ProjectInstruction]) -> [ProjectInstructionDiagnostic] {
        orderedScopeGroups(for: instructions).compactMap { scopePath, scopedInstructions in
            guard scopedInstructions.count > 1 else { return nil }
            return ProjectInstructionDiagnostic(
                id: "instruction-duplicate-scope-\(normalizedID(scopePath))",
                title: "Shared instruction scope",
                detail: "\(ProjectInstruction.scopeLabel(for: scopePath)): \(pathList(scopedInstructions))",
                statusLabel: "review"
            )
        }
    }

    private static func nestedOverrideDiagnostics(for instructions: [ProjectInstruction]) -> [ProjectInstructionDiagnostic] {
        orderedScopeGroups(for: instructions).compactMap { scopePath, scopedInstructions in
            guard scopePath != "." else { return nil }
            let broaderInstructions = instructions.filter { isBroaderScope($0.scopePath, than: scopePath) }
            guard !broaderInstructions.isEmpty else { return nil }

            return ProjectInstructionDiagnostic(
                id: "instruction-nested-override-\(normalizedID(scopePath))",
                title: "Nested instruction override",
                detail: "\(ProjectInstruction.scopeLabel(for: scopePath)) from \(pathList(scopedInstructions)) may override \(pathList(broaderInstructions))",
                statusLabel: "scope"
            )
        }
    }

    private static func semanticConflictDiagnostics(for instructions: [ProjectInstruction]) -> [ProjectInstructionDiagnostic] {
        let claims = semanticClaims(for: instructions)
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

                let id = "instruction-semantic-conflict-\(first.intent.id)-\(normalizedSemanticID(first.instruction.path))-\(normalizedSemanticID(second.instruction.path))"
                guard seenIDs.insert(id).inserted else { continue }

                diagnostics.append(ProjectInstructionDiagnostic(
                    id: id,
                    title: "Conflicting instruction intent",
                    detail: "\(first.intent.displayName): \(first.instruction.path) says \(first.polarity.detailLabel); \(second.instruction.path) says \(second.polarity.detailLabel)",
                    statusLabel: "conflict"
                ))
            }
        }

        return diagnostics
    }

    private static func semanticClaims(for instructions: [ProjectInstruction]) -> [SemanticClaim] {
        var claims: [SemanticClaim] = []
        var seen = Set<String>()

        for instruction in instructions {
            let content = searchableText(instruction.content)
            for rule in SemanticRule.allCases where rule.matches(content) {
                let key = "\(instruction.path)|\(rule.intent.id)|\(rule.polarity.rawValue)"
                guard seen.insert(key).inserted else { continue }
                claims.append(SemanticClaim(
                    instruction: instruction,
                    intent: rule.intent,
                    polarity: rule.polarity
                ))
            }
        }

        return claims
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

    private static func searchableText(_ text: String) -> String {
        let lowered = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return " " + lowered
            .split(separator: " ")
            .joined(separator: " ") + " "
    }
}

private struct SemanticClaim: Sendable, Hashable {
    var instruction: ProjectInstruction
    var intent: SemanticIntent
    var polarity: SemanticPolarity
}

private enum SemanticIntent: String, Sendable {
    case tests
    case formatter
    case commits
    case dependencies

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tests: "Tests"
        case .formatter: "Formatting"
        case .commits: "Commits"
        case .dependencies: "Dependencies"
        }
    }
}

private enum SemanticPolarity: String, Sendable {
    case require
    case avoid

    var detailLabel: String {
        switch self {
        case .require: "require"
        case .avoid: "avoid"
        }
    }
}

private struct SemanticRule: Sendable, Hashable {
    var intent: SemanticIntent
    var polarity: SemanticPolarity
    var phrases: [String]

    func matches(_ searchableText: String) -> Bool {
        phrases.contains { phrase in
            searchableText.contains(" \(phrase) ")
        }
    }

    static let allCases: [SemanticRule] = [
        SemanticRule(
            intent: .tests,
            polarity: .require,
            phrases: [
                "always run tests",
                "must run tests",
                "run tests before",
                "run tests after",
                "must write tests",
                "always write tests",
                "must add tests",
                "always add tests",
                "must include tests",
                "always include tests",
                "tests are required",
                "test coverage required"
            ]
        ),
        SemanticRule(
            intent: .tests,
            polarity: .avoid,
            phrases: [
                "never run tests",
                "do not run tests",
                "don t run tests",
                "skip tests",
                "avoid tests",
                "do not add tests",
                "don t add tests",
                "without tests",
                "tests are not required"
            ]
        ),
        SemanticRule(
            intent: .formatter,
            polarity: .require,
            phrases: [
                "always format",
                "must format",
                "run formatter",
                "run the formatter",
                "format before committing",
                "format all files"
            ]
        ),
        SemanticRule(
            intent: .formatter,
            polarity: .avoid,
            phrases: [
                "never format",
                "do not format",
                "don t format",
                "skip formatting",
                "avoid formatting"
            ]
        ),
        SemanticRule(
            intent: .commits,
            polarity: .require,
            phrases: [
                "always commit",
                "must commit",
                "create a commit",
                "make a commit"
            ]
        ),
        SemanticRule(
            intent: .commits,
            polarity: .avoid,
            phrases: [
                "never commit",
                "do not commit",
                "don t commit",
                "avoid committing",
                "no commits"
            ]
        ),
        SemanticRule(
            intent: .dependencies,
            polarity: .require,
            phrases: [
                "always add dependencies",
                "must add dependencies",
                "must install dependencies",
                "install required dependencies",
                "use required dependencies"
            ]
        ),
        SemanticRule(
            intent: .dependencies,
            polarity: .avoid,
            phrases: [
                "never add dependencies",
                "do not add dependencies",
                "don t add dependencies",
                "avoid dependencies",
                "no new dependencies"
            ]
        )
    ]
}
