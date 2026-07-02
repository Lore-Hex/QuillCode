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
        // Derivation refuses to build an allow rule for a call that has no bounding resource
        // (apply_patch, git.*, a shell call carrying an env/cwd override): teaching one such call
        // must never silently authorize every future call of that tool. In that case nothing is
        // persisted and nothing is backfilled — the single request was already run/skipped.
        guard let rule = PermissionRuleDerivation.rule(
            for: request,
            decision: decision,
            workspaceRoot: workspaceRoot
        ) else {
            if decision == .allow {
                setLastError(
                    "\(request.toolCall.name) can't be saved as an always-allow rule (it has no bounded target), so it was approved just this once."
                )
            }
            return
        }

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

    /// Resolves the still-pending, current-turn approval requests the new rule matches, exactly as
    /// if the user had answered each one: allow rules run the held tool, deny rules skip it.
    ///
    /// Guards that keep backfill honest:
    /// - only current-turn requests (see `undecidedRequests`), never ones the user abandoned;
    /// - hard-blocked requests (recommended verdict `.deny` — the static safety floor) are never
    ///   backfilled: a persisted allow skips the ASK, not the floor;
    /// - an ALLOW rule only matches an allow-scopable call (its `allowMatchResource`), so a
    ///   pending call carrying an env/cwd override is never auto-run by a bare-command allow.
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
            let candidateResource = rule.decision == .allow ? subject.allowMatchResource : subject.resource
            guard let candidateResource,
                  rule.matches(action: subject.action, resource: candidateResource)
            else {
                continue
            }
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
