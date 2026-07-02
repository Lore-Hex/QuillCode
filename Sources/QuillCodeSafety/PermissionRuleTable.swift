import Foundation

/// The decision a persisted permission rule maps a matching (action, resource) pair to.
///
/// `allow` skips the approval ASK (never the static hard-deny safety floor), `deny` blocks the
/// call in every mode (including Auto), and `ask` forces an approval gate even where the mode
/// would have auto-approved.
public enum PermissionRuleDecision: String, Codable, Sendable, CaseIterable {
    case allow
    case deny
    case ask

    /// The issue-mandated tie-break ordering (`allow > deny > ask`) for callers that must resolve
    /// two decisions of EQUAL precedence (e.g. merging tables from two equally-ranked sources).
    /// Within a single table this never applies — evaluation there is strictly last-match-wins.
    public static func strongest(_ lhs: PermissionRuleDecision, _ rhs: PermissionRuleDecision) -> PermissionRuleDecision {
        priorityOrder(lhs) >= priorityOrder(rhs) ? lhs : rhs
    }

    private static func priorityOrder(_ decision: PermissionRuleDecision) -> Int {
        switch decision {
        case .allow: return 3
        case .deny: return 2
        case .ask: return 1
        }
    }
}

/// How a rule's `action`/`resource` strings are interpreted when matching.
///
/// Rules saved from an "always allow/deny" answer are `.exact` so a command that happens to
/// contain `*` (e.g. `rm *.log`) never silently becomes a wildcard. Hand-authored rules default
/// to `.pattern`.
public enum PermissionRuleMatchKind: String, Codable, Sendable {
    case exact
    case pattern
}

/// One persisted permission rule: a pattern for the action (tool name), a pattern for the
/// resource (command string, normalized path, …) and the decision to take when both match.
public struct PermissionRule: Codable, Sendable, Hashable {
    public var action: String
    public var resource: String
    public var match: PermissionRuleMatchKind
    public var decision: PermissionRuleDecision

    public init(
        action: String,
        resource: String,
        match: PermissionRuleMatchKind = .pattern,
        decision: PermissionRuleDecision
    ) {
        self.action = action
        self.resource = resource
        self.match = match
        self.decision = decision
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case resource
        case match
        case decision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.action = try container.decode(String.self, forKey: .action)
        self.resource = try container.decode(String.self, forKey: .resource)
        // Absent match kind reads as `.pattern` (the hand-authored default); an unknown kind is a
        // decode error the tolerant store-level loader reports per-rule.
        self.match = try container.decodeIfPresent(PermissionRuleMatchKind.self, forKey: .match) ?? .pattern
        self.decision = try container.decode(PermissionRuleDecision.self, forKey: .decision)
    }

    /// Whether this rule matches the given normalized subject.
    public func matches(action candidateAction: String, resource candidateResource: String) -> Bool {
        switch match {
        case .exact:
            return action == candidateAction && resource == candidateResource
        case .pattern:
            guard let actionPattern = PermissionWildcardPattern(action),
                  actionPattern.matches(candidateAction)
            else {
                return false
            }
            guard let resourcePattern = PermissionWildcardPattern(resource) else { return false }
            return resourcePattern.matches(candidateResource)
        }
    }
}

/// An ordered per-project permission rule table.
///
/// Evaluation is LAST-MATCH-WINS over the rule list: later rules override earlier ones, so
/// appending a rule (the "always allow/deny" save path) always takes effect immediately. When no
/// rule matches, `decision` returns nil and the caller keeps its existing behavior (ask).
public struct PermissionRuleTable: Sendable, Equatable {
    /// Upper bound on rules consulted per evaluation. The table (and the JSON file it is loaded
    /// from) is untrusted input; together with the pattern/candidate size caps this bounds the
    /// total matching work per decision, so a hostile rules file cannot stall the gate.
    public static let maxRuleCount = 256

