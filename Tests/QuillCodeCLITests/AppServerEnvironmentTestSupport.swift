import Foundation
@testable import QuillCodeCLI

actor AppServerFakeExecServerClient: AppServerExecServerClient {
    struct Snapshot: Sendable, Equatable {
        var connectCount: Int
        var closeCount: Int
        var processRequests: [AppServerRemoteProcessRequest]
        var removedURIs: [String]
    }

    private var info: AppServerEnvironmentInfo
    private var infoDelay: Duration?
    private var processDelay: Duration?
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
    private var removedURIs: [String] = []

    init(
        info: AppServerEnvironmentInfo = .init(
            shell: .init(name: "zsh", path: "/bin/zsh"),
            cwd: "file:///workspace"
        ),
        infoDelay: Duration? = nil,
        processDelay: Duration? = nil,
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
        self.connectError = connectError
        self.infoError = infoError
        self.processResults = processResults
        self.files = files
        self.directories = directories
        self.canonicalURIs = canonicalURIs
        self.directoryEntries = directoryEntries
    }

    func connect() throws {
        connectCount += 1
        if let connectError { throw connectError }
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

    func readFile(at pathURI: String) throws -> Data {
        guard let data = files[pathURI] else { throw missing(pathURI) }
        return data
    }

    func writeFile(_ data: Data, at pathURI: String) {
        files[pathURI] = data
    }

    func createDirectory(at pathURI: String, recursive: Bool) {
        directories.insert(pathURI)
    }

    func metadata(at pathURI: String) throws -> AppServerRemoteFileMetadata {
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

    func canonicalize(_ pathURI: String) throws -> String {
        let canonical = canonicalURIs[pathURI] ?? pathURI
        guard directories.contains(pathURI)
                || files[pathURI] != nil
                || directories.contains(canonical)
                || files[canonical] != nil else {
            throw missing(pathURI)
        }
        return canonical
    }

    func readDirectory(at pathURI: String) throws -> [AppServerRemoteDirectoryEntry] {
        guard directories.contains(pathURI) else { throw missing(pathURI) }
        return directoryEntries[pathURI] ?? []
    }

    func remove(at pathURI: String, recursive: Bool, force: Bool) {
        removedURIs.append(pathURI)
        files[pathURI] = nil
        directories.remove(pathURI)
    }

    func close() {
        closeCount += 1
    }

    func setInfoError(_ error: AppServerExecServerError?) {
        infoError = error
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
            removedURIs: removedURIs
        )
    }

    private func missing(_ pathURI: String) -> AppServerExecServerError {
        .remoteRPC(code: -32_000, message: "path not found: \(pathURI)")
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
