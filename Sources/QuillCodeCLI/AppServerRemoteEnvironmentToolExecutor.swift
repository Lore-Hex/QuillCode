import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

actor AppServerRemoteEnvironmentToolExecutor {
    private static let remoteToolDefinitions: [ToolDefinition] = [
        .shellRun,
        .fileRead,
        .fileList,
        .fileSearch,
        .fileWrite,
        .applyPatch
    ]
    static let remotelyExecutedToolNames = Set(remoteToolDefinitions.map(\.name))
    static let toolDefinitions = remoteToolDefinitions + [.webSearch]

    private static let shellDefaultTimeout: TimeInterval = 30
    private static let shellMaximumTimeout = 1_800
    private static let maximumStandardInputBytes = 1_048_576
    private static let defaultListLimit = 200
    private static let maximumListLimit = 500
    private static let defaultSearchLimit = 20
    private static let maximumSearchLimit = 100

    let environmentID: String
    let environmentInfo: AppServerEnvironmentInfo
    let workspace: AppServerRemoteWorkspacePath

    private let client: any AppServerExecServerClient
    private let sandbox: AppServerExecServerSandboxContext
    private let managedNetwork: AppServerManagedNetworkPolicy
    private var readFileURIs: Set<String> = []

    init(
        environmentID: String,
        cwd: String,
        environmentInfo: AppServerEnvironmentInfo,
        sandboxPolicy: AppServerSandboxPolicy,
        requirements: ManagedRequirements? = nil,
        client: any AppServerExecServerClient
    ) throws {
        self.environmentID = environmentID
        self.environmentInfo = environmentInfo
        let workspace = try AppServerRemoteWorkspacePath(
            cwd: cwd,
            fallbackCWDURI: environmentInfo.cwd
        )
        self.workspace = workspace
        self.sandbox = try AppServerExecServerSandboxContext(
            policy: sandboxPolicy,
            workspace: workspace
        )
        self.managedNetwork = AppServerManagedNetworkPolicy(requirements: requirements)
        self.client = client
    }

    var logicalWorkspaceURL: URL {
        URL(fileURLWithPath: workspace.root.nativePath, isDirectory: true)
    }

    var modelEnvironmentContext: String {
        """
        <environment_context>
          <environment_id>\(AppServerModelContextXML.escaped(environmentID))</environment_id>
          <cwd>\(AppServerModelContextXML.escaped(workspace.root.nativePath))</cwd>
          <shell>\(AppServerModelContextXML.escaped(environmentInfo.shell.name))</shell>
        </environment_context>
        """
    }

    func execute(_ call: ToolCall) async -> ToolResult {
        await execute(call, shellTimeoutOverride: nil)
    }

    func executeUserShell(
        _ call: ToolCall,
        timeoutSeconds: TimeInterval
    ) async -> ToolResult {
        await execute(call, shellTimeoutOverride: timeoutSeconds)
    }

    func startUserShell(
        command: String,
        processID: Int32,
        timeoutSeconds: TimeInterval
    ) async throws -> AppServerRemoteProcessSession {
        let canonicalCWD = try await canonicalized(workspace.root)
        return try await client.startProcess(.init(
            processID: processID.description,
            argv: Self.shellArguments(shell: environmentInfo.shell, command: command),
            cwdURI: canonicalCWD.uri,
            environment: [:],
            sandbox: sandbox,
            managedNetwork: managedNetwork,
            timeoutSeconds: try validatedInternalShellTimeout(timeoutSeconds)
        ))
    }

    private func execute(
        _ call: ToolCall,
        shellTimeoutOverride: TimeInterval?
    ) async -> ToolResult {
        do {
            switch call.name {
            case ToolDefinition.shellRun.name:
                return try await runShell(
                    ToolArguments(call.argumentsJSON),
                    timeoutOverride: shellTimeoutOverride
                )
            case ToolDefinition.fileRead.name:
                return try await readFile(ToolArguments(call.argumentsJSON))
            case ToolDefinition.fileList.name:
                return try await listFiles(ToolArguments(call.argumentsJSON))
            case ToolDefinition.fileSearch.name:
                return try await searchFiles(ToolArguments(call.argumentsJSON))
            case ToolDefinition.fileWrite.name:
                return try await writeFile(ToolArguments(call.argumentsJSON))
            case ToolDefinition.applyPatch.name:
                return try await applyPatch(ToolArguments(call.argumentsJSON))
            default:
                return ToolResult(
                    ok: false,
                    error: "Tool is not available in remote environment \(environmentID): \(call.name)"
                )
            }
        } catch {
            return ToolResult(ok: false, error: Self.errorMessage(error))
        }
    }

    private func runShell(
        _ arguments: ToolArguments,
        timeoutOverride: TimeInterval? = nil
    ) async throws -> ToolResult {
        let command = try arguments.requiredString("cmd")
        let cwd = try workspace.resolve(
            arguments.string("cwd") ?? ".",
            defaultingToRoot: true
        )
        let canonicalCWD = try await canonicalized(cwd)
        let timeout = try timeoutOverride.map(validatedInternalShellTimeout)
            ?? shellTimeout(arguments)
        let environment = try shellEnvironment(arguments)
        let standardInput = try shellStandardInput(arguments)

        guard let standardInput else {
            return try await runCommand(
                command,
                cwd: canonicalCWD,
                environment: environment,
                timeout: timeout
            )
        }

        let temporary = try await temporaryFile(data: Data(standardInput.utf8), suffix: "stdin")
        let wrapped = "(\(command)) < \(shellSingleQuoted(temporary.nativePath))"
        let result: ToolResult
        do {
            result = try await runCommand(
                wrapped,
                cwd: canonicalCWD,
                environment: environment,
                timeout: timeout
            )
        } catch {
            try? await client.remove(
                at: temporary.uri,
                recursive: false,
                force: true,
                sandbox: sandbox
            )
            throw error
        }
        try? await client.remove(
            at: temporary.uri,
            recursive: false,
            force: true,
            sandbox: sandbox
        )
        return result
    }

    private func readFile(_ arguments: ToolArguments) async throws -> ToolResult {
        let requested = try arguments.requiredString("path")
        let resolved = try workspace.resolve(requested)
        let canonical = try await canonicalized(resolved)
        let data = try await client.readFile(at: canonical.uri, sandbox: sandbox)
        if FileReadRenderer.isProbablyBinary(data) {
            return ToolResult(
                ok: true,
                stdout: FileReadRenderer.binaryDescription(
                    data,
                    fileName: canonical.nativePath.split(separator: "/").last.map(String.init)
                        ?? requested
                ),
                artifacts: [canonical.nativePath]
            )
        }
        let text = FileEncodingPreservation.normalizeForDisplay(
            String(decoding: data, as: UTF8.self)
        )
        let offset = arguments.int("offset")
        if Self.readWindowShowsContent(text, offset: offset) {
            readFileURIs.insert(canonical.uri)
        }
        return ToolResult(
            ok: true,
            stdout: FileReadRenderer.render(
                text,
                offset: offset,
                limit: arguments.int("limit")
            ),
            artifacts: [canonical.nativePath]
        )
    }

    private func listFiles(_ arguments: ToolArguments) async throws -> ToolResult {
        let requested = arguments.string("path") ?? "."
        let resolved = try workspace.resolve(requested, defaultingToRoot: true)
        let canonical = try await canonicalized(resolved)
        let metadata = try await client.metadata(at: canonical.uri, sandbox: sandbox)
        guard metadata.isDirectory else { throw FileToolError.notDirectory(requested) }

        let includeHidden = arguments.bool("includeHidden") ?? false
        let allEntries = try await client.readDirectory(
            at: canonical.uri,
            sandbox: sandbox
        )
            .filter { includeHidden || !$0.fileName.hasPrefix(".") }
            .sorted(by: Self.entrySort)
        let limit = min(
            max(arguments.int("maxEntries") ?? Self.defaultListLimit, 1),
            Self.maximumListLimit
        )
        let entries = allEntries.prefix(limit).map { entry in
            FileListEntry(
                name: entry.fileName,
                path: resolved.relativePath == "."
                    ? entry.fileName
                    : "\(resolved.relativePath)/\(entry.fileName)",
                kind: entry.isDirectory ? "directory" : (entry.isFile ? "file" : "other"),
                bytes: nil,
                isHidden: entry.fileName.hasPrefix(".")
            )
        }
        let output = FileListToolOutput(
            path: resolved.relativePath,
            entries: Array(entries),
            totalEntries: allEntries.count,
            includedHidden: includeHidden,
            truncated: allEntries.count > entries.count
        )
        return ToolResult(
            ok: true,
            stdout: Self.encode(output),
            artifacts: entries.compactMap { try? workspace.resolve($0.path).nativePath }
        )
    }

    private func searchFiles(_ arguments: ToolArguments) async throws -> ToolResult {
        let query = try arguments.requiredString("query")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw FileToolError.emptySearchQuery }
        let requested = arguments.string("path") ?? "."
        let resolved = try workspace.resolve(requested, defaultingToRoot: true)
        let canonical = try await canonicalized(resolved)
        let limit = min(
            max(arguments.int("maxResults") ?? Self.defaultSearchLimit, 1),
            Self.maximumSearchLimit
        )
        var scanner = RemoteFileSearchScanner(
            client: client,
            sandbox: sandbox,
            workspace: workspace,
            query: query,
            limit: limit
        )
        let matches = try await scanner.search(startingAt: canonical)
        let output = FileSearchToolOutput(
            query: query,
            path: canonical.relativePath,
            matches: matches,
            scannedFiles: scanner.scannedFiles,
            skippedFiles: scanner.skippedFiles,
            truncated: scanner.truncated
        )
        return ToolResult(
            ok: true,
            stdout: Self.encode(output),
            artifacts: matches.compactMap { try? workspace.resolve($0.path).nativePath }
        )
    }

    private func writeFile(_ arguments: ToolArguments) async throws -> ToolResult {
        let requested = try arguments.requiredString("path")
        let content = try arguments.requiredString("content", allowingEmpty: true)
        let resolved = try workspace.resolve(requested)
        let parent = try workspace.parent(of: resolved)
        try await validateNearestExistingParent(of: parent)

        let existingMetadata = try await optionalMetadata(at: resolved.uri)
        if existingMetadata?.isDirectory == true {
            throw FileToolError.notDirectory(requested)
        }
        let existingCanonical = existingMetadata == nil ? nil : try await canonicalized(resolved)
        if let existingCanonical, !readFileURIs.contains(existingCanonical.uri) {
            throw FileEditGuardError.writeWithoutRead(requested)
        }
        let existingData = existingMetadata == nil
            ? nil
            : try await client.readFile(at: resolved.uri, sandbox: sandbox)
        let style = existingData.map(FileEncodingPreservation.detect) ?? .default
        let data = FileEncodingPreservation.apply(content, style: style)
        if existingData == data { throw FileEditGuardError.noOpWrite(requested) }

        try await client.createDirectory(
            at: parent.uri,
            recursive: true,
            sandbox: sandbox
        )
        try await client.writeFile(data, at: resolved.uri, sandbox: sandbox)
        let written = try await canonicalized(resolved)
        readFileURIs.insert(written.uri)
        return ToolResult(
            ok: true,
            stdout: "Wrote \(written.nativePath)\n",
            artifacts: [written.nativePath]
        )
    }

    private func applyPatch(_ arguments: ToolArguments) async throws -> ToolResult {
        var patch = try arguments.requiredString("patch")
        guard !patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PatchToolError.emptyPatch
        }
        if let unsafe = PatchToolExecutor.unsafePath(in: patch) {
            throw PatchToolError.unsafePath(unsafe)
        }
        if !patch.hasSuffix("\n") { patch.append("\n") }
        let targets = PatchToolExecutor.targetPaths(in: patch)
        for target in targets {
            let resolved = try workspace.resolve(target)
            guard try await optionalMetadata(at: resolved.uri) != nil else { continue }
            let canonical = try await canonicalized(resolved)
            guard readFileURIs.contains(canonical.uri) else {
                throw FileEditGuardError.patchWithoutRead(target)
            }
        }

        let temporary = try await temporaryFile(data: Data(patch.utf8), suffix: "patch")
        let quoted = shellSingleQuoted(temporary.relativePath)
        let strict = "git apply --check \(quoted) && git apply \(quoted)"
        let executionResult: ToolResult
        do {
            var attempted = try await runCommand(
                strict,
                cwd: workspace.root,
                environment: [:],
                timeout: 60
            )
            if !attempted.ok {
                let recount = "git apply --check --recount \(quoted) && git apply --recount \(quoted)"
                let fallback = try await runCommand(
                    recount,
                    cwd: workspace.root,
                    environment: [:],
                    timeout: 60
                )
                if fallback.ok {
                    attempted = fallback
                    attempted.stdout = "Patch applied after recounting hunk headers.\n" + attempted.stdout
                }
            }
            executionResult = attempted
        } catch {
            try? await client.remove(
                at: temporary.uri,
                recursive: false,
                force: true,
                sandbox: sandbox
            )
            throw error
        }
        try? await client.remove(
            at: temporary.uri,
            recursive: false,
            force: true,
            sandbox: sandbox
        )
        guard executionResult.ok else { return executionResult }

        var result = executionResult
        var artifacts: [String] = []
        for target in targets {
            let resolved = try workspace.resolve(target)
            if let canonical = try? await canonicalized(resolved) {
                readFileURIs.insert(canonical.uri)
                artifacts.append(canonical.nativePath)
            }
        }
        result.artifacts = artifacts
        if result.stdout.isEmpty { result.stdout = "Patch applied.\n" }
        return result
    }

    private func runCommand(
        _ command: String,
        cwd: AppServerRemoteWorkspacePath.Resolved,
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> ToolResult {
        let process = try await client.runProcess(.init(
            argv: Self.shellArguments(shell: environmentInfo.shell, command: command),
            cwdURI: cwd.uri,
            environment: environment,
            sandbox: sandbox,
            managedNetwork: managedNetwork,
            timeoutSeconds: timeout
        ))
        return Self.toolResult(from: process)
    }

    nonisolated static func toolResult(
        from process: AppServerRemoteProcessResult
    ) -> ToolResult {
        let ok = process.exitCode == 0 && process.failure == nil && !process.sandboxDenied
        let error: String?
        if process.sandboxDenied {
            error = "The remote environment sandbox denied this command."
        } else if let failure = process.failure {
            error = failure
        } else if !ok {
            error = "Command failed with exit code \(process.exitCode)."
        } else {
            error = nil
        }
        return ToolResult(
            ok: ok,
            stdout: process.stdout,
            stderr: process.stderr,
            exitCode: process.exitCode,
            error: error
        )
    }

    private func canonicalized(
        _ path: AppServerRemoteWorkspacePath.Resolved
    ) async throws -> AppServerRemoteWorkspacePath.Resolved {
        let canonicalURI = try await client.canonicalize(path.uri, sandbox: sandbox)
        guard let canonical = workspace.canonical(canonicalURI) else {
            throw AppServerRemotePathError.outsideWorkspace(path.nativePath)
        }
        return canonical
    }

    private func optionalMetadata(at uri: String) async throws -> AppServerRemoteFileMetadata? {
        do {
            return try await client.metadata(at: uri, sandbox: sandbox)
        } catch let error as AppServerExecServerError {
            guard case .remoteRPC(_, let message) = error,
                  Self.isMissingPathError(message) else {
                throw error
            }
            return nil
        }
    }

    private func validateNearestExistingParent(
        of requested: AppServerRemoteWorkspacePath.Resolved
    ) async throws {
        var candidate = requested
        while try await optionalMetadata(at: candidate.uri) == nil {
            let parent = try workspace.parent(of: candidate)
            guard parent != candidate else {
                throw FileToolError.pathNotFound(workspace.root.nativePath)
            }
            candidate = parent
        }
        let canonical = try await canonicalized(candidate)
        let metadata = try await client.metadata(at: canonical.uri, sandbox: sandbox)
        guard metadata.isDirectory else {
            throw FileToolError.notDirectory(candidate.relativePath)
        }
    }

    private func temporaryFile(
        data: Data,
        suffix: String
    ) async throws -> AppServerRemoteWorkspacePath.Resolved {
        let directory = try workspace.resolve(".quillcode/tmp")
        try await validateNearestExistingParent(of: directory)
        try await client.createDirectory(
            at: directory.uri,
            recursive: true,
            sandbox: sandbox
        )
        let file = try workspace.resolve(
            ".quillcode/tmp/\(UUID().uuidString.lowercased()).\(suffix)"
        )
        try await client.writeFile(data, at: file.uri, sandbox: sandbox)
        return file
    }

    private func shellTimeout(_ arguments: ToolArguments) throws -> TimeInterval {
        guard let raw = arguments.string("timeoutSeconds")
            ?? arguments.string("timeout_seconds") else {
            return Self.shellDefaultTimeout
        }
        guard let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...Self.shellMaximumTimeout).contains(value) else {
            throw AppServerRemoteToolError.invalidArguments(
                "Shell timeoutSeconds must be between 1 and \(Self.shellMaximumTimeout)."
            )
        }
        return TimeInterval(value)
    }

    private func validatedInternalShellTimeout(_ value: TimeInterval) throws -> TimeInterval {
        guard value.isFinite, value > 0 else {
            throw AppServerRemoteToolError.invalidArguments(
                "Internal shell timeout must be a positive finite number."
            )
        }
        return value
    }

    private func shellEnvironment(_ arguments: ToolArguments) throws -> [String: String] {
        let raw = arguments.stringDictionary("environment")
            ?? arguments.stringDictionary("env")
        switch EnvironmentOverridePolicy.validateOverrides(raw) {
        case .allowed(let value): return value
        case .denied(let error): throw AppServerRemoteToolError.invalidArguments(error)
        }
    }

    private func shellStandardInput(_ arguments: ToolArguments) throws -> String? {
        guard let input = arguments.string("stdin") else { return nil }
        guard input.utf8.count <= Self.maximumStandardInputBytes else {
            throw AppServerRemoteToolError.invalidArguments(
                "Shell stdin must be at most \(Self.maximumStandardInputBytes) UTF-8 bytes."
            )
        }
        return input
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func shellArguments(
        shell: AppServerEnvironmentInfo.Shell,
        command: String
    ) -> [String] {
        switch shell.name.lowercased() {
        case "powershell", "pwsh":
            [shell.path, "-NoLogo", "-NoProfile", "-Command", command]
        case "cmd", "cmd.exe":
            [shell.path, "/D", "/S", "/C", command]
        default:
            [shell.path, "-lc", command]
        }
    }

    private static func entrySort(
        _ lhs: AppServerRemoteDirectoryEntry,
        _ rhs: AppServerRemoteDirectoryEntry
    ) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        let order = lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName)
        return order == .orderedSame ? lhs.fileName < rhs.fileName : order == .orderedAscending
    }

    private static func readWindowShowsContent(_ text: String, offset: Int?) -> Bool {
        let start = max(1, offset ?? 1)
        guard start > 1 else { return true }
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if text.hasSuffix("\n"), lines.last == "" { lines.removeLast() }
        return start <= lines.count
    }

    private static func isMissingPathError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("not found")
            || normalized.contains("no such file")
            || normalized.contains("does not exist")
    }

    private static func encode<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func errorMessage(_ error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }
}

