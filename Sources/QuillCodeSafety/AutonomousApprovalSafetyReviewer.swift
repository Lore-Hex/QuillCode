import Foundation
import QuillCodeCore

/// Delivers the autonomous behavior a headless `--sandbox workspace-write` run is supposed to have
/// (it is the flag that REPLACED `--full-auto`): a base reviewer's `.clarify` verdict — "I'm not
/// sure this matches the request; ask the human" — becomes `.approve`, because in a headless run
/// there is no human to ask.
///
/// Without this, an unattended run dead-ends on the first command the static policy does not
/// recognize and the model reviewer is unsure about — a plain `git clone …` or `uv venv …` during
/// task setup stalls the entire run at `approval_required`, which is exactly what broke coworker
/// use case #1 (BFCL from scratch) after the deferral-stall fix let it get that far.
///
/// Safety boundary is unchanged: this NEVER converts `.deny`. The hard-deny floors (rm -rf,
/// pipe-to-shell, sudo, system-path writes, secret reads) still block, and the workspace-write
/// sandbox still confines filesystem writes. This only removes the "ask a human" step that has no
/// answer in an autonomous run — it does not remove the "never do this" rules.
///
/// Applied ONLY to headless/exec runs whose sandbox is workspace-write or danger-full-access.
/// Interactive runs keep their `.clarify` so the human at the keyboard can decide.
///
/// F24 carve-out: a `.clarify` for a shell command that references paths OUTSIDE the workspace
/// root is not "unrecognized but safe" — it is the one question that must not be answered with a
/// silent yes (live incident: `grep` over the real ~/Documents echoed personal filenames into run
/// output). Under workspace-write, that clarify becomes an honest `.deny` with a clear message
/// instead of an approve. `--sandbox danger-full-access` sets `waivesOutsideWorkspacePaths`: the
/// user explicitly opted into full filesystem reach, so the original waive behavior applies.
public struct AutonomousApprovalSafetyReviewer: SafetyReviewer {
    private let base: any SafetyReviewer
    private let waivesOutsideWorkspacePaths: Bool

    public init(base: any SafetyReviewer, waivesOutsideWorkspacePaths: Bool = false) {
        self.base = base
        self.waivesOutsideWorkspacePaths = waivesOutsideWorkspacePaths
    }

    public func review(_ context: SafetyContext) async -> SafetyReview {
        let review = await base.review(context)
        guard review.verdict == .clarify else { return review }

        if !waivesOutsideWorkspacePaths,
           let violation = StaticSafetyOutsideWorkspaceShellPolicy.violation(context) {
            let listed = violation.offendingPaths.prefix(4).joined(separator: ", ")
            return SafetyReview(
                verdict: .deny,
                rationale: "Blocked: this shell command references paths outside the workspace "
                    + "(\(listed)). A headless autonomous run has no human to approve "
                    + "out-of-workspace access, and the model reviewer may not waive it. Name the "
                    + "exact path in the task message to authorize it, or run interactively to "
                    + "approve it.",
                reviewerModel: review.reviewerModel,
                userIntentMatched: review.userIntentMatched,
                riskLevel: review.riskLevel,
                userAuthorization: review.userAuthorization
            ).withReviewTelemetry(.init(
                source: .autonomousOverride,
                fallbackReason: .outsideWorkspacePath
            ))
        }

        return SafetyReview(
            verdict: .approve,
            rationale: "Autonomous run: proceeding without a human approval step. "
                + "Hard-deny rules and the workspace sandbox still apply. "
                + "(Base reviewer said: \(review.rationale))",
            reviewerModel: review.reviewerModel,
            userIntentMatched: review.userIntentMatched,
            riskLevel: review.riskLevel,
            userAuthorization: review.userAuthorization
        ).withReviewTelemetry(.init(source: .autonomousOverride))
    }
}
