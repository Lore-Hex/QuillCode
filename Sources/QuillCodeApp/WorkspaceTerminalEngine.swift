import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceTerminalEngine {
    static let stoppedMessage = "Command stopped."
    static let missingRemoteHostMessage = "SSH Remote project is missing a usable host."

    static func normalizedCommand(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedProcessInput(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        return input.hasSuffix("\n") ? input : "\(input)\n"
    }

    static func setDraft(_ draft: String, terminal: inout TerminalState) {
        terminal.draft = draft
        terminal.historyCursor = nil
        terminal.historyDraft = nil
    }

    static func canBeginRun(command: String, terminal: TerminalState) -> Bool {
        !command.isEmpty && !terminal.isRunning
    }

    static func canSendProcessInput(_ input: String, terminal: TerminalState) -> Bool {
        !input.isEmpty && terminal.isRunning
    }

    @discardableResult
    static func beginRun(
        command: String,
        entryID: UUID = UUID(),
        terminal: inout TerminalState
    ) -> UUID {
        terminal.draft = ""
        terminal.historyCursor = nil
        terminal.historyDraft = nil
        terminal.isVisible = true
        terminal.isRunning = true
        terminal.entries.append(TerminalCommandState(
            id: entryID,
            command: command,
            stdout: "",
            stderr: "",
            exitCode: nil,
            ok: false,
            status: .running
        ))
        return entryID
    }

    static func failMissingExecutionContext(
        id: UUID,
        terminal: inout TerminalState,
        message: String = missingRemoteHostMessage
    ) {
        finishEntry(
            id: id,
            stdout: "",
            stderr: message,
            exitCode: nil,
            ok: false,
            status: .failed,
            terminal: &terminal
        )
        terminal.isRunning = false
    }

    @discardableResult
    static func applyStreamingEvent(
        _ event: ShellProcessEvent,
        id: UUID,
        terminal: inout TerminalState
    ) -> ToolResult? {
        switch event {
        case .stdout(let text):
            appendOutput(id: id, stdout: text, terminal: &terminal)
            return nil
        case .stderr(let text):
            appendOutput(id: id, stderr: text, terminal: &terminal)
            return nil
        case .finished(let result):
            return result
        }
    }

    static func entryIsStopped(id: UUID, terminal: TerminalState) -> Bool {
        terminal.entries.first(where: { $0.id == id })?.status == .stopped
    }

    static func finishStoppedRun(
        executionContext: WorkspaceTerminalExecutionContext,
        terminal: inout TerminalState
    ) {
        WorkspaceTerminalSessionAdapter.removeMarkers(executionContext.markerURLs)
        terminal.isRunning = false
    }

    static func finishCancelledRun(
        id: UUID,
        executionContext: WorkspaceTerminalExecutionContext,
        terminal: inout TerminalState
    ) {
        WorkspaceTerminalSessionAdapter.removeMarkers(executionContext.markerURLs)
        finishEntry(
            id: id,
            stdout: "",
            stderr: stoppedMessage,
            exitCode: nil,
            ok: false,
            status: .stopped,
            terminal: &terminal
        )
        terminal.isRunning = false
    }

    static func finishCompletedRun(
        id: UUID,
        executionContext: WorkspaceTerminalExecutionContext,
        result: ToolResult,
        terminal: inout TerminalState
    ) {
        let terminalResult = WorkspaceTerminalSessionAdapter.sessionResult(
            for: executionContext,
            stdout: result.stdout
        )
        terminal.currentDirectoryPath = terminalResult.currentDirectoryPath
        if let environmentDelta = terminalResult.environmentDelta {
            terminal.environmentOverrides = environmentDelta.overrides
            terminal.removedEnvironmentKeys = environmentDelta.removedKeys
        }
        finishEntry(
            id: id,
            stdout: terminalResult.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            ok: result.ok,
            status: result.ok ? .done : .failed,
            terminal: &terminal
        )
        terminal.isRunning = false
    }

    static func currentDirectoryURL(
        terminal: TerminalState,
        selectedProjectID: UUID?,
        selectedProjectIsRemote: Bool,
        activeWorkspaceRoot: URL?
    ) -> URL? {
        guard !selectedProjectIsRemote else { return nil }
        guard terminal.projectID == selectedProjectID else {
            return activeWorkspaceRoot
        }
        if let path = terminal.currentDirectoryPath, !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return activeWorkspaceRoot
    }

    static func syncSessionToSelectedProject(
        terminal: inout TerminalState,
        selectedProjectID: UUID?,
        selectedProjectDisplayPath: String?
    ) {
        guard terminal.projectID != selectedProjectID else { return }
        terminal.projectID = selectedProjectID
        terminal.currentDirectoryPath = selectedProjectDisplayPath
        terminal.environmentOverrides = [:]
        terminal.removedEnvironmentKeys = []
        terminal.historyCursor = nil
        terminal.historyDraft = nil
    }

    @discardableResult
    static func clearHistory(terminal: inout TerminalState) -> Bool {
        guard !terminal.isRunning else { return false }
        terminal.entries = []
        terminal.historyCursor = nil
        terminal.historyDraft = nil
        return true
    }

    @discardableResult
    static func recallPreviousCommand(terminal: inout TerminalState) -> Bool {
        guard !terminal.isRunning else { return false }
        let history = commandHistory(from: terminal)
        guard !history.isEmpty else { return false }
        if let cursor = terminal.historyCursor {
            guard history.indices.contains(cursor) else {
                terminal.historyCursor = nil
                terminal.historyDraft = nil
                return false
            }
            guard cursor > history.startIndex else { return false }
            terminal.historyCursor = history.index(before: cursor)
        } else {
            terminal.historyDraft = terminal.draft
            terminal.historyCursor = history.index(before: history.endIndex)
        }
        if let cursor = terminal.historyCursor {
            terminal.draft = history[cursor]
        }
        return true
    }

    @discardableResult
    static func recallNextCommand(terminal: inout TerminalState) -> Bool {
        guard !terminal.isRunning, let cursor = terminal.historyCursor else { return false }
        let history = commandHistory(from: terminal)
        guard history.indices.contains(cursor) else {
            terminal.historyCursor = nil
            terminal.historyDraft = nil
            return false
        }
        let next = history.index(after: cursor)
        if next < history.endIndex {
            terminal.historyCursor = next
            terminal.draft = history[next]
        } else {
            terminal.historyCursor = nil
            terminal.draft = terminal.historyDraft ?? ""
            terminal.historyDraft = nil
        }
        return true
    }

    static func appendOutput(
        id: UUID,
        stdout: String = "",
        stderr: String = "",
        terminal: inout TerminalState
    ) {
        guard let index = terminal.entries.firstIndex(where: { $0.id == id }),
              terminal.entries[index].status == .running else {
            return
        }
        terminal.entries[index].stdout += stdout
        terminal.entries[index].stderr += stderr
    }

    static func updateExecutionContext(
        id: UUID,
        executionContext: ExecutionContextSurface,
        terminal: inout TerminalState
    ) {
        guard let index = terminal.entries.firstIndex(where: { $0.id == id }) else { return }
        terminal.entries[index].executionContext = executionContext
    }

    static func finishEntry(
        id: UUID,
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        status: TerminalCommandStatus,
        terminal: inout TerminalState
    ) {
        guard let index = terminal.entries.firstIndex(where: { $0.id == id }) else { return }
        if terminal.entries[index].status == .stopped, status != .stopped {
            return
        }
        terminal.entries[index].stdout = stdout
        terminal.entries[index].stderr = stderr
        terminal.entries[index].exitCode = exitCode
        terminal.entries[index].ok = ok
        terminal.entries[index].status = status
    }

    static func stopRunningEntries(terminal: inout TerminalState) {
        for index in terminal.entries.indices where terminal.entries[index].status == .running {
            terminal.entries[index].stderr = terminal.entries[index].stderr.isEmpty
                ? stoppedMessage
                : terminal.entries[index].stderr
            terminal.entries[index].exitCode = nil
            terminal.entries[index].ok = false
            terminal.entries[index].status = .stopped
        }
    }

    private static func commandHistory(from terminal: TerminalState) -> [String] {
        terminal.entries.compactMap { entry in
            guard entry.status != .running else { return nil }
            let command = normalizedCommand(entry.command)
            return command.isEmpty ? nil : command
        }
    }

    static func executionContext(
        command: String,
        selectedProject: ProjectRef?,
        terminalCurrentDirectoryURL: URL?,
        terminal: TerminalState,
        workspaceRoot: URL,
        sshRemoteShellExecutor: SSHRemoteShellExecutor
    ) -> WorkspaceTerminalExecutionContext? {
        if let selectedProject, selectedProject.isRemote {
            let connection = WorkspaceTerminalSessionAdapter.remoteConnection(
                for: selectedProject,
                terminalCurrentDirectoryPath: terminal.currentDirectoryPath
            )
            let marker = WorkspaceTerminalSessionAdapter.remoteMarker()
            let wrappedCommand = WorkspaceTerminalSessionAdapter.remoteWrappedCommand(
                command,
                marker: marker,
                environmentOverrides: terminal.environmentOverrides,
                removedEnvironmentKeys: terminal.removedEnvironmentKeys
            )
            guard let request = sshRemoteShellExecutor.request(
                command: wrappedCommand,
                connection: connection
            ) else {
                return nil
            }
            return WorkspaceTerminalExecutionContext(
                request: request,
                cwdMarkerURL: nil,
                environmentMarkerURL: nil,
                remoteMarker: marker,
                remoteConnection: connection,
                fallbackCurrentDirectoryPath: connection.displayLabel,
                surface: .project(selectedProject)
            )
        }

        let environment = WorkspaceTerminalSessionAdapter.effectiveEnvironment(
            overrides: terminal.environmentOverrides,
            removedKeys: terminal.removedEnvironmentKeys
        )
        let workingDirectory = terminalCurrentDirectoryURL ?? workspaceRoot.standardizedFileURL
        return WorkspaceTerminalSessionAdapter.localExecutionContext(
            command: command,
            workingDirectory: workingDirectory,
            environment: environment,
            executionContext: .local(path: workingDirectory.standardizedFileURL.path)
        )
    }
}
