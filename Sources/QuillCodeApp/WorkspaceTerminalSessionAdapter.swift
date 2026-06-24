import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceTerminalSessionAdapter {
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
        return environmentDelta(baseEnvironment: baseEnvironment, finalEnvironment: finalEnvironment)
    }

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

    static func removeMarkers(_ urls: [URL]) {
        for url in urls {
            removeMarker(at: url)
        }
    }

    nonisolated static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func remoteDisplayPrefix(for connection: ProjectConnection) -> String? {
        guard connection.kind == .ssh,
              let host = connection.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        let userPrefix = connection.user.map { "\($0)@" } ?? ""
        let portSuffix = connection.port.map { ":\($0)" } ?? ""
        return "ssh://\(userPrefix)\(host)\(portSuffix)"
    }

    private static func isValidShellEnvironmentKey(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else {
            return false
        }
        return value.unicodeScalars.dropFirst().allSatisfy {
            $0 == "_" || CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func currentDirectoryPath(for context: WorkspaceTerminalExecutionContext) -> String {
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

    private static let ignoredEnvironmentDeltaKeys: Set<String> = [
        "PWD",
        "OLDPWD",
        "SHLVL",
        "_"
    ]

    private static func environmentDelta(markerURL: URL) -> WorkspaceTerminalEnvironmentDelta? {
        defer { removeMarker(at: markerURL) }
        guard let data = try? Data(contentsOf: markerURL) else {
            return nil
        }
        return environmentDelta(
            baseEnvironment: ProcessInfo.processInfo.environment,
            finalEnvironment: environment(from: data)
        )
    }

    private static func environmentDelta(
        baseEnvironment: [String: String],
        finalEnvironment: [String: String]
    ) -> WorkspaceTerminalEnvironmentDelta {
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

    private static func environment(from data: Data) -> [String: String] {
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

    private static func environment(fromHex hex: String) -> [String: String]? {
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

    private static func removeMarker(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
