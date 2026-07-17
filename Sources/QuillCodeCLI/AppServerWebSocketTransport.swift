import Foundation
import QuillCodePlatform

struct AppServerWebSocketTransport: Sendable {
    let runnerFactory: CLIAgentRunnerFactory

    func run(
        request: CLIAppServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        diagnostics: any CLIOutputWriting
    ) async throws {
        guard case .webSocket(let host, let requestedPort) = request.transport else {
            preconditionFailure("WebSocket transport requested for a non-WebSocket listener")
        }
        let authPolicy = try AppServerWebSocketAuthPolicy(configuration: request.webSocketAuth)
        guard Self.isLoopback(host) || authPolicy.requiresAuthentication else {
            throw CLIError.invalidAppServerAuth(
                "non-loopback WebSocket listeners require --ws-auth"
            )
        }
        let listener = try TCPSocketListener(host: host, port: requestedPort)
        let connections = AppServerSocketConnectionPool()
        let runtimeFeatureStore = AppServerRuntimeFeatureStore()
        let displayHost = host.contains(":") ? "[\(host)]" : host
        await diagnostics.writeStandardErrorLine(
            "quill-code app-server: listening on ws://\(displayHost):\(listener.port)"
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
                            runtimeFeatureStore: runtimeFeatureStore
                        ).run(
                            request: request,
                            environment: environment,
                            currentDirectory: currentDirectory,
                            connection: connection,
                            authPolicy: authPolicy
                        )
                    } catch is CancellationError {
                        connection.close()
                    } catch {
                        await diagnostics.writeStandardErrorLine(
                            "quill-code app-server: WebSocket client disconnected: "
                                + error.localizedDescription
                        )
                    }
                }
                if !accepted { connection.close() }
            }
        } catch TCPSocketError.cancelled where Task.isCancelled {
            // Parent cancellation closes the listener and is handled by the command runner.
        } catch {
            listenerError = error
        }
        listener.close()
        await connections.cancelAndWait()
        if let listenerError { throw listenerError }
        try Task.checkCancellation()
    }

    private static func isLoopback(_ host: String) -> Bool {
        if host == "::1" { return true }
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 4 && components.first == "127"
    }
}

struct AppServerWebSocketConnectionHandler: Sendable {
    private static let queueCapacity = 128

    let runnerFactory: CLIAgentRunnerFactory
    let runtimeFeatureStore: AppServerRuntimeFeatureStore

    func run(
        request: CLIAppServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        connection: any SocketByteConnection,
        authPolicy: AppServerWebSocketAuthPolicy
    ) async throws {
        let reader = AppServerWebSocketReader(
            connection: connection,
            maximumMessageBytes: AppServerSession.maximumMessageBytes
        )
        let writer = AppServerWebSocketWriter(connection: connection)
        let httpRequest: AppServerHTTPRequest
        do {
            httpRequest = try await reader.readHTTPRequest()
        } catch {
            try? await writer.sendHTTP(
                status: "400 Bad Request",
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: Data("Bad Request".utf8)
            )
            return
        }

        guard !httpRequest.hasHeader("origin") else {
            try await writer.sendHTTP(
                status: "403 Forbidden",
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: Data("Forbidden".utf8)
            )
            return
        }
        if httpRequest.method == "GET",
           httpRequest.target == "/readyz" || httpRequest.target == "/healthz" {
            try await writer.sendHTTP(
                status: "200 OK",
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: Data("OK".utf8)
            )
            return
        }

        do {
            try Self.validateUpgrade(httpRequest)
            try authPolicy.authorize(httpRequest)
        } catch let error as AppServerWebSocketAuthError {
            try await writer.sendHTTP(
                status: "\(error.statusCode) Unauthorized",
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: Data(error.reason.utf8)
            )
            return
        } catch {
            try await writer.sendHTTP(
                status: "400 Bad Request",
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: Data("Invalid WebSocket upgrade".utf8)
            )
            return
        }

        guard let key = httpRequest.header("sec-websocket-key") else {
            throw AppServerWebSocketProtocolError.invalidUpgrade("missing Sec-WebSocket-Key")
        }
        try await writer.acceptUpgrade(key: key)
        try await runSession(
            request: request,
            environment: environment,
            currentDirectory: currentDirectory,
            reader: reader,
            writer: writer,
            connection: connection
        )
    }

