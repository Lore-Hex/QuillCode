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

enum WorkspaceTerminalEngine {
    static let stoppedMessage = "Command stopped."
    static let missingRemoteHostMessage = "SSH Remote project is missing a usable host."

    static func normalizedCommand(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canBeginRun(command: String, terminal: TerminalState) -> Bool {
        !command.isEmpty && !terminal.isRunning
    }

    @discardableResult
    static func beginRun(
        command: String,
        entryID: UUID = UUID(),
        terminal: inout TerminalState
    ) -> UUID {
        terminal.draft = ""
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
        removeMarkers(executionContext.markerURLs)
        terminal.isRunning = false
    }

    static func finishCancelledRun(
        id: UUID,
        executionContext: WorkspaceTerminalExecutionContext,
        terminal: inout TerminalState
    ) {
        removeMarkers(executionContext.markerURLs)
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
        let terminalResult = sessionResult(for: executionContext, stdout: result.stdout)
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
    }

    @discardableResult
    static func clearHistory(terminal: inout TerminalState) -> Bool {
        guard !terminal.isRunning else { return false }
        terminal.entries = []
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

    static func executionContext(
        command: String,
        selectedProject: ProjectRef?,
        terminalCurrentDirectoryURL: URL?,
        terminal: TerminalState,
        workspaceRoot: URL,
        sshRemoteShellExecutor: SSHRemoteShellExecutor
    ) -> WorkspaceTerminalExecutionContext? {
        if let selectedProject, selectedProject.isRemote {
            let connection = remoteConnection(
                for: selectedProject,
                terminalCurrentDirectoryPath: terminal.currentDirectoryPath
            )
            let marker = remoteMarker()
            let wrappedCommand = remoteWrappedCommand(
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

        let environment = effectiveEnvironment(
            overrides: terminal.environmentOverrides,
            removedKeys: terminal.removedEnvironmentKeys
        )
        let workingDirectory = terminalCurrentDirectoryURL ?? workspaceRoot.standardizedFileURL
        return localExecutionContext(
            command: command,
            workingDirectory: workingDirectory,
            environment: environment,
            executionContext: .local(path: workingDirectory.standardizedFileURL.path)
        )
    }

    static func localExecutionContext(
        command: String,
        workingDirectory: URL,
        environment: [String: String],
        executionContext: ExecutionContextSurface
    ) -> WorkspaceTerminalExecutionContext {
        let markerID = UUID().uuidString
        let markerDirectory = FileManager.default.temporaryDirectory
        let cwdMarkerURL = markerDirectory.appendingPathComponent("quillcode-terminal-\(markerID).cwd")
        let environmentMarkerURL = markerDirectory.appendingPathComponent("quillcode-terminal-\(markerID).env")
        let cwdMarkerPath = shellSingleQuoted(cwdMarkerURL.path)
        let environmentMarkerPath = shellSingleQuoted(environmentMarkerURL.path)
        let wrappedCommand = """
        \(command)
        status=$?
        printf '%s\n' "$PWD" > \(cwdMarkerPath)
        /usr/bin/env -0 > \(environmentMarkerPath)
        exit "$status"
        """
        return WorkspaceTerminalExecutionContext(
            request: ShellExecutionRequest(
                command: wrappedCommand,
                cwd: workingDirectory,
                environment: environment
            ),
            cwdMarkerURL: cwdMarkerURL,
            environmentMarkerURL: environmentMarkerURL,
            remoteMarker: nil,
            remoteConnection: nil,
            fallbackCurrentDirectoryPath: workingDirectory.standardizedFileURL.path,
            surface: executionContext
        )
    }

    static func remoteConnection(
        for project: ProjectRef,
        terminalCurrentDirectoryPath: String?
    ) -> ProjectConnection {
        var connection = project.connection
        let current = terminalCurrentDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !current.isEmpty else { return connection }
        if current.hasPrefix("/") || current == "~" || current.hasPrefix("~/") {
            connection.path = current
            return connection
        }
        guard let prefix = remoteDisplayPrefix(for: connection),
              current.hasPrefix(prefix) else {
            return connection
        }
        let path = String(current.dropFirst(prefix.count))
        connection.path = path.isEmpty ? "/" : path
        return connection
    }

    static func remoteDisplayPrefix(for connection: ProjectConnection) -> String? {
        guard connection.kind == .ssh,
              let host = connection.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        let userPrefix = connection.user.map { "\($0)@" } ?? ""
        let portSuffix = connection.port.map { ":\($0)" } ?? ""
        return "ssh://\(userPrefix)\(host)\(portSuffix)"
    }

    static func remoteMarker() -> String {
        "__QUILLCODE_TERMINAL_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
    }

    static func remoteWrappedCommand(
        _ command: String,
        marker: String,
        environmentOverrides: [String: String],
        removedEnvironmentKeys: Set<String>
    ) -> String {
        let environmentPreamble = remoteEnvironmentPreamble(
            overrides: environmentOverrides,
            removedKeys: removedEnvironmentKeys
        )
        return """
        __quillcode_base_env="$(/usr/bin/env -0 | od -An -tx1 | tr -d ' \\n')"
        \(environmentPreamble)
        \(command)
        __quillcode_status=$?
        printf '\\n\(marker):cwd\\n%s\\n' "$PWD"
        printf '\(marker):base-env\\n%s\\n' "$__quillcode_base_env"
        printf '\(marker):final-env\\n'
        /usr/bin/env -0 | od -An -tx1 | tr -d ' \\n'
        printf '\\n\(marker):end\\n'
        exit "$__quillcode_status"
        """
    }

    static func remoteEnvironmentPreamble(
        overrides: [String: String],
        removedKeys: Set<String>
    ) -> String {
        let unsetLines = removedKeys
            .filter(isValidShellEnvironmentKey)
            .sorted()
            .map { "unset \($0)" }
        let exportLines = overrides
            .filter { isValidShellEnvironmentKey($0.key) }
            .sorted { $0.key < $1.key }
            .map { "export \($0.key)=\(shellSingleQuoted($0.value))" }
        return (unsetLines + exportLines).joined(separator: "\n")
    }

    static func isValidShellEnvironmentKey(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else {
            return false
        }
        return value.unicodeScalars.dropFirst().allSatisfy {
            $0 == "_" || CharacterSet.alphanumerics.contains($0)
        }
    }

    static func sessionResult(
        for context: WorkspaceTerminalExecutionContext,
        stdout: String
    ) -> WorkspaceTerminalSessionResult {
        if let marker = context.remoteMarker,
           let connection = context.remoteConnection,
           let metadata = remoteMetadata(from: stdout, marker: marker) {
            var updated = connection
            if !metadata.cwd.isEmpty {
                updated.path = metadata.cwd
            }
            return WorkspaceTerminalSessionResult(
                stdout: metadata.stdout,
                currentDirectoryPath: updated.displayLabel,
                environmentDelta: remoteEnvironmentDelta(metadata)
            )
        }

        let sessionEnvironmentDelta: WorkspaceTerminalEnvironmentDelta?
        if let environmentMarkerURL = context.environmentMarkerURL {
            sessionEnvironmentDelta = environmentDelta(markerURL: environmentMarkerURL)
        } else {
            sessionEnvironmentDelta = nil
        }
        return WorkspaceTerminalSessionResult(
            stdout: stdout,
            currentDirectoryPath: currentDirectoryPath(for: context),
            environmentDelta: sessionEnvironmentDelta
        )
    }

    struct RemoteTerminalMetadata {
        var stdout: String
        var cwd: String
        var baseEnvironment: [String: String]?
        var finalEnvironment: [String: String]?
    }

    static func remoteMetadata(from stdout: String, marker: String) -> RemoteTerminalMetadata? {
        let cwdToken = "\n\(marker):cwd\n"
        let baseToken = "\n\(marker):base-env\n"
        let finalToken = "\n\(marker):final-env\n"
        let endToken = "\n\(marker):end\n"
        guard let cwdRange = stdout.range(of: cwdToken) else {
            return nil
        }

        let visibleStdout = String(stdout[..<cwdRange.lowerBound])
        let afterCWDToken = stdout[cwdRange.upperBound...]
        guard let baseRange = afterCWDToken.range(of: baseToken) else {
            return RemoteTerminalMetadata(
                stdout: visibleStdout,
                cwd: String(afterCWDToken).trimmingCharacters(in: .whitespacesAndNewlines),
                baseEnvironment: nil,
                finalEnvironment: nil
            )
        }
        let cwd = String(afterCWDToken[..<baseRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterBaseToken = afterCWDToken[baseRange.upperBound...]
        guard let finalRange = afterBaseToken.range(of: finalToken) else {
            return RemoteTerminalMetadata(
                stdout: visibleStdout,
                cwd: cwd,
                baseEnvironment: nil,
                finalEnvironment: nil
            )
        }
        let baseHex = String(afterBaseToken[..<finalRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterFinalToken = afterBaseToken[finalRange.upperBound...]
        guard let endRange = afterFinalToken.range(of: endToken) else {
            return RemoteTerminalMetadata(
                stdout: visibleStdout,
                cwd: cwd,
                baseEnvironment: nil,
                finalEnvironment: nil
            )
        }
        let finalHex = String(afterFinalToken[..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return RemoteTerminalMetadata(
            stdout: visibleStdout,
            cwd: cwd,
            baseEnvironment: environment(fromHex: baseHex),
            finalEnvironment: environment(fromHex: finalHex)
        )
    }

    static func remoteEnvironmentDelta(
        _ metadata: RemoteTerminalMetadata
    ) -> WorkspaceTerminalEnvironmentDelta? {
        guard let baseEnvironment = metadata.baseEnvironment,
              let finalEnvironment = metadata.finalEnvironment else {
            return nil
        }
        var overrides: [String: String] = [:]
        for (key, value) in finalEnvironment
            where baseEnvironment[key] != value
                && !ignoredEnvironmentDeltaKeys.contains(key) {
            overrides[key] = value
        }
        let removedKeys = Set(baseEnvironment.keys.filter {
            finalEnvironment[$0] == nil && !ignoredEnvironmentDeltaKeys.contains($0)
        })
        return WorkspaceTerminalEnvironmentDelta(overrides: overrides, removedKeys: removedKeys)
    }

    static func currentDirectoryPath(for context: WorkspaceTerminalExecutionContext) -> String {
        guard let markerURL = context.cwdMarkerURL else {
            return context.fallbackCurrentDirectoryPath
        }
        defer { removeMarker(at: markerURL) }
        guard let rawPath = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return context.fallbackCurrentDirectoryPath
        }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return context.fallbackCurrentDirectoryPath
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static let ignoredEnvironmentDeltaKeys: Set<String> = [
        "PWD",
        "OLDPWD",
        "SHLVL",
        "_"
    ]

    static func effectiveEnvironment(
        overrides: [String: String],
        removedKeys: Set<String>
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in removedKeys {
            environment.removeValue(forKey: key)
        }
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }

    static func environmentDelta(markerURL: URL) -> WorkspaceTerminalEnvironmentDelta? {
        defer { removeMarker(at: markerURL) }
        guard let data = try? Data(contentsOf: markerURL) else {
            return nil
        }
        let finalEnvironment = environment(from: data)
        let baseEnvironment = ProcessInfo.processInfo.environment
        var overrides: [String: String] = [:]
        for (key, value) in finalEnvironment
            where baseEnvironment[key] != value
                && !ignoredEnvironmentDeltaKeys.contains(key) {
            overrides[key] = value
        }
        let removedKeys = Set(baseEnvironment.keys.filter {
            finalEnvironment[$0] == nil && !ignoredEnvironmentDeltaKeys.contains($0)
        })
        return WorkspaceTerminalEnvironmentDelta(overrides: overrides, removedKeys: removedKeys)
    }

    static func environment(from data: Data) -> [String: String] {
        var environment: [String: String] = [:]
        for entry in data.split(separator: 0, omittingEmptySubsequences: true) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let equalsIndex = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<equalsIndex])
            let value = String(text[text.index(after: equalsIndex)...])
            guard !key.isEmpty else { continue }
            environment[key] = value
        }
        return environment
    }

    static func environment(fromHex hex: String) -> [String: String]? {
        let scalars = Array(hex.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        guard scalars.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(scalars.count / 2)
        var index = 0
        while index < scalars.count {
            let pair = String(String.UnicodeScalarView([scalars[index], scalars[index + 1]]))
            guard let byte = UInt8(pair, radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        return environment(from: Data(bytes))
    }

    static func removeMarkers(_ urls: [URL]) {
        for url in urls {
            removeMarker(at: url)
        }
    }

    static func removeMarker(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
