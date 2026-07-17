import Foundation
import QuillCodeCore

public actor SSHRemoteAppServerPool: SSHRemoteAppServerExecuting {
    private struct ConnectionKey: Hashable, Sendable {
        var host: String
        var user: String?
        var port: Int?
        var path: String

        init(_ connection: ProjectConnection) {
            host = connection.host ?? ""
            user = connection.user
            port = connection.port
            path = connection.path
        }
    }

    private let sshExecutor: SSHRemoteShellExecutor
    private let quillCodeExecutable: String
    private let environment: [String: String]
    private let handshakeTimeoutSeconds: TimeInterval
    private var clients: [ConnectionKey: SSHRemoteAppServerClient] = [:]

    public init(
        sshExecutable: String = "ssh",
        quillCodeExecutable: String = "quill-code",
        connectTimeoutSeconds: Int = 10,
        handshakeTimeoutSeconds: TimeInterval = 15,
        environment: [String: String] = [:]
    ) {
        self.sshExecutor = SSHRemoteShellExecutor(
            sshExecutable: sshExecutable,
            connectTimeoutSeconds: connectTimeoutSeconds
        )
        self.quillCodeExecutable = quillCodeExecutable
        self.environment = environment
        self.handshakeTimeoutSeconds = handshakeTimeoutSeconds
    }

    public func execute(
        command: String,
        connection: ProjectConnection,
        timeoutSeconds: TimeInterval
    ) async -> SSHRemoteAppServerExecutionOutcome {
        let key = ConnectionKey(connection)
        let client = clients[key] ?? makeClient(connection)
        clients[key] = client

        let task = Task.detached(priority: .userInitiated) {
            client.executeShell(command: command, timeoutSeconds: timeoutSeconds)
        }
        let outcome = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            client.cancelCurrentRequest()
            task.cancel()
        }

        switch outcome {
        case .completed:
            break
        case .unavailableBeforeExecution, .executionStateUnknown:
            if clients[key] === client { clients.removeValue(forKey: key) }
            client.close()
        }
        return outcome
    }

    public func disconnect(_ connection: ProjectConnection) async {
        clients.removeValue(forKey: ConnectionKey(connection))?.close()
    }

    public func disconnectAll() async {
        let active = Array(clients.values)
        clients.removeAll()
        for client in active { client.close() }
    }

    private func makeClient(_ connection: ProjectConnection) -> SSHRemoteAppServerClient {
        SSHRemoteAppServerClient(
            connection: connection,
            sshExecutor: sshExecutor,
            quillCodeExecutable: quillCodeExecutable,
            environment: environment,
            handshakeTimeoutSeconds: handshakeTimeoutSeconds
        )
    }
}