    public private(set) var rules: [PermissionRule]

    public init(rules: [PermissionRule] = []) {
        // Keep the NEWEST rules when over the cap, matching `append` and the last-match-wins
        // priority: the highest-priority (latest) rules — including hand-authored deny overrides at
        // the tail of an oversized file — must be the ones that survive, never silently dropped.
        self.rules = Array(rules.suffix(Self.maxRuleCount))
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// Appends a rule. Because evaluation is last-match-wins, the new rule overrides any earlier
    /// rule it overlaps with. When the table is full, the OLDEST rule is dropped so a fresh
    /// user-taught rule is never silently ignored.
    public mutating func append(_ rule: PermissionRule) {
        rules.append(rule)
        if rules.count > Self.maxRuleCount {
            rules.removeFirst(rules.count - Self.maxRuleCount)
        }
    }

    /// Evaluates the table for a normalized subject. `resource` is what DENY and ASK rules match
    /// against (broadening a block is safe, so it always has a resource). `allowResource` is what
    /// ALLOW rules match against — pass nil for a call that is not allow-scopable, and no allow
    /// rule will match (evaluation degrades to deny/ask only). Nil result = no opinion (ask as
    /// before).
    ///
    /// Oversized resources (longer than `PermissionWildcardPattern.maxCandidateScalarCount`) are
    /// never wildcard-matched. So that an oversized command can never DODGE a wildcard deny rule
    /// by padding itself past the cap, any evaluation that had to skip a wildcard rule for an
    /// otherwise action-matching rule degrades to the conservative answer: keep an exact deny if
    /// one matched, otherwise force `.ask`. Exact rules always compare (string equality is linear
    /// and safe at any length).
    public func decision(
        action: String,
        resource: String,
        allowResource: String?
    ) -> PermissionRuleDecision? {
        let denyAskOversized = resource.unicodeScalars.count > PermissionWildcardPattern.maxCandidateScalarCount
        let allowOversized = (allowResource?.unicodeScalars.count ?? 0) > PermissionWildcardPattern.maxCandidateScalarCount
        var lastMatch: PermissionRuleDecision?
        var skippedWildcardRule = false

        for rule in rules {
            // An allow rule may only match a call that is allow-scopable, against its allowResource;
            // deny/ask rules match the always-present resource.
            let candidate: String?
            let candidateOversized: Bool
            if rule.decision == .allow {
                candidate = allowResource
                candidateOversized = allowOversized
            } else {
                candidate = resource
                candidateOversized = denyAskOversized
            }
            guard let candidate else {
                continue
            }

            switch rule.match {
            case .exact:
                if rule.action == action, rule.resource == candidate {
                    lastMatch = rule.decision
                }
            case .pattern:
                guard let actionPattern = PermissionWildcardPattern(rule.action),
                      actionPattern.matches(action)
                else {
                    continue
                }
                if candidateOversized {
                    // Only a skipped DENY/ASK wildcard forces the conservative degrade; a skipped
                    // ALLOW wildcard simply does not match (missing an allow is already safe).
                    if rule.decision != .allow {
                        skippedWildcardRule = true
                    }
                    continue
                }
                guard let resourcePattern = PermissionWildcardPattern(rule.resource),
                      resourcePattern.matches(candidate)
                else {
                    continue
                }
                lastMatch = rule.decision
            }
        }

        if skippedWildcardRule {
            return lastMatch == .deny ? .deny : .ask
        }
        return lastMatch
    }

    /// Convenience for callers that treat allow and deny/ask resources identically (the tests and
    /// hand-authored table checks). Production paths pass the subject's `allowMatchResource`.
    public func decision(action: String, resource: String) -> PermissionRuleDecision? {
        decision(action: action, resource: resource, allowResource: resource)
    }
}

/// Linear-time wildcard matcher for permission rule patterns.
///
/// Semantics:
/// - `*` matches any run of characters EXCEPT `/` (it never crosses a path segment)
/// - `**` matches any run of characters including `/`
/// - everything else matches literally (no escapes, no character classes, no regex)
///
/// The matcher is a bit-parallel NFA simulation over pattern positions (Thompson construction for
/// globs, Shift-And style): one left-to-right pass over the candidate updating a bitset of active
/// pattern states with a constant number of word operations per character. That makes matching
/// O(candidate x pattern/64) with NO backtracking, so hostile patterns like `a*a*a*a*…` cannot
/// blow up the gate. Patterns are untrusted input (they come from a JSON file on disk): patterns
/// longer than `maxPatternScalarCount` are rejected (`init` returns nil, the rule never matches)
/// and candidates longer than `maxCandidateScalarCount` are the caller's signal to degrade
/// conservatively (see `PermissionRuleTable.decision`).
public struct PermissionWildcardPattern: Sendable {
    public static let maxPatternScalarCount = 256
    public static let maxCandidateScalarCount = 4096

