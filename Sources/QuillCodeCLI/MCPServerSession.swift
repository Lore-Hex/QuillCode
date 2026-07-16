import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

typealias MCPServerMessageSink = @Sendable (String) async -> Void

actor MCPServerSession {
    static let maximumMessageBytes = 4 * 1_024 * 1_024
    static let protocolVersion = "2025-06-18"

    enum HandshakeState: Sendable, Equatable {
        case awaitingInitialize
        case awaitingInitialized
        case ready
    }

    struct ActiveCall: Sendable {
        var threadID: UUID
        var task: Task<Void, Never>
    }

    let request: CLIMCPServerRequest
    let environment: [String: String]
    let currentDirectory: URL
    let paths: QuillCodePaths
    let appConfig: AppConfig
    let repository: AppServerThreadRepository
    let attachmentStore: ImageAttachmentStore
    let mcpRegistry: AppServerMCPRegistry
    let runnerFactory: CLIAgentRunnerFactory
    let sink: MCPServerMessageSink

    var handshake = HandshakeState.awaitingInitialize
    var activeCalls: [MCPServerRequestID: ActiveCall] = [:]
    var activeThreadIDs: Set<UUID> = []
    var progressProjectors: [MCPServerRequestID: MCPServerProgressProjector] = [:]
    var progressFailures: [MCPServerRequestID: String] = [:]
    var pendingApprovals: [MCPServerRequestID: MCPServerPendingApproval] = [:]
    var nextServerRequestSequence: Int64 = 0
    var inputFinished = false

    init(
        request: CLIMCPServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        runnerFactory: @escaping CLIAgentRunnerFactory,
        mcpLauncher: any MCPClientLaunching = DefaultMCPClientLauncher(),
        mcpHTTPClient: any MCPHTTPClient = URLSessionMCPHTTPClient(),
        sink: @escaping MCPServerMessageSink
    ) throws {
        let paths = request.home.map { QuillCodePaths(home: $0) } ?? QuillCodePaths()
        try paths.ensure()
        self.request = request
        self.environment = environment
        self.currentDirectory = currentDirectory.standardizedFileURL
        self.paths = paths
        self.appConfig = try ConfigStore(fileURL: paths.configFile).load()
        self.repository = AppServerThreadRepository(paths: paths, fallbackCWD: currentDirectory)
        self.attachmentStore = ImageAttachmentStore(directory: paths.attachmentsDirectory)
        self.mcpRegistry = AppServerMCPRegistry(
            launcher: mcpLauncher,
            secretStore: AppServerMCPSecretStore(directory: paths.secretsDirectory),
            httpClient: mcpHTTPClient
        )
        self.runnerFactory = runnerFactory
        self.sink = sink
    }

    func receive(_ line: Data) async {
        guard !line.isEmpty else { return }
        let message: MCPServerInboundMessage
        do {
            message = try MCPServerInboundMessage(data: line)
        } catch MCPServerWireError.invalidEnvelope {
            await send(.error(id: nil, error: .invalidRequest))
            return
        } catch {
            await send(.error(id: nil, error: .parseError))
            return
        }

        switch message {
        case .request(let id, let method, let params):
            await handleRequest(id: id, method: method, params: params)
        case .notification(let method, let params):
            await handleNotification(method: method, params: params)
        case .response(let id, let result, let error):
            resolveApprovalResponse(id: id, result: result, error: error)
        }
    }

    func finishInput() {
        inputFinished = true
        resolveAllPendingApprovals(
            with: .deny(reason: "The MCP client disconnected before answering the approval request.")
        )
    }

    func waitForActiveCalls() async {
        while !activeCalls.isEmpty {
            let tasks = activeCalls.values.map(\.task)
            for task in tasks { await task.value }
        }
        await mcpRegistry.terminateAll()
    }

    private func handleRequest(
        id: MCPServerRequestID,
        method: String,
        params: CLIJSONValue
    ) async {
        if method == "initialize" {
            await initialize(id: id, params: params)
            return
        }
        guard handshake == .ready else {
            await send(.error(id: id, error: .notInitialized))
            return
        }

        switch method {
        case "ping":
            await send(.response(id: id, result: .object([:])))
        case "tools/list":
            await send(.response(id: id, result: MCPServerToolCatalog.listResult))
        case "tools/call":
            await startToolCall(id: id, params: params)
        default:
            await send(.error(id: id, error: .methodNotFound(method)))
        }
    }

    private func handleNotification(method: String, params: CLIJSONValue) async {
        switch method {
        case "notifications/initialized":
            if handshake == .awaitingInitialized { handshake = .ready }
        case "notifications/cancelled":
            guard let requestID = MCPServerRequestID(json: params.objectValue?["requestId"]) else { return }
            cancelCall(requestID)
        default:
            break
        }
    }

    private func initialize(id: MCPServerRequestID, params: CLIJSONValue) async {
        guard handshake == .awaitingInitialize else {
            await send(.error(
                id: id,
                error: MCPServerRPCError(code: -32600, message: "Server already initialized")
            ))
            return
        }
        guard let object = params.objectValue,
              object["protocolVersion"]?.stringValue != nil,
              let clientInfo = object["clientInfo"]?.objectValue,
              clientInfo["name"]?.stringValue != nil,
              clientInfo["version"]?.stringValue != nil,
              object["capabilities"]?.objectValue != nil else {
            await send(.error(id: id, error: .invalidParams))
            return
        }
        handshake = .awaitingInitialized
        await send(.response(id: id, result: .object([
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object([
                "tools": .object(["listChanged": .bool(true)])
            ]),
            "serverInfo": .object([
                "name": .string("quillcode-mcp-server"),
                "title": .string("QuillCode"),
                "version": .string(QuillCodeCommandRunner.version),
                "user_agent": .string("QuillCode/\(QuillCodeCommandRunner.version)")
            ])
        ])))
    }

    private func startToolCall(id: MCPServerRequestID, params: CLIJSONValue) async {
        guard activeCalls[id] == nil else {
            await send(.error(
                id: id,
                error: MCPServerRPCError(code: -32600, message: "Request id is already active")
            ))
            return
        }
        let invocation: MCPServerToolInvocation
        do {
            invocation = try MCPServerToolInvocation(params: params)
        } catch {
            await send(.response(id: id, result: MCPServerToolCatalog.error(error.localizedDescription)))
            return
        }

        guard !activeThreadIDs.contains(invocation.threadID) else {
            await send(.response(
                id: id,
                result: MCPServerToolCatalog.error(
                    "Thread \(invocation.threadID.uuidString.lowercased()) already has an active turn.",
                    threadID: invocation.threadID
                )
            ))
            return
        }

        activeThreadIDs.insert(invocation.threadID)
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.executeToolCall(id: id, invocation: invocation)
        }
        activeCalls[id] = ActiveCall(threadID: invocation.threadID, task: task)
    }

    private func executeToolCall(id: MCPServerRequestID, invocation: MCPServerToolInvocation) async {
        let result: CLIJSONValue
        do {
            let content = try await execute(invocation, requestID: id)
            result = MCPServerToolCatalog.callResult(
                threadID: invocation.threadID,
                content: content
            )
        } catch is CancellationError {
            await sendEvent(
                requestID: id,
                threadID: invocation.threadID,
                message: .object(["type": .string("turn_aborted"), "reason": .string("cancelled")])
            )
            result = MCPServerToolCatalog.error(
                "The QuillCode request was cancelled.",
                threadID: invocation.threadID
            )
        } catch {
            await sendEvent(
                requestID: id,
                threadID: invocation.threadID,
                message: .object(["type": .string("error"), "message": .string(error.localizedDescription)])
            )
            result = MCPServerToolCatalog.error(
                error.localizedDescription,
                threadID: invocation.threadID
            )
        }
        await send(.response(id: id, result: result))
        completeCall(id)
    }

    private func cancelCall(_ id: MCPServerRequestID) {
        activeCalls[id]?.task.cancel()
        resolvePendingApprovals(for: id, decision: .deny(reason: "The MCP request was cancelled."))
    }

    private func completeCall(_ id: MCPServerRequestID) {
        guard let call = activeCalls.removeValue(forKey: id) else { return }
        activeThreadIDs.remove(call.threadID)
        progressProjectors[id] = nil
        progressFailures[id] = nil
        resolvePendingApprovals(for: id, decision: .deny(reason: "The MCP request ended."))
    }

    func send(_ message: MCPServerOutboundMessage) async {
        guard let line = try? MCPServerWireCodec.line(message) else { return }
        await sink(line)
    }

    func sendEvent(
        requestID: MCPServerRequestID,
        threadID: UUID,
        message: CLIJSONValue,
        eventID: String = ""
    ) async {
        await send(.notification(method: "codex/event", params: .object([
            "_meta": .object([
                "requestId": requestID.jsonValue,
                "threadId": .string(threadID.uuidString.lowercased())
            ]),
            "id": .string(eventID),
            "msg": message
        ])))
    }
}

private extension MCPServerRequestID {
    init?(json: CLIJSONValue?) {
        if let value = json?.stringValue {
            self = .string(value)
        } else if let value = json?.numberValue,
                  value.isFinite,
                  value.rounded() == value,
                  value >= Double(Int64.min),
                  value <= Double(Int64.max) {
            self = .integer(Int64(value))
        } else {
            return nil
        }
    }

    var jsonValue: CLIJSONValue {
        switch self {
        case .string(let value): .string(value)
        case .integer(let value): .number(Double(value))
        }
    }
}
