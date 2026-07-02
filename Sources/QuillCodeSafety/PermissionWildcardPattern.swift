import Foundation

/// Linear-time wildcard matcher for permission rule patterns.
///
/// Semantics:
/// - `*` matches any run of characters except `/`.
/// - `**` matches any run of characters including `/`.
/// - Everything else matches literally. There are no escapes, classes, or regexes.
///
/// The matcher is a bit-parallel NFA simulation over pattern positions. That makes
/// matching bounded and backtracking-free for untrusted permission-rule patterns.
public struct PermissionWildcardPattern: Sendable {
    public static let maxPatternScalarCount = 256
    public static let maxCandidateScalarCount = 4096

    private static let pathSeparator: Unicode.Scalar = "/"

    /// One bit per pattern state, plus the accept state as the highest bit.
    private let stateCount: Int
    private let wordCount: Int
    /// States holding `**`, which self-loop on every scalar.
    private let globstarMask: [UInt64]
    /// States holding `*`, which self-loop on every scalar except `/`.
    private let starMask: [UInt64]
    /// Per-scalar masks of literal states. Consuming that scalar advances those states by one.
    private let literalMasks: [Unicode.Scalar: [UInt64]]

    /// Nil when the pattern exceeds the size cap, so an untrusted oversized pattern never matches.
    public init?(_ pattern: String) {
        let scalars = Array(pattern.unicodeScalars)
        guard scalars.count <= Self.maxPatternScalarCount else { return nil }

        let tokens = Self.tokens(from: scalars)
        let stateCount = tokens.count + 1
        let wordCount = (stateCount + 63) / 64
        var globstarMask = [UInt64](repeating: 0, count: wordCount)
        var starMask = [UInt64](repeating: 0, count: wordCount)
        var literalMasks: [Unicode.Scalar: [UInt64]] = [:]

        for (state, token) in tokens.enumerated() {
            switch token {
            case .literal(let scalar):
                var mask = literalMasks[scalar] ?? [UInt64](repeating: 0, count: wordCount)
                mask[state >> 6] |= 1 << UInt64(state & 63)
                literalMasks[scalar] = mask
            case .star:
                starMask[state >> 6] |= 1 << UInt64(state & 63)
            case .globstar:
                globstarMask[state >> 6] |= 1 << UInt64(state & 63)
            }
        }

        self.stateCount = stateCount
        self.wordCount = wordCount
        self.globstarMask = globstarMask
        self.starMask = starMask
        self.literalMasks = literalMasks
    }

    public func matches(_ candidate: String) -> Bool {
        var active = [UInt64](repeating: 0, count: wordCount)
        active[0] = 1
        applyEpsilonClosure(&active)

        var next = [UInt64](repeating: 0, count: wordCount)
        for scalar in candidate.unicodeScalars {
            var anyActive: UInt64 = 0
            applyWildcardTransitions(from: active, scalar: scalar, into: &next)
            applyLiteralTransitions(from: active, scalar: scalar, into: &next)
            applyEpsilonClosure(&next)

            for word in 0..<wordCount {
                anyActive |= next[word]
            }
            guard anyActive != 0 else { return false }
            swap(&active, &next)
        }

        let acceptState = stateCount - 1
        return (active[acceptState >> 6] & (1 << UInt64(acceptState & 63))) != 0
    }

    private static func tokens(from scalars: [Unicode.Scalar]) -> [PermissionWildcardToken] {
        var tokens: [PermissionWildcardToken] = []
        tokens.reserveCapacity(scalars.count)
        var index = 0

        while index < scalars.count {
            if scalars[index] == "*" {
                let starCount = countStarRun(in: scalars, startingAt: &index)
                tokens.append(starCount >= 2 ? .globstar : .star)
            } else {
                tokens.append(.literal(scalars[index]))
                index += 1
            }
        }

        return tokens
    }

    private static func countStarRun(
        in scalars: [Unicode.Scalar],
        startingAt index: inout Int
    ) -> Int {
        var count = 0
        while index < scalars.count, scalars[index] == "*" {
            count += 1
            index += 1
        }
        return count
    }

    private func applyWildcardTransitions(
        from active: [UInt64],
        scalar: Unicode.Scalar,
        into next: inout [UInt64]
    ) {
        for word in 0..<wordCount {
            var value = active[word] & globstarMask[word]
            if scalar != Self.pathSeparator {
                value |= active[word] & starMask[word]
            }
            next[word] = value
        }
    }

    private func applyLiteralTransitions(
        from active: [UInt64],
        scalar: Unicode.Scalar,
        into next: inout [UInt64]
    ) {
        guard let literal = literalMasks[scalar] else { return }

        var carry: UInt64 = 0
        for word in 0..<wordCount {
            let advancing = active[word] & literal[word]
            next[word] |= (advancing << 1) | carry
            carry = advancing >> 63
        }
    }

    /// Epsilon closure: every active star state can also match empty, activating its successor.
    /// One shifted-OR pass suffices because token parsing collapses adjacent star runs.
    private func applyEpsilonClosure(_ states: inout [UInt64]) {
        var carry: UInt64 = 0
        for word in 0..<wordCount {
            let stars = states[word] & (starMask[word] | globstarMask[word])
            states[word] |= (stars << 1) | carry
            carry = stars >> 63
        }
    }
}

private enum PermissionWildcardToken {
    case literal(Unicode.Scalar)
    case star
    case globstar
}
