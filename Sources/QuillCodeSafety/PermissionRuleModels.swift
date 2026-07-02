import Foundation

/// The decision a persisted permission rule maps a matching action/resource pair to.
///
/// `allow` skips the approval ask, but never the static hard-deny safety floor. `deny`
/// blocks the call in every mode, including Auto. `ask` forces an approval gate even
/// where the mode would otherwise have auto-approved.
public enum PermissionRuleDecision: String, Codable, Sendable, CaseIterable {
    case allow
    case deny
    case ask

    /// The issue-mandated tie-break order (`allow > deny > ask`) for callers merging
    /// decisions from equally ranked sources. Within one table, evaluation is strictly
    /// last-match-wins.
    public static func strongest(
        _ lhs: PermissionRuleDecision,
        _ rhs: PermissionRuleDecision
    ) -> PermissionRuleDecision {
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

/// How a rule's `action` and `resource` strings are interpreted when matching.
///
/// Rules saved from an "always allow/deny" answer are exact so a command that happens
/// to contain `*`, like `rm *.log`, never silently becomes a wildcard. Hand-authored
/// rules default to pattern matching.
public enum PermissionRuleMatchKind: String, Codable, Sendable {
    case exact
    case pattern
}

/// One persisted permission rule.
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
        self.match = try container.decodeIfPresent(
            PermissionRuleMatchKind.self,
            forKey: .match
        ) ?? .pattern
        self.decision = try container.decode(PermissionRuleDecision.self, forKey: .decision)
    }

    /// Whether this rule matches the given normalized subject.
    public func matches(action candidateAction: String, resource candidateResource: String) -> Bool {
        switch match {
        case .exact:
            return action == candidateAction && resource == candidateResource
        case .pattern:
            guard let actionPattern = PermissionWildcardPattern(action),
                  actionPattern.matches(candidateAction),
                  let resourcePattern = PermissionWildcardPattern(resource)
            else {
                return false
            }
            return resourcePattern.matches(candidateResource)
        }
    }
}
