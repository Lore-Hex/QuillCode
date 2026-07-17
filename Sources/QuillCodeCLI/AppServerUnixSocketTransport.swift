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
        let connections = AppServerSocketConnectionPool()
        let runtimeFeatureStore = AppServerRuntimeFeatureStore()
        let environmentRegistry = AppServerEnvironmentRegistry(
            localCWD: currentDirectory,
            environment: environment
        )
        await diagnostics.writeStandardErrorLine(
            "quill-code app-server: listening on unix://\(socketURL.path)"
        )

        var listenerError: (any Error)?
        do {
            while !Task.isCancelled {
                let connection = try await listener.accept()
                let accepted = await connections.submit { [runnerFactory] in
                    defer { connection.close() }
                    do {
                        try await AppServerWebSocketConnectionHandler(
                            runnerFactory: runnerFactory,
                            runtimeFeatureStore: runtimeFeatureStore,
                            environmentRegistry: environmentRegistry
                        ).run(
                            request: request,
                            environment: environment,
                            currentDirectory: currentDirectory,
                            connection: connection,
                            authPolicy: try AppServerWebSocketAuthPolicy(
                                configuration: CLIAppServerWebSocketAuth()
                            )
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
                if !accepted { connection.close() }
            }
        } catch UnixDomainSocketError.cancelled where Task.isCancelled {
            // Parent cancellation closes the listener and is handled by the command runner.
        } catch {
            listenerError = error
        }
        listener.close()
        await connections.cancelAndWait()
        await environmentRegistry.closeAll()
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

}
