import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore

actor AppServerFakeExecServerClient: AppServerExecServerClient {
    struct FileSystemRequest: Sendable, Equatable {
        var method: String
        var pathURI: String
        var sandbox: AppServerExecServerSandboxContext
    }

    struct Snapshot: Sendable, Equatable {
        var connectCount: Int
        var closeCount: Int
        var processRequests: [AppServerRemoteProcessRequest]
        var fileSystemRequests: [FileSystemRequest]
        var removedURIs: [String]
    }

    private var info: AppServerEnvironmentInfo
    private var infoDelay: Duration?
    private var processDelay: Duration?
    private var connectDelay: Duration?
    private var connectError: AppServerExecServerError?
    private var infoError: AppServerExecServerError?
    private var processResults: [AppServerRemoteProcessResult]
    private var files: [String: Data]
    private var directories: Set<String>
    private var canonicalURIs: [String: String]
    private var directoryEntries: [String: [AppServerRemoteDirectoryEntry]]
    private var connectCount = 0
    private var closeCount = 0
    private var processRequests: [AppServerRemoteProcessRequest] = []
    private var fileSystemRequests: [FileSystemRequest] = []
    private var removedURIs: [String] = []
    private var currentConnectionSnapshot: AppServerEnvironmentConnectionSnapshot = .pending
    private var connected = false
    private var lastPublishedConnectionState: AppServerEnvironmentConnectionState?
    private var connectionEventContinuations:
        [UUID: AsyncStream<AppServerExecServerConnectionObservation>.Continuation] = [:]

    init(
        info: AppServerEnvironmentInfo = .init(
            shell: .init(name: "zsh", path: "/bin/zsh"),
            cwd: "file:///workspace"
        ),
        infoDelay: Duration? = nil,
        processDelay: Duration? = nil,
        connectDelay: Duration? = nil,
        connectError: AppServerExecServerError? = nil,
        infoError: AppServerExecServerError? = nil,
        processResults: [AppServerRemoteProcessResult] = [],
        files: [String: Data] = [:],
        directories: Set<String> = ["file:///workspace"],
        canonicalURIs: [String: String] = [:],
        directoryEntries: [String: [AppServerRemoteDirectoryEntry]] = [:]
    ) {
        self.info = info
        self.infoDelay = infoDelay
        self.processDelay = processDelay
        self.connectDelay = connectDelay
        self.connectError = connectError
        self.infoError = infoError
        self.processResults = processResults
        self.files = files
        self.directories = directories
        self.canonicalURIs = canonicalURIs
        self.directoryEntries = directoryEntries
    }

    func connect() async throws {
        connectCount += 1
        currentConnectionSnapshot = .pending
        if let connectDelay { try await Task.sleep(for: connectDelay) }
        if let connectError {
            currentConnectionSnapshot = .disconnected(connectError.errorDescription)
            transitionConnectionState(to: .disconnected)
            throw connectError
        }
        currentConnectionSnapshot = .ready
        guard !connected else { return }
        connected = true
        transitionConnectionState(to: .connected)
    }

    func connectionSnapshot() -> AppServerEnvironmentConnectionSnapshot {
        currentConnectionSnapshot
    }

    func connectionEvents() -> AsyncStream<AppServerExecServerConnectionObservation> {
        let identifier = UUID()
        let pair = AsyncStream<AppServerExecServerConnectionObservation>.makeStream()
        connectionEventContinuations[identifier] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeConnectionEventContinuation(identifier) }
        }
        return pair.stream
    }

    func environmentInfo() async throws -> AppServerEnvironmentInfo {
        if let infoDelay { try await Task.sleep(for: infoDelay) }
        if let infoError { throw infoError }
        return info
    }

    func runProcess(
        _ request: AppServerRemoteProcessRequest
    ) async throws -> AppServerRemoteProcessResult {
        processRequests.append(request)
        if let processDelay { try await Task.sleep(for: processDelay) }
        guard !processResults.isEmpty else {
            return .init(
                stdout: "",
                stderr: "",
                exitCode: 0,
                failure: nil,
                sandboxDenied: false
            )
        }
        return processResults.removeFirst()
    }

    func readFile(
        at pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) throws -> Data {
        recordFileSystemRequest("fs/readFile", pathURI: pathURI, sandbox: sandbox)
        guard let data = files[pathURI] else { throw missing(pathURI) }
        return data
    }

    func writeFile(
        _ data: Data,
        at pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) {
        recordFileSystemRequest("fs/writeFile", pathURI: pathURI, sandbox: sandbox)
        files[pathURI] = data
    }

    func createDirectory(
        at pathURI: String,
        recursive: Bool,
        sandbox: AppServerExecServerSandboxContext
    ) {
        recordFileSystemRequest("fs/createDirectory", pathURI: pathURI, sandbox: sandbox)
        directories.insert(pathURI)
    }

    func metadata(
        at pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) throws -> AppServerRemoteFileMetadata {
        recordFileSystemRequest("fs/getMetadata", pathURI: pathURI, sandbox: sandbox)
        if directories.contains(pathURI) {
            return .init(isDirectory: true, isFile: false, isSymbolicLink: false, size: 0)
        }
        guard let data = files[pathURI] else { throw missing(pathURI) }
        return .init(
            isDirectory: false,
            isFile: true,
            isSymbolicLink: false,
            size: UInt64(data.count)
        )
    }

    func canonicalize(
        _ pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) throws -> String {
        recordFileSystemRequest("fs/canonicalize", pathURI: pathURI, sandbox: sandbox)
        let canonical = canonicalURIs[pathURI] ?? pathURI
        guard directories.contains(pathURI)
                || files[pathURI] != nil
                || directories.contains(canonical)
                || files[canonical] != nil else {
            throw missing(pathURI)
        }
        return canonical
    }

    func readDirectory(
        at pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) throws -> [AppServerRemoteDirectoryEntry] {
        recordFileSystemRequest("fs/readDirectory", pathURI: pathURI, sandbox: sandbox)
        guard directories.contains(pathURI) else { throw missing(pathURI) }
        return directoryEntries[pathURI] ?? []
    }

    func remove(
        at pathURI: String,
        recursive: Bool,
        force: Bool,
        sandbox: AppServerExecServerSandboxContext
    ) {
        recordFileSystemRequest("fs/remove", pathURI: pathURI, sandbox: sandbox)
        removedURIs.append(pathURI)
        files[pathURI] = nil
        directories.remove(pathURI)
    }

    func close() {
        closeCount += 1
        if connected {
            connected = false
            currentConnectionSnapshot = .disconnected("closed")
            transitionConnectionState(to: .disconnected)
        }
        for continuation in connectionEventContinuations.values {
            continuation.finish()
        }
        connectionEventContinuations.removeAll()
    }

    func setInfoError(_ error: AppServerExecServerError?) {
        infoError = error
    }

    func setConnectionSnapshot(_ snapshot: AppServerEnvironmentConnectionSnapshot) {
        currentConnectionSnapshot = snapshot
        connected = snapshot.isConnected
        transitionConnectionState(to: connected ? .connected : .disconnected)
    }

    func emitConnectionState(_ state: AppServerEnvironmentConnectionState) {
        connected = state == .connected
        currentConnectionSnapshot = connected
            ? .ready
            : .disconnected("connection closed")
        transitionConnectionState(to: state)
    }

    func setProcessResults(_ results: [AppServerRemoteProcessResult]) {
        processResults = results
    }

    func setFile(_ data: Data, at pathURI: String) {
        files[pathURI] = data
    }

    func setCanonicalURI(_ canonicalURI: String, for pathURI: String) {
        canonicalURIs[pathURI] = canonicalURI
    }

    func file(at pathURI: String) -> Data? {
        files[pathURI]
    }

    func snapshot() -> Snapshot {
        Snapshot(
            connectCount: connectCount,
            closeCount: closeCount,
            processRequests: processRequests,
            fileSystemRequests: fileSystemRequests,
            removedURIs: removedURIs
        )
    }

    private func recordFileSystemRequest(
        _ method: String,
        pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) {
        fileSystemRequests.append(.init(
            method: method,
            pathURI: pathURI,
            sandbox: sandbox
        ))
    }

    private func missing(_ pathURI: String) -> AppServerExecServerError {
        .remoteRPC(code: -32_000, message: "path not found: \(pathURI)")
    }

    private func transitionConnectionState(to state: AppServerEnvironmentConnectionState) {
        guard state != lastPublishedConnectionState else { return }
        lastPublishedConnectionState = state
        let observation = AppServerExecServerConnectionObservation(
            state: state,
            observedAt: ContinuousClock.now
        )
        for continuation in connectionEventContinuations.values {
            continuation.yield(observation)
        }
    }

    private func removeConnectionEventContinuation(_ identifier: UUID) {
        connectionEventContinuations[identifier] = nil
    }
}