    private static let pathSeparator: Unicode.Scalar = "/"

    /// One bit per pattern state (token index), plus the accept state as the highest bit.
    private let stateCount: Int
    private let wordCount: Int
    /// States holding `**` (self-loop on every scalar).
    private let globstarMask: [UInt64]
    /// States holding `*` (self-loop on every scalar except `/`).
    private let starMask: [UInt64]
    /// Per-scalar masks of literal states: consuming that scalar advances those states by one.
    private let literalMasks: [Unicode.Scalar: [UInt64]]

    /// Nil when the pattern exceeds the size cap (an untrusted oversized pattern never matches).
    public init?(_ pattern: String) {
        let scalars = Array(pattern.unicodeScalars)
        guard scalars.count <= Self.maxPatternScalarCount else { return nil }

        enum Token {
            case literal(Unicode.Scalar)
            case star
            case globstar
        }
        var tokens: [Token] = []
        tokens.reserveCapacity(scalars.count)
        var index = 0
        while index < scalars.count {
            if scalars[index] == "*" {
                var starCount = 0
                while index < scalars.count, scalars[index] == "*" {
                    starCount += 1
                    index += 1
                }
                // A run of 2+ stars collapses to one globstar; a single star stays segment-bound.
                // Collapsing also guarantees NO two adjacent star tokens, which the single-pass
                // epsilon closure below relies on.
                tokens.append(starCount >= 2 ? .globstar : .star)
            } else {
                tokens.append(.literal(scalars[index]))
                index += 1
            }
        }

        let stateCount = tokens.count + 1 // +1 accept state
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
        active[0] = 1 // initial state
        applyEpsilonClosure(&active)

        var next = [UInt64](repeating: 0, count: wordCount)
        for scalar in candidate.unicodeScalars {
            let literal = literalMasks[scalar]
            var anyActive: UInt64 = 0
            for word in 0..<wordCount {
                // Stars self-loop (segment-bound `*` refuses the path separator)…
                var value = active[word] & globstarMask[word]
                if scalar != Self.pathSeparator {
                    value |= active[word] & starMask[word]
                }
                next[word] = value
            }
            if let literal {
                // …and literal states matching this scalar advance by one.
                var carry: UInt64 = 0
                for word in 0..<wordCount {
                    let advancing = active[word] & literal[word]
                    next[word] |= (advancing << 1) | carry
                    carry = advancing >> 63
                }
            }
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

    /// Epsilon closure: every active star state can also match empty, activating its successor.
    /// One shifted-OR pass suffices because token parsing collapses star runs, so star states are
    /// never adjacent (a star's successor is always a literal or the accept state).
    private func applyEpsilonClosure(_ states: inout [UInt64]) {
        var carry: UInt64 = 0
        for word in 0..<wordCount {
            let stars = states[word] & (starMask[word] | globstarMask[word])
            states[word] |= (stars << 1) | carry
            carry = stars >> 63
        }
    }
}