private enum AppServerRemoteToolError: Error, LocalizedError, Sendable, Equatable {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): message
        }
    }
}

private struct RemoteFileSearchScanner {
    private static let maximumSearchFileBytes = 1_000_000
    private static let maximumSearchScannedFiles = 2_000
    private static let maximumSearchPreviewCharacters = 240
    private static let excludedDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "build",
        "node_modules"
    ]

    private let client: any AppServerExecServerClient
    private let sandbox: AppServerExecServerSandboxContext
    private let workspace: AppServerRemoteWorkspacePath
    private let query: String
    private let lowercasedQuery: String
    private let limit: Int

    private(set) var scannedFiles = 0
    private(set) var skippedFiles = 0
    private(set) var truncated = false
    private var matches: [FileSearchMatch] = []

    init(
        client: any AppServerExecServerClient,
        sandbox: AppServerExecServerSandboxContext,
        workspace: AppServerRemoteWorkspacePath,
        query: String,
        limit: Int
    ) {
        self.client = client
        self.sandbox = sandbox
        self.workspace = workspace
        self.query = query
        self.lowercasedQuery = query.lowercased()
        self.limit = limit
    }

    mutating func search(
        startingAt root: AppServerRemoteWorkspacePath.Resolved
    ) async throws -> [FileSearchMatch] {
        try await scan(root)
        return matches
    }

    private mutating func scan(
        _ path: AppServerRemoteWorkspacePath.Resolved
    ) async throws {
        guard !truncated else { return }
        let metadata = try await client.metadata(
            at: path.uri,
            sandbox: sandbox
        )
        if metadata.isDirectory {
            guard !shouldSkipDirectory(path) else { return }
            let entries = try await client.readDirectory(
                at: path.uri,
                sandbox: sandbox
            )
                .sorted(by: Self.entrySort)
            for entry in entries {
                guard !truncated else { break }
                let child = try workspace.resolve(
                    path.relativePath == "."
                        ? entry.fileName
                        : "\(path.relativePath)/\(entry.fileName)"
                )
                if entry.isDirectory {
                    guard !shouldSkipDirectory(child) else { continue }
                    try await scan(child)
                } else if entry.isFile {
                    try await scanFile(child)
                } else {
                    skippedFiles += 1
                }
            }
            return
        }
        guard metadata.isFile else {
            skippedFiles += 1
            return
        }
        try await scanFile(path, metadata: metadata)
    }

    private mutating func scanFile(
        _ path: AppServerRemoteWorkspacePath.Resolved,
        metadata knownMetadata: AppServerRemoteFileMetadata? = nil
    ) async throws {
        guard matches.count < limit,
              scannedFiles < Self.maximumSearchScannedFiles else {
            truncated = true
            return
        }
        let metadata: AppServerRemoteFileMetadata
        if let knownMetadata {
            metadata = knownMetadata
        } else {
            metadata = try await client.metadata(
                at: path.uri,
                sandbox: sandbox
            )
        }
        guard metadata.isFile else {
            skippedFiles += 1
            return
        }
        guard metadata.size <= Self.maximumSearchFileBytes else {
            skippedFiles += 1
            return
        }
        let data = try await client.readFile(
            at: path.uri,
            sandbox: sandbox
        )
        guard let text = String(data: data, encoding: .utf8) else {
            skippedFiles += 1
            return
        }
        scannedFiles += 1
        appendMatches(in: text, path: path.relativePath)
    }

    private mutating func appendMatches(in text: String, path: String) {
        for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
            guard matches.count < limit else {
                truncated = true
                return
            }
            guard line.lowercased().contains(lowercasedQuery) else { continue }
            matches.append(FileSearchMatch(
                path: path,
                line: offset + 1,
                preview: Self.boundedSearchPreview(line)
            ))
        }
    }

    private func shouldSkipDirectory(
        _ path: AppServerRemoteWorkspacePath.Resolved
    ) -> Bool {
        guard path.relativePath != "." else { return false }
        let name = path.relativePath.split(separator: "/").last.map(String.init)
        guard let name else { return false }
        return Self.excludedDirectoryNames.contains(name)
    }

    private static func entrySort(
        _ lhs: AppServerRemoteDirectoryEntry,
        _ rhs: AppServerRemoteDirectoryEntry
    ) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        let order = lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName)
        return order == .orderedSame ? lhs.fileName < rhs.fileName : order == .orderedAscending
    }

    private static func boundedSearchPreview(_ line: String) -> String {
        let collapsed = line
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maximumSearchPreviewCharacters else {
            return collapsed
        }
        return "\(collapsed.prefix(maximumSearchPreviewCharacters))..."
    }
}
