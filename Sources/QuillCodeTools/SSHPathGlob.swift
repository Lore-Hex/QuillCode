import Foundation

enum SSHPathGlob {
    static func expand(path: String, maximumMatches: Int) -> [URL] {
        let components = URL(fileURLWithPath: path).pathComponents
        var candidates = [URL(fileURLWithPath: "/", isDirectory: true)]

        for component in components.dropFirst() {
            var next: [URL] = []
            for candidate in candidates {
                if containsWildcard(component) {
                    let children = immediateChildren(
                        of: candidate,
                        maximumEntries: min(4_096, max(256, maximumMatches * 32))
                    )
                    next.append(contentsOf: children.filter {
                        !$0.lastPathComponent.hasPrefix(".") || explicitlyMatchesLeadingDot(component)
                    }.filter {
                        wildcardMatch(pattern: component, candidate: $0.lastPathComponent)
                    })
                } else {
                    next.append(candidate.appendingPathComponent(component))
                }
                if next.count >= maximumMatches {
                    break
                }
            }
            candidates = Array(next.prefix(maximumMatches))
            if candidates.isEmpty { break }
        }
        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path < $1.path }
    }

    private static func containsWildcard(_ value: String) -> Bool {
        value.contains("*") || value.contains("?") || value.contains("[")
    }

    private static func explicitlyMatchesLeadingDot(_ pattern: String) -> Bool {
        guard let first = tokens(in: pattern).first else { return false }
        switch first {
        case .literal("."):
            return true
        case .characterClass(let characterClass):
            return characterClass.matches(".")
        case .anySequence, .anyCharacter, .literal:
            return false
        }
    }

    private static func immediateChildren(of directory: URL, maximumEntries: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) else { return [] }
        var children: [URL] = []
        while let child = enumerator.nextObject() as? URL, children.count < maximumEntries {
            children.append(child)
        }
        return children.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func wildcardMatch(pattern: String, candidate: String) -> Bool {
        let pattern = tokens(in: pattern)
        let candidate = Array(candidate)
        var previous = Array(repeating: false, count: candidate.count + 1)
        previous[0] = true

        for token in pattern {
            var current = Array(repeating: false, count: candidate.count + 1)
            if token == .anySequence {
                current[0] = previous[0]
                if !candidate.isEmpty {
                    for index in 1...candidate.count {
                        current[index] = previous[index] || current[index - 1]
                    }
                }
            } else {
                for index in candidate.indices where token.matches(candidate[index]) {
                    current[index + 1] = previous[index]
                }
            }
            previous = current
        }
        return previous[candidate.count]
    }

    private static func tokens(in pattern: String) -> [SSHPathGlobToken] {
        let characters = Array(pattern)
        var tokens: [SSHPathGlobToken] = []
        var index = 0
        while index < characters.count {
            switch characters[index] {
            case "*":
                if tokens.last != .anySequence {
                    tokens.append(.anySequence)
                }
            case "?":
                tokens.append(.anyCharacter)
            case "[":
                if let parsed = characterClass(in: characters, openingIndex: index) {
                    tokens.append(.characterClass(parsed.characterClass))
                    index = parsed.closingIndex
                } else {
                    tokens.append(.literal("["))
                }
            default:
                tokens.append(.literal(characters[index]))
            }
            index += 1
        }
        return tokens
    }

    private static func characterClass(
        in characters: [Character],
        openingIndex: Int
    ) -> (characterClass: SSHPathGlobCharacterClass, closingIndex: Int)? {
        let firstContentIndex = openingIndex + 1
        guard firstContentIndex < characters.count,
              let closingIndex = characters[(firstContentIndex)...].firstIndex(of: "]"),
              closingIndex > firstContentIndex
        else { return nil }

        var content = Array(characters[firstContentIndex..<closingIndex])
        let isNegated = content.first == "!" || content.first == "^"
        if isNegated { content.removeFirst() }
        guard !content.isEmpty else { return nil }

        var literals: Set<Character> = []
        var ranges: [ClosedRange<UInt32>] = []
        var contentIndex = 0
        while contentIndex < content.count {
            if contentIndex + 2 < content.count,
               content[contentIndex + 1] == "-",
               let lower = scalarValue(of: content[contentIndex]),
               let upper = scalarValue(of: content[contentIndex + 2]),
               lower <= upper {
                ranges.append(lower...upper)
                contentIndex += 3
            } else {
                literals.insert(content[contentIndex])
                contentIndex += 1
            }
        }
        return (
            SSHPathGlobCharacterClass(literals: literals, ranges: ranges, isNegated: isNegated),
            closingIndex
        )
    }

    fileprivate static func scalarValue(of character: Character) -> UInt32? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1 else { return nil }
        return scalars.first?.value
    }
}

private enum SSHPathGlobToken: Equatable {
    case anySequence
    case anyCharacter
    case literal(Character)
    case characterClass(SSHPathGlobCharacterClass)

    func matches(_ candidate: Character) -> Bool {
        switch self {
        case .anySequence:
            return false
        case .anyCharacter:
            return true
        case .literal(let expected):
            return expected == candidate
        case .characterClass(let characterClass):
            return characterClass.matches(candidate)
        }
    }
}

private struct SSHPathGlobCharacterClass: Equatable {
    var literals: Set<Character>
    var ranges: [ClosedRange<UInt32>]
    var isNegated: Bool

    func matches(_ candidate: Character) -> Bool {
        let inRange = SSHPathGlob.scalarValue(of: candidate).map { value in
            ranges.contains { $0.contains(value) }
        } ?? false
        let contains = literals.contains(candidate) || inRange
        return isNegated ? !contains : contains
    }
}
