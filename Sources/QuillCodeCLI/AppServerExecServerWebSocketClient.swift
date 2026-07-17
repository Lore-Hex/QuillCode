import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import QuillCodeTools

actor AppServerExecServerWebSocketClient: AppServerExecServerClient {
    private let websocketURL: String
    private let connectTimeout: TimeInterval
    private let session: URLSession

    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, any Error>?
    private var readerTask: Task<Void, Never>?
    private var initialized = false
    private var connectionGeneration: UInt64 = 0
    private var nextRequestID: Int64 = 1
    private var resumableSessionID: String?
    private var permanentlyClosed = false
    private var lastConnectionError: String?
    private var lastPublishedConnectionState: AppServerEnvironmentConnectionState?
    private var responseRegistry = AppServerExecServerPendingResponseRegistry()
    private var connectionEventContinuations:
        [UUID: AsyncStream<AppServerExecServerConnectionObservation>.Continuation] = [:]

    init(websocketURL: String, connectTimeout: TimeInterval) {
        self.websocketURL = websocketURL
        self.connectTimeout = connectTimeout
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = min(
            max(connectTimeout, 0.001),
            100 * 365.25 * 24 * 60 * 60
        )
        // WebSocket environments are intentionally long-lived. Per-operation deadlines below bound
        // every request without letting URLSession reap a healthy connection after the connect timeout.
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        self.session = URLSession(configuration: configuration)
    }

    func connect() async throws {
        guard !permanentlyClosed else {
            throw AppServerExecServerError.disconnected("the client has been closed")
        }
        if initialized, socket != nil { return }
        if let connectionTask {
            return try await connectionTask.value
        }

        let task = Task { [weak self] in
            guard let self else {
                throw AppServerExecServerError.disconnected("the client was released")
            }
            try await self.openConnection()
        }
        connectionTask = task
        do {
            try await task.value
            connectionTask = nil
        } catch {
            connectionTask = nil
            resetConnection(error: error)
            throw error
        }
    }

    func connectionSnapshot() async -> AppServerEnvironmentConnectionSnapshot {
        guard !permanentlyClosed else {
            return .disconnected(lastConnectionError ?? "the client has been closed")
        }
        if connectionTask != nil { return .pending }
        guard initialized, socket != nil else {
            return lastConnectionError.map(AppServerEnvironmentConnectionSnapshot.disconnected)
                ?? .pending
        }

        do {
            let result = try await requestOnInitializedConnection(
                method: "environment/status",
                params: .null,
                timeout: Self.environmentStatusTimeout
            )
            let snapshot = try Self.decodeConnectionSnapshot(result)
            lastConnectionError = nil
            transitionConnectionState(
                to: snapshot.isConnected ? .connected : .disconnected
            )
            return snapshot
        } catch {
            resetConnection(error: error)
            return .disconnected(Self.errorDetail(error))
        }
    }

    func connectionEvents() async -> AsyncStream<AppServerExecServerConnectionObservation> {
        let identifier = UUID()
        let pair = AsyncStream<AppServerExecServerConnectionObservation>.makeStream()
        connectionEventContinuations[identifier] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeConnectionEventContinuation(identifier) }
        }
        return pair.stream
    }

    func close() async {
        permanentlyClosed = true
        connectionTask?.cancel()
        connectionTask = nil
        resetConnection(error: AppServerExecServerError.disconnected("the client has been closed"))
        for continuation in connectionEventContinuations.values {
            continuation.finish()
        }
        connectionEventContinuations.removeAll()
        session.invalidateAndCancel()
    }

    private func openConnection() async throws {
        let trimmed = websocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme),
              url.host != nil else {
            throw AppServerExecServerError.invalidURL(Self.redactedURL(trimmed))
        }

        connectionGeneration &+= 1
        let generation = connectionGeneration
        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        let initializeResult = try await requestDuringHandshake(
            method: "initialize",
            params: .object([
                "clientName": .string("quillcode-environment"),
                "resumeSessionId": resumableSessionID.map(CLIJSONValue.string) ?? .null
            ]),
            timeout: max(connectTimeout, 0.001)
        )
        guard let sessionID = initializeResult.objectValue?["sessionId"]?.stringValue,
              !sessionID.isEmpty else {
            throw AppServerExecServerError.invalidResponse(
                "initialize did not return a sessionId"
            )
        }
        resumableSessionID = sessionID
        try await sendNotification(method: "initialized", params: .object([:]))
        try Task.checkCancellation()
        guard !permanentlyClosed else {
            throw AppServerExecServerError.disconnected("the client was closed while connecting")
        }
        initialized = true
        lastConnectionError = nil
        startReader(socket: socket, generation: generation)
        transitionConnectionState(to: .connected)
    }

    func request(method: String, params: CLIJSONValue) async throws -> CLIJSONValue {
        try Task.checkCancellation()
        try await connect()
        do {
            return try await requestOnInitializedConnection(
                method: method,
                params: params,
                timeout: Self.requestTimeout
            )
        } catch is CancellationError {
            // A process reader can be cancelled after its process has been terminated. Retire only
            // that pending response; the multiplexed WebSocket remains valid for other processes.
            throw CancellationError()
        } catch let error as AppServerExecServerError {
            if case .remoteRPC = error { throw error }
            resetConnection(error: error)
            throw error
        } catch {
            // Never replay a request whose send may have reached the executor. A subsequent caller
            // may reconnect, but this operation fails closed so mutations cannot run twice.
            resetConnection(error: error)
            throw error
        }
    }

    private func requestDuringHandshake(
        method: String,
        params: CLIJSONValue,
        timeout: TimeInterval
    ) async throws -> CLIJSONValue {
        guard let socket else {
            throw AppServerExecServerError.disconnected("no active WebSocket")
        }
        let requestID = nextRequestID
        nextRequestID += 1
        let payload = try CLIJSONCodec.encode(.object([
            "id": .number(Double(requestID)),
            "method": .string(method),
            "params": params
        ]))
        try await appServerWithTimeout(operation: "request", seconds: timeout) {
            try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
        }

        var ignoredNotifications = 0
        while ignoredNotifications < 10_000 {
            let message = try await appServerWithTimeout(operation: "response", seconds: timeout) {
                try await socket.receive()
            }
            let value = try CLIJSONCodec.decode(Self.messageData(message))
            guard let object = value.objectValue else {
                throw AppServerExecServerError.invalidResponse("JSON-RPC envelope must be an object")
            }
            guard let responseID = object["id"]?.numberValue else {
                ignoredNotifications += 1
                continue
            }
            guard responseID == Double(requestID) else {
                throw AppServerExecServerError.invalidResponse(
                    "received response for unexpected request id \(responseID)"
                )
            }
            if let error = object["error"]?.objectValue {
                let code = error["code"]?.numberValue.flatMap(Self.decodeJSONRPCErrorCode)
                let message = error["message"]?.stringValue ?? "unknown remote error"
                throw AppServerExecServerError.remoteRPC(code: code, message: message)
            }
            guard let result = object["result"] else {
                throw AppServerExecServerError.invalidResponse(
                    "JSON-RPC response omitted result and error"
                )
            }
            return result
        }
        throw AppServerExecServerError.invalidResponse(
            "too many notifications arrived without a matching response"
        )
    }

    private func requestOnInitializedConnection(
        method: String,
        params: CLIJSONValue,
        timeout: TimeInterval
    ) async throws -> CLIJSONValue {
        guard initialized, let socket else {
            throw AppServerExecServerError.disconnected("no initialized WebSocket")
        }
        let generation = connectionGeneration
        let requestID = nextRequestID
        nextRequestID += 1
        let response = AsyncThrowingStream<CLIJSONValue, Error>.makeStream()
        try responseRegistry.register(
            requestID: requestID,
            generation: generation,
            continuation: response.continuation
        )
        defer { finishPendingResponse(requestID) }

        let payload = try CLIJSONCodec.encode(.object([
            "id": .number(Double(requestID)),
            "method": .string(method),
            "params": params
        ]))
        try await appServerWithTimeout(operation: "request", seconds: timeout) {
            try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
        }
        do {
            return try await appServerWithTimeout(operation: "response", seconds: timeout) {
                var iterator = response.stream.makeAsyncIterator()
                guard let value = try await iterator.next() else {
                    try Task.checkCancellation()
                    throw AppServerExecServerError.disconnected(
                        "response stream ended before request id \(requestID) completed"
                    )
                }
                return value
            }
        } catch is CancellationError {
            if responseRegistry.abandon(requestID) {
                if responseRegistry.abandonedCount > Self.maximumAbandonedResponseIDs {
                    resetConnection(error: AppServerExecServerError.invalidResponse(
                        "too many canceled requests remained without responses"
                    ))
                }
            }
            throw CancellationError()
        }
    }

    private func sendNotification(method: String, params: CLIJSONValue) async throws {
        guard let socket else {
            throw AppServerExecServerError.disconnected("no active WebSocket")
        }
        let payload = try CLIJSONCodec.encode(.object([
            "method": .string(method),
            "params": params
        ]))
        try await appServerWithTimeout(operation: "notification", seconds: Self.requestTimeout) {
            try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
        }
    }

    private func startReader(
        socket: URLSessionWebSocketTask,
        generation: UInt64
    ) {
        readerTask?.cancel()
        readerTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    try await self?.handleIncomingMessage(message, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                await self?.readerDidFail(error, generation: generation)
            }
        }
    }

    private func handleIncomingMessage(
        _ message: URLSessionWebSocketTask.Message,
        generation: UInt64
    ) throws {
        guard generation == connectionGeneration, initialized else { return }
        let value = try CLIJSONCodec.decode(Self.messageData(message))
        guard let object = value.objectValue else {
            throw AppServerExecServerError.invalidResponse("JSON-RPC envelope must be an object")
        }
        guard let rawResponseID = object["id"] else {
            // Exec-server notifications are consumed by higher-level process polling today.
            return
        }
        guard let responseID = Self.decodeRequestID(rawResponseID) else {
            throw AppServerExecServerError.invalidResponse(
                "JSON-RPC response id must be an integer"
            )
        }
        guard let pending = try responseRegistry.take(responseID) else { return }
        guard pending.generation == generation else { return }
        if let error = object["error"]?.objectValue {
            let code = error["code"]?.numberValue.flatMap(Self.decodeJSONRPCErrorCode)
            let message = error["message"]?.stringValue ?? "unknown remote error"
            pending.continuation.finish(
                throwing: AppServerExecServerError.remoteRPC(code: code, message: message)
            )
            return
        }
        guard let result = object["result"] else {
            pending.continuation.finish(
                throwing: AppServerExecServerError.invalidResponse(
                    "JSON-RPC response omitted result and error"
                )
            )
            return
        }
        pending.continuation.yield(result)
        pending.continuation.finish()
    }

    private func readerDidFail(_ error: Error, generation: UInt64) {
        guard generation == connectionGeneration, !permanentlyClosed else { return }
        resetConnection(error: error)
    }

    private func finishPendingResponse(_ requestID: Int64) {
        responseRegistry.finish(requestID)
    }

    private func resetConnection(error: Error) {
        initialized = false
        connectionGeneration &+= 1
        readerTask?.cancel()
        readerTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        let detail = Self.errorDetail(error)
        lastConnectionError = detail
        let pendingError = AppServerExecServerError.disconnected(detail)
        responseRegistry.failAll(throwing: pendingError)
        transitionConnectionState(to: .disconnected)
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
