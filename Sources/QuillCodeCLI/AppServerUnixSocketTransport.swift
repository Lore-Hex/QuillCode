import Foundation
import QuillCodePersistence
import QuillCodePlatform

struct AppServerUnixSocketTransport: Sendable {
    private static let controlDirectoryName = "app-server-control"
    private static let defaultSocketName = "app-server-control.sock"

    let runnerFactory: CLIAgentRunnerFactory

    func run(
        request: CLIAppServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        diagnostics: any CLIOutputWriting
    ) async throws {
        let socketURL = try Self.socketURL(for: request)
        let listener = try UnixDomainSocketListener(socketURL: socketURL)
        let connections = AppServerUnixConnectionPool()
        await diagnostics.writeStandardErrorLine(
            "quill-code app-server: listening on unix://\(socketURL.path)"
        )

        var listenerError: (any Error)?
        do {
            while !Task.isCancelled {
                let connection = try await listener.accept()
                await connections.submit { [runnerFactory] in
                    defer { connection.close() }
                    do {
                        try await AppServerConnectionDriver(runnerFactory: runnerFactory).run(
                            request: request,
                            environment: environment,
                            currentDirectory: currentDirectory,
                            lines: Self.lines(from: connection),
                            sink: { line in
                                do {
                                    try await connection.send(Data(line.utf8))
                                } catch {
                                    connection.close()
                                }
                            }
                        )
                    } catch is CancellationError {
                        connection.close()
                    } catch {
                        await diagnostics.writeStandardErrorLine(
                            "quill-code app-server: Unix client disconnected: "
                                + error.localizedDescription
                        )
                    }
                }
            }
        } catch UnixDomainSocketError.cancelled where Task.isCancelled {
            // Parent cancellation closes the listener and is handled by the command runner.
        } catch {
            listenerError = error
        }
        listener.close()
        await connections.cancelAndWait()
        if let listenerError { throw listenerError }
        try Task.checkCancellation()
    }

    static func socketURL(for request: CLIAppServerRequest) throws -> URL {
        guard case .unix(let configuredPath) = request.transport else {
            preconditionFailure("Unix socket URL requested for a non-Unix transport")
        }
        if let configuredPath {
            return URL(fileURLWithPath: configuredPath)
        }

        let paths = request.home.map { QuillCodePaths(home: $0) } ?? QuillCodePaths()
        try paths.ensure()
        let directory = paths.home.appendingPathComponent(
            controlDirectoryName,
            isDirectory: true
        )
        try ensurePrivateControlDirectory(directory)
        return directory.appendingPathComponent(defaultSocketName)
    }

    private static func ensurePrivateControlDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            let attributes = try fileManager.attributesOfItem(atPath: directory.path)
            guard values.isSymbolicLink != true,
                  attributes[.type] as? FileAttributeType == .typeDirectory
            else {
                throw UnixDomainSocketError.listenerUnavailable(directory.path)
            }
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directory.path
            )
            return
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
    }

    private static func lines(
        from connection: UnixDomainSocketConnection
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var framer = CLIInputLineFramer(
                        maxLineBytes: AppServerSession.maximumMessageBytes
                    )
                    while let chunk = try await connection.receive() {
                        for line in try framer.append(chunk) {
                            continuation.yield(line)
                        }
                    }
                    if let finalLine = try framer.finish() {
                        continuation.yield(finalLine)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                connection.close()
            }
        }
    }
}

private actor AppServerUnixConnectionPool {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func submit(_ operation: @escaping @Sendable () async -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            await operation()
            await self?.remove(id)
        }
    }

    func cancelAndWait() async {
        let active = Array(tasks.values)
        tasks.removeAll()
        active.forEach { $0.cancel() }
        for task in active { await task.value }
    }

    private func remove(_ id: UUID) {
        tasks[id] = nil
    }
}
