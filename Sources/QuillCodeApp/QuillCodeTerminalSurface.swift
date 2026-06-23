import Foundation

public struct TerminalSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var draft: String
    public var isRunning: Bool
    public var cwdLabel: String
    public var entries: [TerminalCommandSurface]
    public var emptyTitle: String

    public var canRun: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning
    }

    public var canClear: Bool {
        !entries.isEmpty && !isRunning
    }

    public init(
        terminal: TerminalState,
        cwd: URL?,
        emptyTitle: String = "Run commands in this project without leaving QuillCode."
    ) {
        self.isVisible = terminal.isVisible
        self.draft = terminal.draft
        self.isRunning = terminal.isRunning
        self.cwdLabel = cwd?.path ?? terminal.currentDirectoryPath ?? "No project"
        self.entries = terminal.entries.map(TerminalCommandSurface.init)
        self.emptyTitle = emptyTitle
    }
}

public struct TerminalCommandSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var command: String
    public var stdout: String
    public var stderr: String
    public var exitCodeLabel: String
    public var statusLabel: String
    public var executionContext: ExecutionContextSurface?
    public var isSuccess: Bool
    public var isRunning: Bool
    public var isStopped: Bool

    public init(entry: TerminalCommandState) {
        self.id = entry.id
        self.command = entry.command
        self.stdout = entry.stdout
        self.stderr = entry.stderr
        self.exitCodeLabel = Self.exitCodeLabel(for: entry)
        self.statusLabel = Self.statusLabel(for: entry.status)
        self.executionContext = entry.executionContext
        self.isSuccess = entry.status == .done
        self.isRunning = entry.status == .running
        self.isStopped = entry.status == .stopped
    }

    private static func exitCodeLabel(for entry: TerminalCommandState) -> String {
        switch entry.status {
        case .running:
            return "running"
        case .stopped:
            return "stopped"
        case .done, .failed:
            return entry.exitCode.map { "exit \($0)" } ?? "exit unknown"
        }
    }

    private static func statusLabel(for status: TerminalCommandStatus) -> String {
        switch status {
        case .running:
            return "Running"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        case .stopped:
            return "Stopped"
        }
    }
}
