enum StaticSafetyPullRequestPolicy {
    static let requestTriggers = [
        "pull request",
        "open pr",
        "open a pr",
        "create pr",
        "create a pr",
        "submit pr",
        "submit a pr",
        "checkout pr",
        "check out pr",
        "switch to pr",
        "merge pr",
        "automerge pr",
        "auto merge pr",
        "inline comment",
        "review thread",
        "review threads",
        "thread ids",
        "resolve thread",
        "unresolve thread"
    ]

    private static let specificRules: [StaticSafetyIntentRule] = [
        .init(
            requestTriggers: ["checkout", "check out", "switch"],
            allowedToolNames: ["git.pr.checkout", "git.status"]
        ),
        .init(
            requestTriggers: ["reviewer", "reviewers", "request review from"],
            allowedToolNames: ["git.pr.reviewers", "git.status"]
        ),
        .init(
            requestTriggers: ["label", "labels", "unlabel"],
            allowedToolNames: ["git.pr.labels", "git.status"]
        ),
        .init(
            requestTriggers: ["merge", "automerge"],
            allowedToolNames: ["git.pr.merge", "git.pr.checks", "git.status"]
        ),
        .init(
            requestTriggers: ["list", "show", "browse", "find", "unresolved", "thread ids", "comment ids"],
            allowedToolNames: ["git.pr.review_threads", "git.pr.view", "git.status"]
        ),
        .init(
            requestTriggers: ["resolve", "unresolve", "reopen"],
            allowedToolNames: ["git.pr.review_thread", "git.status"]
        ),
        .init(
            requestTriggers: ["approve", "request changes", "needs changes", "review"],
            allowedToolNames: ["git.pr.review", "git.status"]
        ),
        .init(
            requestTriggers: ["comment", "reply"],
            allowedToolNames: ["git.pr.comment", "git.pr.review_comment", "git.pr.review_reply"]
        ),
        .init(
            requestTriggers: ["check", "ci", "status"],
            allowedToolNames: ["git.pr.checks", "git.status"]
        ),
        .init(
            requestTriggers: ["view", "show", "inspect", "read"],
            allowedToolNames: ["git.pr.view", "git.status"]
        )
    ]

    /// An explicit PR-creation intent. Checked only when no more-specific verb rule matches, so
    /// "create a comment on the pr" stays a comment (the comment rule wins) and does not auto-approve
    /// creating a brand-new PR. `git.push` is intentionally NOT here — a push is authorized by its own
    /// explicit push verb below, so "open a pull request but don't push" cannot auto-approve a push via
    /// the unnegated "open".
    private static let createRule = StaticSafetyIntentRule(
        requestTriggers: ["open", "create", "submit"],
        allowedToolNames: ["git.pr.create", "git.status"]
    )

    /// An explicit push/publish intent — keyed on the push verb so a negated "don't push" suppresses it.
    private static let pushRule = StaticSafetyIntentRule(
        requestTriggers: ["push", "publish"],
        allowedToolNames: ["git.push", "git.status"]
    )

    // The fallback when NO verb rule matches must be READ-ONLY. A bare PR mention
    // ("summarize the pull request") never auto-approves an outward-facing `git.push`/`git.pr.create`.
    private static let defaultAllowedToolNames = [
        "git.pr.view",
        "git.pr.checks",
        "git.status"
    ]

    static func requestMatches(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(requestTriggers)
            || (request.containsToken("pr")
                && (specificRules + [createRule, pushRule]).contains { $0.matches(request: request) })
    }

    static func intentMatches(request: StaticSafetyRequest, toolName: String) -> Bool {
        // Specific verb rules (comment, view, checkout, …) take priority: if any matches, the create/
        // push intents are NOT consulted, so a co-occurring "create"/"open" cannot escalate a
        // comment/read request into an outward-facing write.
        let matchingRules = specificRules.filter { $0.matches(request: request) }
        if !matchingRules.isEmpty {
            return matchingRules.contains { $0.allows(toolName: toolName) }
        }
        if createRule.matches(request: request) && createRule.allows(toolName: toolName) {
            return true
        }
        if pushRule.matches(request: request) && pushRule.allows(toolName: toolName) {
            return true
        }
        return defaultAllowedToolNames.contains { toolName.contains($0) }
    }
}
