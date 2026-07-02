import Foundation
import QuillCodeCore

/// The outcome of loading a workspace's permission rules for a review.
///
/// `degraded` is the fail-safe signal: when the on-disk rules file could not be read as intended
/// (corrupt, truncated, or written by a NEWER QuillCode), the loader cannot know what a
/// previously-saved rule said. It MUST NOT silently return an empty table, because an empty table
/// in Auto turns a persisted always-DENY into an auto-run. Instead it returns `degraded: true` and
/// the reviewer forces an approval gate until the file is resolved.
public struct PermissionRuleLoadOutcome: Sendable {
    public var table: PermissionRuleTable
    /// True when the rules file exists but could not be loaded as intended (corrupt / newer
    /// version). The reviewer treats this as "force ask": never auto-approve on a broken rules file.
    public var degraded: Bool
    /// Human-readable diagnostics to surface to the run/approval surface.
    public var diagnostics: [String]

    public init(
        table: PermissionRuleTable = PermissionRuleTable(),
        degraded: Bool = false,
        diagnostics: [String] = []
    ) {
        self.table = table
        self.degraded = degraded
        self.diagnostics = diagnostics
    }
}

/// Supplies the persisted per-workspace permission rules at review time. Implemented by the
/// persistence layer's file-backed store; reading fresh per review means an "always allow" saved
/// mid-run applies to the very next gate with no cache-invalidation seams.
public protocol PermissionRulesProviding: Sendable {
    func loadRuleOutcome(forWorkspaceRoot root: URL) -> PermissionRuleLoadOutcome
}

public extension PermissionRulesProviding {
    /// Convenience for callers that only need the table (ignoring the degraded/diagnostic signal).
    func ruleTable(forWorkspaceRoot root: URL) -> PermissionRuleTable {
        loadRuleOutcome(forWorkspaceRoot: root).table
    }
}

/// A `PermissionRuleTable` that is the same for every workspace — the in-memory provider for
/// tests and single-workspace embedders.
public struct StaticPermissionRulesProvider: PermissionRulesProviding {
    public var table: PermissionRuleTable
    public var degraded: Bool

    public init(table: PermissionRuleTable, degraded: Bool = false) {
        self.table = table
        self.degraded = degraded
    }

    public func loadRuleOutcome(forWorkspaceRoot root: URL) -> PermissionRuleLoadOutcome {
        PermissionRuleLoadOutcome(table: table, degraded: degraded)
    }
}

/// Composes the persisted permission rules with the existing mode + intent safety review, WITHOUT
/// replacing it: the table decides whether to skip or force the ASK; the safety floor stays.
///
/// Composition order per review:
/// 1. No workspace root → the base reviewer's verdict, unchanged.
/// 2. A DEGRADED rules file (corrupt / newer version) → force an approval gate (fail safe): a base
///    `approve` is downgraded to `clarify` so a broken rules file can never auto-run something a
///    prior rule may have denied.
/// 3. Empty table / no matching rule → the base reviewer's verdict, unchanged (existing behavior).
/// 4. A matching `deny` rule blocks the call in EVERY mode — including Auto, where the static
///    intent gate might otherwise have waved the call through.
/// 5. A matching `allow` rule skips the approval ASK in `.auto` and `.review` — but never the
///    static hard-deny safety floor (`rm -rf /`, credential reads, curl|sh, …): those categories
///    stay denied even when a persisted rule says allow. `.plan` and `.readOnly` keep their mode
///    semantics untouched, so an allow rule falls through to the base reviewer there. An allow rule
///    only matches an allow-scopable call (see `PermissionRuleSubject.allowMatchResource`).
/// 6. A matching `ask` rule forces the gate: a base `approve` is downgraded to `clarify`.
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
        let outcome = rules.loadRuleOutcome(forWorkspaceRoot: workspaceRoot)

        if outcome.degraded {
            // The rules file is broken; we cannot trust that a prior deny is still represented.
            // Fail safe: never auto-approve — force the human gate.
            return await forceAsk(
                context,
                rationale: "The saved permission rules could not be read; asking for confirmation to be safe."
            )
        }

        guard !outcome.table.isEmpty else {
            return await base.review(context)
        }
        let subject = PermissionRuleSubject.make(
            toolCall: context.toolCall,
            workspaceRoot: workspaceRoot
        )
        switch outcome.table.decision(
            action: subject.action,
            resource: subject.resource,
            allowResource: subject.allowMatchResource
        ) {
        case .deny:
            return SafetyReview(
                verdict: .deny,
                rationale: "A saved permission rule blocks \(context.toolCall.name) for this target."
            )
        case .allow:
            guard context.mode == .auto || context.mode == .review else {
                return await base.review(context)
            }
            // The hard-deny floor is evaluated against the SAME whitespace-normalized argument text
            // the rule table matched (StaticSafetyPolicy collapses horizontal whitespace), so a
            // padded spelling like `rm -rf  /` cannot slip an allow past the floor.
            if let hardDenyReason = floor.hardDenyReason(context) {
                return SafetyReview(verdict: .deny, rationale: hardDenyReason)
            }
            return SafetyReview(
                verdict: .approve,
                rationale: "A saved permission rule allows this action.",
                userIntentMatched: true
            )
        case .ask:
            return await forceAsk(
                context,
                rationale: "A saved permission rule asks for confirmation before running \(context.toolCall.name)."
            )
        case nil:
            return await base.review(context)
        }
    }

    /// Force a human gate: run the base review first so a base DENY (e.g. the hard-deny floor, or a
    /// read-only/plan mode block) still stands, but downgrade a base `approve` to `clarify` so the
    /// operation is asked about rather than auto-run.
    private func forceAsk(_ context: SafetyContext, rationale: String) async -> SafetyReview {
        let baseReview = await base.review(context)
        guard baseReview.verdict == .approve else {
            return baseReview
        }
        return SafetyReview(
            verdict: .clarify,
            rationale: rationale,
            userIntentMatched: baseReview.userIntentMatched
        )
    }
}
