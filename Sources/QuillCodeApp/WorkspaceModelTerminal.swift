import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
extension QuillCodeWorkspaceModel {
    public func setTerminalDraft(_ draft: String) {
        WorkspaceTerminalEngine.setDraft(draft, terminal: &terminal)
    }

    public func setTerminalVisible(_ isVisible: Bool) {
        terminal.isVisible = isVisible
    }

    public func toggleTerminal() {
        terminal.isVisible.toggle()
    }

    @discardableResult
    public func clearTerminalHistory() -> Bool {
        guard WorkspaceTerminalEngine.clearHistory(terminal: &terminal) else { return false }
        terminal.isVisible = true
        setLastError(nil)
        return true
    }

    @discardableResult
    public func recallPreviousTerminalCommand() -> Bool {
        WorkspaceTerminalEngine.recallPreviousCommand(terminal: &terminal)
    }

    @discardableResult
    public func recallNextTerminalCommand() -> Bool {
        WorkspaceTerminalEngine.recallNextCommand(terminal: &terminal)
    }

    public func runTerminalCommand(workspaceRoot: URL) async {
        await runTerminalCommand(terminal.draft, workspaceRoot: workspaceRoot)
    }

    @discardableResult
    public func sendTerminalInput(_ input: String) -> Bool {
        let processInput = WorkspaceTerminalEngine.normalizedProcessInput(input)
        guard WorkspaceTerminalEngine.canSendProcessInput(processInput, terminal: terminal),
              let activeTerminalSession else {
            return false
        }
        return activeTerminalSession.sendInput(processInput)
    }

    public func runTerminalCommand(_ input: String, workspaceRoot: URL) async {
        let command = WorkspaceTerminalEngine.normalizedCommand(input)
        guard WorkspaceTerminalEngine.canBeginRun(command: command, terminal: terminal) else { return }
        syncTerminalSessionToSelectedProject()

        let entryID = WorkspaceTerminalEngine.beginRun(command: command, terminal: &terminal)
        applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.started())

        guard let executionContext = WorkspaceTerminalEngine.executionContext(
            command: command,
            selectedProject: selectedProject,
            terminalCurrentDirectoryURL: terminalCurrentDirectoryURL,
            terminal: terminal,
            workspaceRoot: workspaceRoot,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        ) else {
            WorkspaceTerminalEngine.failMissingExecutionContext(id: entryID, terminal: &terminal)
            applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.missingExecutionContext())
            return
        }
        WorkspaceTerminalEngine.updateExecutionContext(
            id: entryID,
            executionContext: executionContext.surface,
            terminal: &terminal
        )

        var finalResult: ToolResult?
        let session = terminalSession(for: executionContext)
        activeTerminalSession = session
        defer {
            if isSameShellProcessSession(activeTerminalSession, session) {
                activeTerminalSession = nil
            }
        }
        for await event in session.events {
            if Task.isCancelled || WorkspaceTerminalEngine.entryIsStopped(id: entryID, terminal: terminal) {
                break
            }
            if let result = WorkspaceTerminalEngine.applyStreamingEvent(event, id: entryID, terminal: &terminal) {
                finalResult = result
            }
        }

        if WorkspaceTerminalEngine.entryIsStopped(id: entryID, terminal: terminal) {
            WorkspaceTerminalEngine.finishStoppedRun(executionContext: executionContext, terminal: &terminal)
            applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.stopped())
            return
        }
        guard !Task.isCancelled, let result = finalResult else {
            WorkspaceTerminalEngine.finishCancelledRun(
                id: entryID,
                executionContext: executionContext,
                terminal: &terminal
            )
            applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.cancelled())
            return
        }

        WorkspaceTerminalEngine.finishCompletedRun(
            id: entryID,
            executionContext: executionContext,
            result: result,
            terminal: &terminal
        )
        applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.finished(result: result))
    }

    private func applyTerminalLifecyclePlan(_ plan: WorkspaceTerminalLifecyclePlan) {
        setLastError(plan.lastError)
        refreshTopBar(agentStatus: plan.agentStatus)
    }

    private func terminalSession(
        for executionContext: WorkspaceTerminalExecutionContext
    ) -> any ShellProcessSession {
        let executor = ShellToolExecutor()
        switch executionContext.sessionKind {
        case .pipe:
            return executor.startStreamingSession(executionContext.request)
        case .pseudoTerminal:
            return executor.startPTYSession(executionContext.request)
        }
    }
}

private func isSameShellProcessSession(
    _ lhs: (any ShellProcessSession)?,
    _ rhs: any ShellProcessSession
) -> Bool {
    guard let lhs else { return false }
    return (lhs as AnyObject) === (rhs as AnyObject)
}