final class AppServerFakeExecServerFactory: @unchecked Sendable {
    struct Registration: Sendable {
        var websocketURL: String
        var connectTimeout: TimeInterval
        var client: AppServerFakeExecServerClient
    }

    private let lock = NSLock()
    private var clients: [AppServerFakeExecServerClient]
    private var registrations: [Registration] = []

    init(clients: [AppServerFakeExecServerClient]) {
        self.clients = clients
    }

    func make(
        websocketURL: String,
        connectTimeout: TimeInterval
    ) -> any AppServerExecServerClient {
        lock.lock()
        defer { lock.unlock() }
        precondition(!clients.isEmpty, "No fake exec-server client remains")
        let client = clients.removeFirst()
        registrations.append(.init(
            websocketURL: websocketURL,
            connectTimeout: connectTimeout,
            client: client
        ))
        return client
    }

    func snapshot() -> [Registration] {
        lock.lock()
        defer { lock.unlock() }
        return registrations
    }
}

struct EnvironmentSessionFixture {
    var session: AppServerSession
    var output: EnvironmentSessionOutputCollector
    var workspace: URL
}

actor EnvironmentSessionOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let value = try CLIJSONCodec.decode(line).objectValue else {
                throw EnvironmentSessionTestError.invalidRecord
            }
            return value
        }
    }
}

struct EnvironmentEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) -> AgentAction {
        .say(userMessage)
    }
}

actor EnvironmentScriptedLLM: LLMClient {
    struct Observation: Sendable {
        var messages: [ChatMessage]
        var toolNames: Set<String>
    }

    private var actions: [AgentAction]
    private var captured: [Observation] = []

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) -> AgentAction {
        captured.append(.init(messages: thread.messages, toolNames: Set(tools.map(\.name))))
        guard !actions.isEmpty else { return .say("No scripted action remains.") }
        return actions.removeFirst()
    }

    func observations() -> [Observation] {
        captured
    }
}

enum EnvironmentSessionTestError: Error {
    case invalidRecord
}
