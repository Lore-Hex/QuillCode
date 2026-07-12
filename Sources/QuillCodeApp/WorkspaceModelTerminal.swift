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
    public func setTerminalWindowSize(rows: Int, columns: Int) -> Bool {
        guard let windowSize = WorkspaceTerminalEngine.normalizedWindowSize(
            rows: rows,
            columns: columns
        ) else {
            return false
        }
        terminal.windowSize = windowSize
        return activeTerminalSession?.resize(to: windowSize.ptyWindowSize) ?? false
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

    @discardableResult
    public func sendTerminalMouseInput(_ request: TerminalMouseInputRequest) -> Bool {
        guard terminal.isRunning,
              terminal.mouseReporting == request.reporting,
              let activeTerminalSession,
              let input = TerminalMouseInputEncoder.encode(request) else {
            return false
        }
        return activeTerminalSession.sendInput(input)
    }

    @discardableResult
    public func sendTerminalKeyboardInput(_ request: TerminalKeyboardInputRequest) -> Bool {
        guard terminal.isRunning,
              terminal.keyboardMode == request.mode,
              let activeTerminalSession,
              let input = TerminalKeyboardInputEncoder.encode(request) else {
            return false
        }
        return activeTerminalSession.sendInput(input)
    }

    /// Suspends the running terminal command (job control, like a shell's Ctrl+Z). Returns `false` if
    /// nothing is running, it is already suspended, or the session does not support suspension (only
    /// the local PTY does).
    @discardableResult
    public func suspendTerminalCommand() -> Bool {
        guard terminal.isRunning, !terminal.isSuspended,
              let activeTerminalSession, activeTerminalSession.suspend() else {
            return false
        }
        terminal.isSuspended = true
        return true
    }

    /// Resumes a suspended terminal command. Returns `false` if nothing is running or it is not
    /// currently suspended.
    @discardableResult
    public func resumeTerminalCommand() -> Bool {
        guard terminal.isRunning, terminal.isSuspended,
              let activeTerminalSession, activeTerminalSession.resume() else {
            return false
        }
        terminal.isSuspended = false
        return true
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
        let session = WorkspaceTerminalProcessLauncher.startSession(
            for: executionContext,
            windowSize: terminal.windowSize
        )
        activeTerminalSession = session
        defer {
            clearActiveTerminalSessionIfCurrent(session)
        }
        for await event in session.events {
            if Task.isCancelled || WorkspaceTerminalEngine.entryIsStopped(id: entryID, terminal: terminal) {
                break
            }
            if let result = WorkspaceTerminalEngine.applyStreamingEvent(event, id: entryID, terminal: &terminal) {
                finalResult = result
            }
        }
        // The session has ended (completed, stopped, or cancelled); job control no longer applies.
        terminal.isSuspended = false

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
        if result.ok,
           let threadID = root.selectedThreadID,
           let managedRoot = self.workspaceRoot(forThreadID: threadID) {
            _ = reconcileManagedWorktreeBranch(threadID: threadID, workspaceRoot: managedRoot)
        }
        applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.finished(result: result))
    }

    private func applyTerminalLifecyclePlan(_ plan: WorkspaceTerminalLifecyclePlan) {
        setLastError(plan.lastError)
        refreshTopBar(agentStatus: plan.agentStatus)
    }

    private func clearActiveTerminalSessionIfCurrent(_ session: any ShellInteractiveSession) {
        guard let activeTerminalSession,
              ObjectIdentifier(activeTerminalSession as AnyObject) == ObjectIdentifier(session as AnyObject) else {
            return
        }
        self.activeTerminalSession = nil
    }
}
