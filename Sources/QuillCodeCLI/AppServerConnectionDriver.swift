import Foundation

struct AppServerConnectionDriver: Sendable {
    let runnerFactory: CLIAgentRunnerFactory
    let runtimeFeatureStore: AppServerRuntimeFeatureStore

    init(
        runnerFactory: @escaping CLIAgentRunnerFactory,
        runtimeFeatureStore: AppServerRuntimeFeatureStore = AppServerRuntimeFeatureStore()
    ) {
        self.runnerFactory = runnerFactory
        self.runtimeFeatureStore = runtimeFeatureStore
    }

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
            runtimeFeatureStore: runtimeFeatureStore,
            sink: sink
        )
        let concurrentRequests = AppServerConcurrentRequestPool()
        var inputError: (any Error)?
        do {
            for try await line in lines {
                if Self.requestCanAwaitClientResponse(line) {
                    let accepted = await concurrentRequests.submit(line, to: session)
                    if !accepted { await Self.sendOverloadResponse(for: line, sink: sink) }
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

    private static func sendOverloadResponse(
        for line: Data,
        sink: AppServerMessageSink
    ) async {
        guard case .request(let id, _, _) = try? AppServerInboundMessage(data: line),
              let response = try? AppServerWireCodec.line(.error(
                id: id,
                error: AppServerRPCError.overloaded
              ))
        else { return }
        await sink(response)
    }
}

/// Owns only app-server requests that may wait for a server-request response from the same input
/// connection. Completed tasks remove themselves, so a long-lived client does not retain every
/// direct MCP call until disconnect.
private actor AppServerConcurrentRequestPool {
    private static let maximumConcurrentRequests = 128
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func submit(_ line: Data, to session: AppServerSession) -> Bool {
        guard tasks.count < Self.maximumConcurrentRequests else { return false }
        let id = UUID()
        tasks[id] = Task { [weak self] in
            await session.receive(line)
            await self?.remove(id)
        }
        return true
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
