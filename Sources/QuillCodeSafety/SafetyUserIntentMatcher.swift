import Foundation

struct SafetyUserIntentMatcher: Sendable {
    func matches(_ context: SafetyContext) -> Bool {
        let user = context.userMessage.lowercased()
        if matchesMemoryIntent(user: user, toolName: context.toolCall.name) {
            return true
        }
        if user.contains("remember") || user.contains("memorize") {
            return false
        }
        if user.contains("run") || user.contains("execute") {
            return true
        }
        if matchesPullRequestIntent(user: user, toolName: context.toolCall.name) {
            return true
        }
        if matchesFileCreationIntent(user: user, toolName: context.toolCall.name) {
            return true
        }
        if matchesGitIntent(user: user, toolName: context.toolCall.name) {
            return true
        }
        if matchesComputerUseIntent(user: user, toolName: context.toolCall.name) {
            return true
        }
        if matchesDiagnosticIntent(user: user) {
            return true
        }
        return sharedWords(in: user).contains { context.toolCall.argumentsJSON.lowercased().contains($0) }
    }

    private func matchesMemoryIntent(user: String, toolName: String) -> Bool {
        (user.contains("remember") || user.contains("memorize")) && toolName.contains("memory")
    }

    private func matchesPullRequestIntent(user: String, toolName: String) -> Bool {
        guard isPullRequestRequest(user) else {
            return false
        }
        if user.contains("checkout") || user.contains("check out") || user.contains("switch") {
            return toolName.contains("git.pr.checkout") || toolName.contains("git.status")
        }
        if user.contains("reviewer")
            || user.contains("reviewers")
            || user.contains("request review from") {
            return toolName.contains("git.pr.reviewers") || toolName.contains("git.status")
        }
        if user.contains("label") || user.contains("labels") || user.contains("unlabel") {
            return toolName.contains("git.pr.labels") || toolName.contains("git.status")
        }
        if user.contains("merge") || user.contains("automerge") {
            return toolName.contains("git.pr.merge")
                || toolName.contains("git.pr.checks")
                || toolName.contains("git.status")
        }
        if user.contains("approve")
            || user.contains("request changes")
            || user.contains("needs changes")
            || user.contains("review") {
            return toolName.contains("git.pr.review") || toolName.contains("git.status")
        }
        if user.contains("comment") || user.contains("reply") {
            return toolName.contains("git.pr.comment")
        }
        if user.contains("check") || user.contains("ci") || user.contains("status") {
            return toolName.contains("git.pr.checks") || toolName.contains("git.status")
        }
        if user.contains("view")
            || user.contains("show")
            || user.contains("inspect")
            || user.contains("read") {
            return toolName.contains("git.pr.view") || toolName.contains("git.status")
        }
        return toolName.contains("git.pr.create")
            || toolName.contains("git.pr.comment")
            || toolName.contains("git.push")
            || toolName.contains("git.status")
    }

    private func isPullRequestRequest(_ user: String) -> Bool {
        [
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
            "auto merge pr"
        ].contains { user.contains($0) }
    }

    private func matchesFileCreationIntent(user: String, toolName: String) -> Bool {
        guard user.contains("make") || user.contains("create") || user.contains("write") else {
            return false
        }
        return toolName.contains("file")
            || toolName.contains("shell")
            || toolName.contains("git.worktree")
    }

    private func matchesGitIntent(user: String, toolName: String) -> Bool {
        if user.contains("commit") {
            return toolName.contains("git.commit")
                || toolName.contains("git.stage")
                || toolName.contains("git.status")
                || toolName.contains("git.diff")
        }
        if user.contains("push") || user.contains("publish branch") {
            return toolName.contains("git.push") || toolName.contains("git.status")
        }
        if user.contains("worktree") {
            return toolName.contains("git.worktree")
                || toolName.contains("git.status")
                || toolName.contains("git.diff")
        }
        return false
    }

    private func matchesComputerUseIntent(user: String, toolName: String) -> Bool {
        guard toolName.contains("computer") else {
            return false
        }
        return [
            "screenshot",
            "screen",
            "click",
            "type",
            "scroll",
            "cursor",
            "mouse",
            "press",
            "key"
        ].contains { user.contains($0) }
    }

    private func matchesDiagnosticIntent(user: String) -> Bool {
        user.contains("openclaw")
            || user.contains("whoami")
            || user.contains("disk")
            || user.contains("storage")
    }

    private func sharedWords(in user: String) -> [String] {
        user.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }
}
