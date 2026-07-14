@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func publishSelectedWorktreeBranch() -> Bool {
        let published = WorkspaceManagedWorktreePublishCoordinator(model: self).publishSelectedThread()
        if published {
            scheduleSelectedPullRequestReconciliation()
        }
        return published
    }

    @discardableResult
    public func refreshSelectedPullRequest() -> Bool {
        let refreshed = WorkspaceManagedWorktreePullRequestCoordinator(model: self).refreshSelectedThread()
        if refreshed {
            scheduleSelectedPullRequestReconciliation()
        }
        return refreshed
    }

    @discardableResult
    public func landSelectedPullRequest() -> Bool {
        let landed = WorkspaceManagedWorktreePullRequestCoordinator(model: self).landSelectedThread()
        if landed {
            scheduleSelectedPullRequestReconciliation()
        }
        return landed
    }

    @discardableResult
    public func cleanUpSelectedMergedWorktree() -> Bool {
        WorkspaceManagedWorktreePullRequestCoordinator(model: self).cleanUpMergedSelectedThread()
    }
}
