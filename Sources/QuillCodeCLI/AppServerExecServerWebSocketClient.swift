import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import QuillCodeTools

actor AppServerExecServerWebSocketClient: AppServerExecServerClient {
    private static let requestTimeout: TimeInterval = 30
    private static let maximumMessageBytes = 8 * 1_024 * 1_024

    private let websocketURL: String
    private let connectTimeout: TimeInterval
    private let session: URLSession

    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, any Error>?
    private var initialized = false
    private var nextRequestID: Int64 = 1
    private var resumableSessionID: String?
    private var permanentlyClosed = false
    private var requestSlotOccupied = false
    private var requestSlotWaiters: [CheckedContinuation<Void, Never>] = []

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
            resetConnection()
            throw error
        }
    }

    func environmentInfo() async throws -> AppServerEnvironmentInfo {
        let result = try await request(method: "environment/info", params: .null)
        guard let object = result.objectValue,
              let shell = object["shell"]?.objectValue,
              let shellName = shell["name"]?.stringValue,
              let shellPath = shell["path"]?.stringValue,
              Self.isValidProtocolString(shellName),
              Self.isValidProtocolString(shellPath) else {
            throw AppServerExecServerError.invalidResponse(
                "environment/info did not return shell.name and shell.path"
            )
        }
        let cwd: String?
        if let value = object["cwd"], value != .null {
            guard let string = value.stringValue else {
                throw AppServerExecServerError.invalidResponse(
                    "environment/info cwd must be a file URI or null"
                )
            }
            cwd = string
        } else {
            cwd = nil
        }
        return AppServerEnvironmentInfo(
            shell: .init(name: shellName, path: shellPath),
            cwd: cwd
        )
    }

    func close() async {
        permanentlyClosed = true
        connectionTask?.cancel()
        connectionTask = nil
        resetConnection()
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

        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        do {
            let initializeResult = try await requestOnCurrentConnection(
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
        } catch {
            resetConnection()
            throw error
        }
    }

    func request(method: String, params: CLIJSONValue) async throws -> CLIJSONValue {
        await acquireRequestSlot()
        defer { releaseRequestSlot() }
        try Task.checkCancellation()
        try await connect()
        do {
            return try await requestOnCurrentConnection(
                method: method,
                params: params,
                timeout: Self.requestTimeout
            )
        } catch {
            // Never replay a request whose send may have reached the executor. A subsequent caller
            // may reconnect, but this operation fails closed so mutations cannot run twice.
            resetConnection()
            throw error
        }
    }

    private func acquireRequestSlot() async {
        guard requestSlotOccupied else {
            requestSlotOccupied = true
            return
        }
        await withCheckedContinuation { continuation in
            requestSlotWaiters.append(continuation)
        }
    }

    private func releaseRequestSlot() {
        guard !requestSlotWaiters.isEmpty else {
            requestSlotOccupied = false
            return
        }
        requestSlotWaiters.removeFirst().resume()
    }

    private func requestOnCurrentConnection(
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
            let data = try Self.messageData(message)
            let value = try CLIJSONCodec.decode(data)
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

    private func resetConnection() {
        initialized = false
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private static func messageData(_ message: URLSessionWebSocketTask.Message) throws -> Data {
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default:
            throw AppServerExecServerError.invalidResponse("unsupported WebSocket message type")
        }
        guard data.count <= maximumMessageBytes else {
            throw AppServerExecServerError.invalidResponse(
                "WebSocket message exceeds \(maximumMessageBytes) bytes"
            )
        }
        return data
    }

    private static func redactedURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else { return "<invalid>" }
        components.user = nil
        components.password = nil
        components.query = components.queryItems?.isEmpty == false ? "<redacted>" : nil
        return components.string ?? "<invalid>"
    }

    static func decodeUInt64(
        _ value: Double,
        malformedResponse: String
    ) throws -> UInt64 {
        guard value.isFinite,
              value >= 0,
              value.rounded() == value,
              value < Double(UInt64.max) else {
            throw AppServerExecServerError.invalidResponse(malformedResponse)
        }
        return UInt64(value)
    }

    private static func decodeJSONRPCErrorCode(_ value: Double) -> Int? {
        guard value.isFinite,
              value.rounded() == value,
              value >= Double(Int32.min),
              value <= Double(Int32.max) else {
            return nil
        }
        return Int(value)
    }

    static func isValidProtocolString(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.contains("\0")
            && value.rangeOfCharacter(from: .newlines) == nil
    }

    static func isValidDirectoryEntryName(_ value: String) -> Bool {
        isValidProtocolString(value)
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }
}

func appServerDuration(seconds: TimeInterval) -> Duration {
    // A century is effectively unbounded for a process lifetime while remaining comfortably
    // inside ContinuousClock and Duration arithmetic on every supported platform.
    let maximumMilliseconds: Double = 100 * 365.25 * 24 * 60 * 60 * 1_000
    let requestedMilliseconds = max(0, seconds) * 1_000
    let boundedMilliseconds = min(
        requestedMilliseconds.isFinite
            ? requestedMilliseconds.rounded(.up)
            : maximumMilliseconds,
        maximumMilliseconds
    )
    return .milliseconds(Int64(boundedMilliseconds))
}

private func appServerWithTimeout<Value: Sendable>(
    operation: String,
    seconds: TimeInterval,
    body: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask(operation: body)
        group.addTask {
            try await Task.sleep(for: appServerDuration(seconds: seconds))
            throw AppServerExecServerError.timedOut(operation: operation, seconds: seconds)
        }
        guard let value = try await group.next() else {
            throw AppServerExecServerError.disconnected("timeout race ended without a result")
        }
        group.cancelAll()
        return value
    }
}
