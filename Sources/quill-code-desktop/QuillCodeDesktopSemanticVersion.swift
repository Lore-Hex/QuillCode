import Foundation

struct QuillCodeDesktopSemanticVersion: Comparable, Equatable, Sendable {
    private var components: [UInt64]
    private var prerelease: [Identifier]?

    init?(_ value: String) {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        let withoutBuild = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let versionParts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numberParts = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
        let parsed = numberParts.compactMap { UInt64($0) }
        guard !numberParts.isEmpty,
              numberParts.count <= 4,
              numberParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              numberParts.allSatisfy({ $0.count == 1 || $0.first != "0" }),
              parsed.count == numberParts.count
        else {
            return nil
        }
        var normalizedComponents = parsed
        while normalizedComponents.count > 1 && normalizedComponents.last == 0 {
            normalizedComponents.removeLast()
        }
        components = normalizedComponents

        if versionParts.count == 2 {
            let identifiers = versionParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(Self.isIdentifierCharacter) })
            else {
                return nil
            }
            prerelease = identifiers.map(Identifier.init)
        } else {
            prerelease = nil
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (let left?, let right?):
            for (leftID, rightID) in zip(left, right) where leftID != rightID {
                return leftID < rightID
            }
            return left.count < right.count
        }
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-"
    }

    private enum Identifier: Equatable, Comparable, Sendable {
        case numeric(UInt64)
        case text(String)

        init(_ value: Substring) {
            if let number = UInt64(value), value.count == 1 || value.first != "0" {
                self = .numeric(number)
            } else {
                self = .text(String(value))
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.numeric(let left), .numeric(let right)):
                return left < right
            case (.numeric, .text):
                return true
            case (.text, .numeric):
                return false
            case (.text(let left), .text(let right)):
                return left < right
            }
        }
    }
}
