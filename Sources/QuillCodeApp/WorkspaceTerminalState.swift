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

public struct TerminalWindowSize: Sendable, Hashable {
    public var rows: UInt16
    public var columns: UInt16

    public init(rows: UInt16, columns: UInt16) {
        self.rows = rows
        self.columns = columns
    }

    var ptyWindowSize: PTYWindowSize {
        PTYWindowSize(rows: rows, columns: columns)
    }
}

public struct TerminalState: Sendable, Hashable {
    public var projectID: UUID?
    public var currentDirectoryPath: String?
    public var environmentOverrides: [String: String]
    public var removedEnvironmentKeys: Set<String>
    public var windowSize: TerminalWindowSize?
    public var isVisible: Bool
    public var draft: String
    public var historyCursor: Int?
    public var historyDraft: String?
    public var isRunning: Bool
    public var isSuspended: Bool
    public private(set) var mouseReporting: TerminalMouseReporting
    var mouseReportingParser: TerminalMouseReportingParser
    public var entries: [TerminalCommandState]

    public init(
        projectID: UUID? = nil,
        currentDirectoryPath: String? = nil,
        environmentOverrides: [String: String] = [:],
        removedEnvironmentKeys: Set<String> = [],
        windowSize: TerminalWindowSize? = nil,
        isVisible: Bool = false,
        draft: String = "",
        historyCursor: Int? = nil,
        historyDraft: String? = nil,
        isRunning: Bool = false,
        isSuspended: Bool = false,
        mouseReporting: TerminalMouseReporting = .disabled,
        entries: [TerminalCommandState] = []
    ) {
        self.projectID = projectID
        self.currentDirectoryPath = currentDirectoryPath
        self.environmentOverrides = environmentOverrides
        self.removedEnvironmentKeys = removedEnvironmentKeys
        self.windowSize = windowSize
        self.isVisible = isVisible
        self.draft = draft
        self.historyCursor = historyCursor
        self.historyDraft = historyDraft
        self.isRunning = isRunning
        self.isSuspended = isSuspended
        self.mouseReporting = mouseReporting
        self.mouseReportingParser = TerminalMouseReportingParser(reporting: mouseReporting)
        self.entries = entries
    }

    mutating func consumeMouseReporting(from output: String) {
        mouseReportingParser.consume(output)
        mouseReporting = mouseReportingParser.reporting
    }

    mutating func resetMouseReporting() {
        mouseReportingParser.reset()
        mouseReporting = mouseReportingParser.reporting
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
