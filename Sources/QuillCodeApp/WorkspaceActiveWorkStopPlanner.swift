import QuillCodeCore

struct WorkspaceStoppedActiveWork: Sendable, Hashable {
    let hadRunningMCPServers: Bool
    let hadActiveWork: Bool

    var stoppedAnything: Bool {
        hadRunningMCPServers || hadActiveWork
    }
}

struct WorkspaceActiveWorkStopPlan: Sendable, Hashable {
    let lastError: String?
    let agentStatus: String?
}

enum WorkspaceActiveWorkStopPlanner {
    static func cancel(stoppedWork: WorkspaceStoppedActiveWork) -> WorkspaceActiveWorkStopPlan {
        WorkspaceActiveWorkStopPlan(
            lastError: nil,
            agentStatus: stoppedWork.stoppedAnything ? TopBarAgentStatusLabel.stopped : nil
        )
    }

    static func disconnectAll(
        stoppedWork: WorkspaceStoppedActiveWork,
        shouldDetachRemoteProject: Bool
    ) -> WorkspaceActiveWorkStopPlan? {
        guard stoppedWork.stoppedAnything || shouldDetachRemoteProject else {
            return nil
        }

        return WorkspaceActiveWorkStopPlan(
            lastError: nil,
            agentStatus: stoppedWork.stoppedAnything
                ? TopBarAgentStatusLabel.stopped
                : TopBarAgentStatusLabel.idle
        )
    }
}
