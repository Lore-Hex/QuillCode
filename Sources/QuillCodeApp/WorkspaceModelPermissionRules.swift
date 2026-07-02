import Foundation
import QuillCodeCore
import QuillCodeSafety

/// The "always allow / always deny" save path: derives an exact permission rule from the approval
/// request the user just answered, persists it to the per-project rule file, and backfills every
/// other still-pending approval in the thread that the new rule matches.
@MainActor
extension QuillCodeWorkspaceModel {
    func persistPermissionRuleAndBackfill(
        from request: ApprovalRequest,
        decision: PermissionRuleDecision,
        workspaceRoot: URL
    ) {
        let rule = PermissionRuleDerivation.rule(
            for: request,
            decision: decision,
            workspaceRoot: workspaceRoot
        )

        if let permissionRuleStore {
            do {
                let diagnostics = try permissionRuleStore.append(rule, forWorkspaceRoot: workspaceRoot)
                if let diagnostic = diagnostics.first {
                    setLastError(diagnostic)
                }
            } catch {
                // The rule could not be persisted (e.g. a newer-format file). Surface it — the
                // in-session backfill below still applies, but the rule will not survive.
                setLastError("Could not save the permission rule: \(error)")
            }
        }

        backfillPendingApprovals(matching: rule, decidedRequestID: request.id, workspaceRoot: workspaceRoot)
    }

    /// Resolves every still-pending approval request the new rule matches, exactly as if the user
    /// had answered each one: allow rules run the held tool, deny rules skip it. Hard-blocked
    /// requests (recommended verdict `.deny` — the static safety floor) are never backfilled; a
    /// persisted allow skips the ASK, not the safety floor.
    private func backfillPendingApprovals(
        matching rule: PermissionRule,
        decidedRequestID: String,
        workspaceRoot: URL
    ) {
        let pending = WorkspaceApprovalActionPlanner.undecidedRequests(in: selectedThread)
        for request in pending {
            guard request.id != decidedRequestID,
                  request.recommendedVerdict != .deny
            else {
                continue
            }
            let subject = PermissionRuleSubject.make(
                toolCall: request.toolCall,
                workspaceRoot: workspaceRoot
            )
            guard rule.matches(action: subject.action, resource: subject.resource) else { continue }
            let action = ToolCardActionSurface(
                title: rule.decision == .deny ? "Skip" : "Run",
                kind: rule.decision == .deny ? .deny : .approve,
                requestID: request.id,
                style: .secondary
            )
            _ = runToolCardAction(action, workspaceRoot: workspaceRoot)
        }
    }
}
