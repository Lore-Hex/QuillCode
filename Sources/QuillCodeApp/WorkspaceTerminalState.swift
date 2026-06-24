import Foundation
import QuillCodeCore
import QuillCodeTools

public struct TerminalCommandState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var command: String
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var ok: Bool
    public var status: TerminalCommandStatus
    public var executionContext: ExecutionContextSurface?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        command: String,
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        status: TerminalCommandStatus? = nil,
        executionContext: ExecutionContextSurface? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.ok = ok
        self.status = status ?? (ok ? .done : .failed)
        self.executionContext = executionContext
        self.createdAt = createdAt
    }
}

public enum TerminalCommandStatus: String, Sendable, Hashable {
    case running
    case done
    case failed
    case stopped
}

public struct TerminalState: Sendable, Hashable {
    public var projectID: UUID?
    public var currentDirectoryPath: String?
    public var environmentOverrides: [String: String]
    public var removedEnvironmentKeys: Set<String>
    public var isVisible: Bool
    public var draft: String
    public var isRunning: Bool
    public var entries: [TerminalCommandState]

    public init(
        projectID: UUID? = nil,
        currentDirectoryPath: String? = nil,
        environmentOverrides: [String: String] = [:],
        removedEnvironmentKeys: Set<String> = [],
        isVisible: Bool = false,
        draft: String = "",
        isRunning: Bool = false,
        entries: [TerminalCommandState] = []
    ) {
        self.projectID = projectID
        self.currentDirectoryPath = currentDirectoryPath
        self.environmentOverrides = environmentOverrides
        self.removedEnvironmentKeys = removedEnvironmentKeys
        self.isVisible = isVisible
        self.draft = draft
        self.isRunning = isRunning
        self.entries = entries
    }
}

struct WorkspaceTerminalExecutionContext {
    var request: ShellExecutionRequest
    var cwdMarkerURL: URL?
    var environmentMarkerURL: URL?
    var remoteMarker: String?
    var remoteConnection: ProjectConnection?
    var fallbackCurrentDirectoryPath: String
    var surface: ExecutionContextSurface

    var markerURLs: [URL] {
        [cwdMarkerURL, environmentMarkerURL].compactMap { $0 }
    }
}

struct WorkspaceTerminalSessionResult {
    var stdout: String
    var currentDirectoryPath: String
    var environmentDelta: WorkspaceTerminalEnvironmentDelta?
}

struct WorkspaceTerminalEnvironmentDelta: Equatable {
    var overrides: [String: String]
    var removedKeys: Set<String>
}
