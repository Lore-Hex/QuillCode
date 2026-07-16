import Foundation

struct AppServerConnectionDriver: Sendable {
    let runnerFactory: CLIAgentRunnerFactory

    func run(
        request: CLIAppServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        lines: AsyncThrowingStream<Data, Error>,
        sink: @escaping AppServerMessageSink
    ) async throws {
        let session = try AppServerSession(
            request: request,
            environment: environment,
            currentDirectory: currentDirectory,
            runnerFactory: runnerFactory,
            sink: sink
        )
        let concurrentRequests = AppServerConcurrentRequestPool()
        var inputError: (any Error)?
        do {
            for try await line in lines {
                if Self.requestCanAwaitClientResponse(line) {
                    await concurrentRequests.submit(line, to: session)
                } else {
                    await session.receive(line)
                }
            }
        } catch {
            inputError = error
        }
        await session.finishInput()
        await concurrentRequests.waitForAll()
        await session.waitForActiveTurns()
        if let inputError { throw inputError }
    }

    /// Server-initiated requests must not stop the connection reader from receiving their response.
    /// Other methods remain ordered on the input loop; JSON-RPC permits this direct tool request to
    /// complete out of order while its MCP server waits for an elicitation answer.
    private static func requestCanAwaitClientResponse(_ line: Data) -> Bool {
        guard case .request(_, let method, _) = try? AppServerInboundMessage(data: line) else {
            return false
        }
        return method == "mcpServer/tool/call"
    }
}

/// Owns only app-server requests that may wait for a server-request response from the same input
/// connection. Completed tasks remove themselves, so a long-lived client does not retain every
/// direct MCP call until disconnect.
private actor AppServerConcurrentRequestPool {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func submit(_ line: Data, to session: AppServerSession) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            await session.receive(line)
            await self?.remove(id)
        }
    }

    func waitForAll() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    private func remove(_ id: UUID) {
        tasks.removeValue(forKey: id)
    }
}
