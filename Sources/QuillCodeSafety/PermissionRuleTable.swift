import Foundation

/// An ordered per-project permission rule table.
///
/// Evaluation is last-match-wins over the rule list: later rules override earlier ones,
/// so appending a rule always takes effect immediately. When no rule matches, `decision`
/// returns nil and the caller keeps its existing behavior.
public struct PermissionRuleTable: Sendable, Equatable {
    /// Upper bound on rules consulted per evaluation. The table and JSON file it is
    /// loaded from are untrusted input; together with the pattern/candidate size caps
    /// this bounds matching work per decision.
    public static let maxRuleCount = 256

    public private(set) var rules: [PermissionRule]

    public init(rules: [PermissionRule] = []) {
        // Keep the newest tail rules: last-match-wins means the tail has highest priority,
        // including hand-authored deny overrides in an oversized file.
        self.rules = Array(rules.suffix(Self.maxRuleCount))
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// Appends a rule. Because evaluation is last-match-wins, the new rule overrides any
    /// earlier rule it overlaps with. When the table is full, the oldest rule is dropped
    /// so a freshly taught rule is never silently ignored.
    public mutating func append(_ rule: PermissionRule) {
        rules.append(rule)
        if rules.count > Self.maxRuleCount {
            rules.removeFirst(rules.count - Self.maxRuleCount)
        }
    }

    /// Evaluates the table for a normalized subject. `resource` is what deny and ask
    /// rules match against. `allowResource` is what allow rules match against; nil means
    /// the call is not allow-scopable, so allow rules cannot match.
    public func decision(
        action: String,
        resource: String,
        allowResource: String?
    ) -> PermissionRuleDecision? {
        let candidates = PermissionRuleEvaluationCandidates(
            resource: resource,
            allowResource: allowResource
        )
        var result = PermissionRuleEvaluationResult()

        for rule in rules {
            let candidate = candidates.candidate(for: rule.decision)
            guard let value = candidate.value else {
                continue
            }

            switch rule.match {
            case .exact:
                if rule.action == action, rule.resource == value {
                    result.record(rule.decision)
                }
            case .pattern:
                evaluatePatternRule(rule, action: action, candidate: candidate, result: &result)
            }
        }

        return result.decision
    }

    /// Convenience for callers that treat allow and deny/ask resources identically. The
    /// production reviewer passes the subject's distinct `allowMatchResource`.
    public func decision(action: String, resource: String) -> PermissionRuleDecision? {
        decision(action: action, resource: resource, allowResource: resource)
    }

    private func evaluatePatternRule(
        _ rule: PermissionRule,
        action: String,
        candidate: PermissionRuleEvaluationCandidate,
        result: inout PermissionRuleEvaluationResult
    ) {
        guard let value = candidate.value,
              let actionPattern = PermissionWildcardPattern(rule.action),
              actionPattern.matches(action)
        else {
            return
        }

        if candidate.isOversized {
            result.recordSkippedWildcard(decision: rule.decision)
            return
        }

        guard let resourcePattern = PermissionWildcardPattern(rule.resource),
              resourcePattern.matches(value)
        else {
            return
        }
        result.record(rule.decision)
    }
}

private struct PermissionRuleEvaluationCandidates {
    private let denyAsk: PermissionRuleEvaluationCandidate
    private let allow: PermissionRuleEvaluationCandidate

    init(resource: String, allowResource: String?) {
        self.denyAsk = PermissionRuleEvaluationCandidate(value: resource)
        self.allow = PermissionRuleEvaluationCandidate(value: allowResource)
    }

    func candidate(for decision: PermissionRuleDecision) -> PermissionRuleEvaluationCandidate {
        decision == .allow ? allow : denyAsk
    }
}

private struct PermissionRuleEvaluationCandidate {
    var value: String?

    var isOversized: Bool {
        (value?.unicodeScalars.count ?? 0) > PermissionWildcardPattern.maxCandidateScalarCount
    }
}

private struct PermissionRuleEvaluationResult {
    private var lastMatch: PermissionRuleDecision?
    private var skippedDenyOrAskWildcard = false

    var decision: PermissionRuleDecision? {
        if skippedDenyOrAskWildcard {
            return lastMatch == .deny ? .deny : .ask
        }
        return lastMatch
    }

    mutating func record(_ decision: PermissionRuleDecision) {
        lastMatch = decision
    }

    mutating func recordSkippedWildcard(decision: PermissionRuleDecision) {
        // Padding past the wildcard cap must not dodge a deny/ask rule. A skipped allow
        // simply misses, which is already safe.
        if decision != .allow {
            skippedDenyOrAskWildcard = true
        }
    }
}