    private func runSession(
        request: CLIAppServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        reader: AppServerWebSocketReader,
        writer: AppServerWebSocketWriter,
        connection: any SocketByteConnection
    ) async throws {
        let outbound = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingOldest(Self.queueCapacity)
        )
        let writerTask = Task {
            do {
                for await message in outbound.stream {
                    try await writer.sendText(message)
                }
            } catch {
                await writer.close()
            }
        }
        let inbound = Self.inboundMessages(
            reader: reader,
            writer: writer,
            connection: connection,
            outbound: outbound.continuation
        )
        let sink: AppServerMessageSink = { line in
            var message = Data(line.utf8)
            if message.last == 0x0A { message.removeLast() }
            if case .dropped = outbound.continuation.yield(message) {
                outbound.continuation.finish()
                connection.close()
            }
        }

        var driverError: (any Error)?
        do {
            try await AppServerConnectionDriver(
                runnerFactory: runnerFactory,
                runtimeFeatureStore: runtimeFeatureStore
            ).run(
                request: request,
                environment: environment,
                currentDirectory: currentDirectory,
                lines: inbound,
                sink: sink
            )
        } catch {
            driverError = error
        }
        outbound.continuation.finish()
        await writerTask.value
        if let driverError { throw driverError }
    }

    private static func inboundMessages(
        reader: AppServerWebSocketReader,
        writer: AppServerWebSocketWriter,
        connection: any SocketByteConnection,
        outbound: AsyncStream<Data>.Continuation
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(queueCapacity)) { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        switch try await reader.receiveEvent() {
                        case .text(let message):
                            if case .dropped(let dropped) = continuation.yield(message) {
                                guard enqueueOverloadResponse(for: dropped, outbound: outbound) else {
                                    connection.close()
                                    continuation.finish()
                                    return
                                }
                            }
                        case .binary, .pong:
                            continue
                        case .ping(let payload):
                            try await writer.sendPong(payload)
                        case .close(let payload):
                            try? await writer.sendClose(payload)
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch let error as AppServerWebSocketProtocolError {
                    try? await writer.sendClose(closePayload(for: error))
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                task.cancel()
                if case .cancelled = termination { connection.close() }
            }
        }
    }

    private static func enqueueOverloadResponse(
        for message: Data,
        outbound: AsyncStream<Data>.Continuation
    ) -> Bool {
        guard case .request(let id, _, _) = try? AppServerInboundMessage(data: message),
              let line = try? AppServerWireCodec.line(.error(
                id: id,
                error: .overloaded
              ))
        else { return true }
        var payload = Data(line.utf8)
        if payload.last == 0x0A { payload.removeLast() }
        if case .dropped = outbound.yield(payload) { return false }
        return true
    }

    private static func closePayload(for error: AppServerWebSocketProtocolError) -> Data {
        let code: UInt16
        switch error {
        case .messageTooLarge: code = 1_009
        default: code = 1_002
        }
        return Data([UInt8(code >> 8), UInt8(code & 0xFF)])
    }

    private static func validateUpgrade(_ request: AppServerHTTPRequest) throws {
        guard request.method == "GET",
              request.version == "HTTP/1.1",
              request.headerContainsToken("connection", token: "upgrade"),
              request.headerContainsToken("upgrade", token: "websocket"),
              request.header("host") != nil,
              request.header("sec-websocket-version") == "13",
              let key = request.header("sec-websocket-key"),
              Data(base64Encoded: key)?.count == 16
        else {
            throw AppServerWebSocketProtocolError.invalidUpgrade("required headers are missing")
        }
    }
}

actor AppServerSocketConnectionPool {
    private static let maximumConnections = 256
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func submit(_ operation: @escaping @Sendable () async -> Void) -> Bool {
        guard tasks.count < Self.maximumConnections else { return false }
        let id = UUID()
        tasks[id] = Task { [weak self] in
            await operation()
            await self?.remove(id)
        }
        return true
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
