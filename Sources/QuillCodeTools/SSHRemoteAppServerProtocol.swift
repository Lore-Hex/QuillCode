import Foundation
import QuillCodeCore

public enum SSHRemoteAppServerExecutionOutcome: Sendable, Equatable {
    case completed(ToolResult)
    case unavailableBeforeExecution(String)
    case executionStateUnknown(String)
}

public protocol SSHRemoteAppServerExecuting: Sendable {
    func execute(
        command: String,
        connection: ProjectConnection,
        timeoutSeconds: TimeInterval
    ) async -> SSHRemoteAppServerExecutionOutcome

    func disconnect(_ connection: ProjectConnection) async
    func disconnectAll() async
}

public extension SSHRemoteAppServerExecuting {
    func execute(
        command: String,
        connection: ProjectConnection
    ) async -> SSHRemoteAppServerExecutionOutcome {
        await execute(command: command, connection: connection, timeoutSeconds: 60)
    }
}
