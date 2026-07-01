import Foundation
import QuillCodeCore

enum ProjectInstructionSemanticConflictDetector {
    static func claims(for instructions: [ProjectInstruction]) -> [ProjectInstructionSemanticClaim] {
        var claims: [ProjectInstructionSemanticClaim] = []
        var seen = Set<String>()

        for instruction in instructions {
            let content = searchableText(instruction.content)
            for rule in ProjectInstructionSemanticRule.allCases {
                guard let match = rule.firstMatch(in: instruction.content, searchableContent: content) else {
                    continue
                }
                let key = "\(instruction.path)|\(rule.intent.id)|\(rule.polarity.rawValue)"
                guard seen.insert(key).inserted else { continue }
                claims.append(ProjectInstructionSemanticClaim(
                    instruction: instruction,
                    intent: rule.intent,
                    polarity: rule.polarity,
                    match: match
                ))
            }
        }

        return claims
    }

    static func searchableText(_ text: String) -> String {
        let lowered = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return " " + lowered
            .split(separator: " ")
            .joined(separator: " ") + " "
    }
}

struct ProjectInstructionSemanticClaim: Sendable, Hashable {
    var instruction: ProjectInstruction
    var intent: ProjectInstructionSemanticIntent
    var polarity: ProjectInstructionSemanticPolarity
    var match: ProjectInstructionSemanticMatch
}

struct ProjectInstructionSemanticMatch: Sendable, Hashable {
    var lineNumber: Int
    var excerpt: String
}

enum ProjectInstructionSemanticIntent: String, Sendable {
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

enum ProjectInstructionSemanticPolarity: String, Sendable {
    case require
    case avoid

    var detailLabel: String {
        switch self {
        case .require: "require"
        case .avoid: "avoid"
        }
    }

    func referenceRole(for intent: ProjectInstructionSemanticIntent) -> String {
        switch self {
        case .require: "requires \(intent.displayName.lowercased())"
        case .avoid: "avoids \(intent.displayName.lowercased())"
        }
    }

    func suggestedAction(for intent: ProjectInstructionSemanticIntent) -> String {
        switch self {
        case .require:
            "Keep, soften, or remove this requirement for \(intent.displayName.lowercased())."
        case .avoid:
            "Keep, soften, or remove this avoidance rule for \(intent.displayName.lowercased())."
        }
    }
}

private struct ProjectInstructionSemanticRule: Sendable, Hashable {
    var intent: ProjectInstructionSemanticIntent
    var polarity: ProjectInstructionSemanticPolarity
    var phrases: [String]

    func firstMatch(in content: String, searchableContent: String) -> ProjectInstructionSemanticMatch? {
        let lines = content
            .components(separatedBy: .newlines)
            .enumerated()
        for (index, line) in lines {
            let searchableLine = ProjectInstructionSemanticConflictDetector.searchableText(line)
            if phrases.contains(where: { searchableLine.contains(" \($0) ") }) {
                return ProjectInstructionSemanticMatch(
                    lineNumber: index + 1,
                    excerpt: line.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        guard let phrase = phrases.first(where: { searchableContent.contains(" \($0) ") }) else {
            return nil
        }
        return ProjectInstructionSemanticMatch(
            lineNumber: 1,
            excerpt: content
                .split(whereSeparator: \.isNewline)
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? phrase
        )
    }

    static let allCases: [ProjectInstructionSemanticRule] = [
        ProjectInstructionSemanticRule(
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
        ProjectInstructionSemanticRule(
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
        ProjectInstructionSemanticRule(
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
        ProjectInstructionSemanticRule(
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
        ProjectInstructionSemanticRule(
            intent: .commits,
            polarity: .require,
            phrases: [
                "always commit",
                "must commit",
                "create a commit",
                "make a commit"
            ]
        ),
        ProjectInstructionSemanticRule(
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
        ProjectInstructionSemanticRule(
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
        ProjectInstructionSemanticRule(
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
