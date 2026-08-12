import Foundation

public enum WorkspaceAutomaticStartupPolicy: Sendable, Equatable {
    case startImmediately
    case deferUntilRequested
}

@MainActor
public extension QuillCodeWorkspaceModel {
    func startAutomaticStartupWork() {
        enforceManagedWorktreeRetention()
        scheduleSelectedPullRequestReconciliation()
    }
}
