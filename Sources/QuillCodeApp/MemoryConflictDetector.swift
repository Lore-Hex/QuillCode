import Foundation
import QuillCodeCore

enum MemoryConflictDetector {
    static func conflicts(
        notes: [MemoryNote],
        canEditProjectMemory: Bool,
        limit: Int = 6
    ) -> [MemoryConflictSurface] {
        let candidates = notes.flatMap(candidates(for:))
        let global = candidates.filter { $0.note.scope == .global }
        let project = candidates.filter { $0.note.scope == .project }
        var seen: Set<String> = []
        var conflicts: [MemoryConflictSurface] = []

        for globalCandidate in global {
            for projectCandidate in project where globalCandidate.conflicts(with: projectCandidate) {
                let key = "\(globalCandidate.note.id)|\(projectCandidate.note.id)|\(globalCandidate.subjectKey)"
                guard seen.insert(key).inserted else { continue }
                conflicts.append(
                    MemoryConflictSurface(
                        subject: globalCandidate.displaySubject,
                        global: globalCandidate.note,
                        project: projectCandidate.note,
                        canEditProjectMemory: canEditProjectMemory
                    )
                )
                if conflicts.count == limit { return conflicts }
            }
        }
        return conflicts
    }

    private static func candidates(for note: MemoryNote) -> [MemoryConflictCandidate] {
        statements(in: note.content).compactMap { statement in
            MemoryConflictCandidate(note: note, statement: statement)
        }
    }

    private static func statements(in content: String) -> [String] {
        content
            .split(whereSeparator: isStatementSeparator)
            .map { normalizeStatement(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func isStatementSeparator(_ character: Character) -> Bool {
        character.isNewline || ".!?;".contains(character)
    }

    private static func normalizeStatement(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-*•"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MemoryConflictCandidate: Sendable, Hashable {
    let note: MemoryNote
    let polarity: MemoryConflictPolarity
    let subjectKey: String
    let displaySubject: String

    init?(note: MemoryNote, statement: String) {
        guard let parsed = MemoryConflictPattern.parse(statement) else { return nil }
        self.note = note
        self.polarity = parsed.polarity
        self.subjectKey = parsed.subjectKey
        self.displaySubject = parsed.displaySubject
    }

    func conflicts(with other: MemoryConflictCandidate) -> Bool {
        subjectKey == other.subjectKey && polarity != other.polarity
    }
}

private enum MemoryConflictPolarity: Sendable, Hashable {
    case affirmative
    case negative
}

private struct MemoryConflictPattern: Sendable {
    let prefix: String
    let polarity: MemoryConflictPolarity

    static func parse(_ statement: String) -> (
        polarity: MemoryConflictPolarity,
        subjectKey: String,
        displaySubject: String
    )? {
        let normalized = statement.lowercased()
        guard let pattern = patterns.first(where: { normalized.hasPrefix($0.prefix) }) else {
            return nil
        }
        let rawSubject = String(statement.dropFirst(pattern.prefix.count))
        let subject = normalizeSubject(rawSubject)
        guard !subject.key.isEmpty else { return nil }
        return (pattern.polarity, subject.key, subject.display)
    }

    private static let patterns: [MemoryConflictPattern] = [
        .init(prefix: "should not use ", polarity: .negative),
        .init(prefix: "should not ", polarity: .negative),
        .init(prefix: "must not use ", polarity: .negative),
        .init(prefix: "must not ", polarity: .negative),
        .init(prefix: "do not use ", polarity: .negative),
        .init(prefix: "do not ", polarity: .negative),
        .init(prefix: "don't use ", polarity: .negative),
        .init(prefix: "don't ", polarity: .negative),
        .init(prefix: "never use ", polarity: .negative),
        .init(prefix: "never ", polarity: .negative),
        .init(prefix: "avoid using ", polarity: .negative),
        .init(prefix: "avoid ", polarity: .negative),
        .init(prefix: "always use ", polarity: .affirmative),
        .init(prefix: "should use ", polarity: .affirmative),
        .init(prefix: "must use ", polarity: .affirmative),
        .init(prefix: "prefer using ", polarity: .affirmative),
        .init(prefix: "prefer ", polarity: .affirmative),
        .init(prefix: "use ", polarity: .affirmative),
        .init(prefix: "keep using ", polarity: .affirmative),
        .init(prefix: "keep ", polarity: .affirmative)
    ]

    private static func normalizeSubject(_ value: String) -> (key: String, display: String) {
        let words = value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return (
            key: words.joined(separator: " "),
            display: words.joined(separator: " ")
        )
    }
}
