import Foundation
import QuillCodeCore

/// Supplies the persisted per-workspace permission rule table at review time. Implemented by the
/// persistence layer's file-backed store; reading fresh per review means an "always allow" saved
/// mid-run applies to the very next gate with no cache-invalidation seams.
public protocol PermissionRulesProviding: Sendable {
    func ruleTable(forWorkspaceRoot root: URL) -> PermissionRuleTable
}

/// A `PermissionRuleTable` that is the same for every workspace — the in-memory provider for
/// tests and single-workspace embedders.
public struct StaticPermissionRulesProvider: PermissionRulesProviding {
    public var table: PermissionRuleTable

    public init(table: PermissionRuleTable) {
        self.table = table
    }

    public func ruleTable(forWorkspaceRoot root: URL) -> PermissionRuleTable {
        table
    }
}

/// Composes the persisted permission rules with the existing mode + intent safety review, WITHOUT
/// replacing it: the table decides whether to skip or force the ASK; the safety floor stays.
///
/// Composition order per review:
/// 1. No workspace root, empty table, or no matching rule → the base reviewer's verdict,
///    unchanged (existing behavior: ask).
/// 2. A matching `deny` rule blocks the call in EVERY mode — including Auto, where the static
///    intent gate might otherwise have waved the call through.
/// 3. A matching `allow` rule skips the approval ASK in `.auto` and `.review` — but never the
///    static hard-deny safety floor (`rm -rf /`, credential reads, curl|sh, …): those categories
///    stay denied even when a persisted rule says allow. `.plan` and `.readOnly` keep their mode
///    semantics untouched (Plan approves step-by-step; read-only never mutates), so an allow rule
///    falls through to the base reviewer there.
/// 4. A matching `ask` rule forces the gate: a base `approve` is downgraded to `clarify` so the
///    user is always consulted for operations they explicitly marked ask-worthy.
public struct PermissionRuleGatedSafetyReviewer: SafetyReviewer {
    public var base: any SafetyReviewer
    public var rules: any PermissionRulesProviding
    private let floor = StaticSafetyReviewer()

    public init(base: any SafetyReviewer, rules: any PermissionRulesProviding) {
        self.base = base
        self.rules = rules
    }

    public func review(_ context: SafetyContext) async -> SafetyReview {
        guard let workspaceRoot = context.workspaceRoot else {
            return await base.review(context)
        }
        let table = rules.ruleTable(forWorkspaceRoot: workspaceRoot)
        guard !table.isEmpty else {
            return await base.review(context)
        }
        let subject = PermissionRuleSubject.make(
            toolCall: context.toolCall,
            workspaceRoot: workspaceRoot
        )
        switch table.decision(action: subject.action, resource: subject.resource) {
        case .deny:
            return SafetyReview(
                verdict: .deny,
                rationale: "A saved permission rule blocks \(context.toolCall.name) for this target."
            )
        case .allow:
            guard context.mode == .auto || context.mode == .review else {
                return await base.review(context)
            }
            if let hardDenyReason = floor.hardDenyReason(context) {
                return SafetyReview(verdict: .deny, rationale: hardDenyReason)
            }
            return SafetyReview(
                verdict: .approve,
                rationale: "A saved permission rule allows this action.",
                userIntentMatched: true
            )
        case .ask:
            let baseReview = await base.review(context)
            guard baseReview.verdict == .approve else {
                return baseReview
            }
            return SafetyReview(
                verdict: .clarify,
                rationale: "A saved permission rule asks for confirmation before running \(context.toolCall.name).",
                userIntentMatched: baseReview.userIntentMatched
            )
        case nil:
            return await base.review(context)
        }
    }
}
