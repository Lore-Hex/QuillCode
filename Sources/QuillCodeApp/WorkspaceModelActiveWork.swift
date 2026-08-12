@MainActor
extension QuillCodeWorkspaceModel {
    public func cancelActiveWork() {
        applyActiveWorkStopPlan(
            WorkspaceActiveWorkStopPlanner.cancel(stoppedWork: stopActiveWorkspaceWork())
        )
    }

    @discardableResult
    public func disconnectAll() -> Bool {
        let stoppedWork = stopActiveWorkspaceWork()
        let shouldDetachRemoteProject = selectedProject?.isRemote == true

        guard let plan = WorkspaceActiveWorkStopPlanner.disconnectAll(
            stoppedWork: stoppedWork,
            shouldDetachRemoteProject: shouldDetachRemoteProject
        ) else {
            return false
        }

        if shouldDetachRemoteProject {
            selectProject(nil, recordsNavigation: false)
        }

        applyActiveWorkStopPlan(plan)
        enforceThreadPayloadResidency()
        return true
    }

    private func stopActiveWorkspaceWork() -> WorkspaceStoppedActiveWork {
        let hadRunningMCPServers = mcpRuntime.cancelAll(extensions: &extensions)
        let hadAgentRuns = agentRuns.finishAll()
        let hadActiveWork = hadAgentRuns || terminal.isRunning
        composer.isSending = false
        activeTerminalSession?.cancel()
        activeTerminalSession = nil
        terminal.isRunning = false
        WorkspaceTerminalEngine.stopRunningEntries(terminal: &terminal)
        return WorkspaceStoppedActiveWork(
            hadRunningMCPServers: hadRunningMCPServers,
            hadActiveWork: hadActiveWork
        )
    }

    private func applyActiveWorkStopPlan(_ plan: WorkspaceActiveWorkStopPlan) {
        setLastError(plan.lastError)
        if let agentStatus = plan.agentStatus {
            refreshTopBar(agentStatus: agentStatus)
        }
    }
}
