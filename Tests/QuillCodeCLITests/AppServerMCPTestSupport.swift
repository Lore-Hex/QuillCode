import Foundation
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodeTools

struct AppServerMCPFixture {
    var session: AppServerSession
    var output: AppServerMCPOutputCollector
    var home: URL
    var workspace: URL
}

actor AppServerMCPOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw MCPProbeError.invalidMessage("app-server output was not a JSON object")
            }
            return object
        }
    }

    func waitForNotification(
        method: String,
        timeout: Duration = .seconds(3)
    ) async throws -> [String: CLIJSONValue] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let match = try records().first(where: { $0["method"]?.stringValue == method }) {
                return match["params"]?.objectValue ?? [:]
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw MCPProbeError.responseError("timed out waiting for \(method)")
    }

    func waitForRequest(
        method: String,
        timeout: Duration = .seconds(3)
    ) async throws -> [String: CLIJSONValue] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let match = try records().first(where: { record in
                record["method"]?.stringValue == method && record["id"] != nil
            }) {
                return match
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw MCPProbeError.responseError("timed out waiting for \(method) request")
    }

    func waitForMCPStartup(
        server: String,
        status: String,
        timeout: Duration = .seconds(3)
    ) async throws -> [String: CLIJSONValue] {
        let method = "mcpServer/startupStatus/updated"
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let match = try records().first(where: { record in
                guard record["method"]?.stringValue == method,
                      let params = record["params"]?.objectValue
                else {
                    return false
                }
                return params["name"]?.stringValue == server
                    && params["status"]?.stringValue == status
            }) {
                return match["params"]?.objectValue ?? [:]
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw MCPProbeError.responseError(
            "timed out waiting for \(server) MCP startup status \(status)"
        )
    }
}

struct FakeMCPServerSpecification: Sendable {
    var probe: MCPServerProbeResult
    var toolResult: MCPToolCallResult
    var toolProgress: [ToolExecutionProgress]
    var elicitationRequest: MCPClientElicitationRequest?
    var resourceResult: MCPResourceReadResult
    var probeDelay: TimeInterval

    init(
        probe: MCPServerProbeResult,
        toolResult: MCPToolCallResult = MCPToolCallResult(),
        toolProgress: [ToolExecutionProgress] = [],
        elicitationRequest: MCPClientElicitationRequest? = nil,
        resourceResult: MCPResourceReadResult = MCPResourceReadResult(),
        probeDelay: TimeInterval = 0
    ) {
        self.probe = probe
        self.toolResult = toolResult
        self.toolProgress = toolProgress
        self.elicitationRequest = elicitationRequest
        self.resourceResult = resourceResult
        self.probeDelay = probeDelay
    }
}

final class FakeMCPLauncher: MCPClientLaunching, @unchecked Sendable {
    private let specifications: [String: FakeMCPServerSpecification]
    private let recorders: [String: FakeMCPRecorder]

    init(specifications: [String: FakeMCPServerSpecification]) {
        self.specifications = specifications
        self.recorders = specifications.mapValues { _ in FakeMCPRecorder() }
    }

    func launch(
        request: MCPClientLaunchRequest,
        onTermination: @escaping @Sendable (Int32) -> Void
    ) throws -> MCPLaunchedClient {
        guard let specification = specifications[request.command],
              let recorder = recorders[request.command]
        else { throw MCPProbeError.invalidMessage("no fake MCP server named \(request.command)") }
        recorder.recordLaunch()
        return MCPLaunchedClient(
            process: FakeMCPProcess(recorder: recorder, onTermination: onTermination),
            session: FakeMCPClientSession(specification: specification, recorder: recorder)
        )
    }

    func recorder(for command: String) -> FakeMCPRecorder {
        guard let recorder = recorders[command] else {
            fatalError("no fake MCP recorder named \(command)")
        }
        return recorder
    }
}

private final class FakeMCPProcess: MCPProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private let recorder: FakeMCPRecorder
    private let onTermination: @Sendable (Int32) -> Void
    private var running = true

    init(recorder: FakeMCPRecorder, onTermination: @escaping @Sendable (Int32) -> Void) {
        self.recorder = recorder
        self.onTermination = onTermination
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func terminate() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        lock.unlock()
        recorder.recordTermination()
        onTermination(0)
    }

    func clearReadabilityHandlers() {}
    func startDrainingStandardError() {}
}

private final class FakeMCPClientSession: MCPClientSession, @unchecked Sendable {
    private let specification: FakeMCPServerSpecification
    private let recorder: FakeMCPRecorder

    init(specification: FakeMCPServerSpecification, recorder: FakeMCPRecorder) {
        self.specification = specification
        self.recorder = recorder
    }

    func configure(clientCapabilities: MCPClientCapabilities) {
        recorder.recordCapabilities(clientCapabilities)
    }

    func probe(timeout: TimeInterval) throws -> MCPServerProbeResult {
        try probe(detail: .full, timeout: timeout)
    }

    func probe(detail: MCPProbeDetail, timeout: TimeInterval) throws -> MCPServerProbeResult {
        _ = timeout
        if specification.probeDelay > 0 {
            Thread.sleep(forTimeInterval: specification.probeDelay)
        }
        recorder.recordProbe(detail)
        var result = specification.probe
        if detail == .toolsAndAuthOnly {
            result.resources = []
            result.resourceTemplates = []
            result.resourceNames = []
            result.resourceURIs = []
            result.promptNames = []
        }
        return result
    }

    func callTool(toolName: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult {
        _ = (toolName, argumentsJSON, timeout)
        return ToolResult(ok: true)
    }

    func callToolResult(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval
    ) throws -> MCPToolCallResult {
        _ = timeout
        recorder.recordToolCall(tool: toolName, arguments: arguments, metadata: metadata)
        return specification.toolResult
    }

    func callToolEvents(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<MCPClientToolEvent, Error> {
        _ = timeout
        recorder.recordToolCall(tool: toolName, arguments: arguments, metadata: metadata)
        let progress = specification.toolProgress
        let result = specification.toolResult
        return AsyncThrowingStream { continuation in
            for update in progress {
                continuation.yield(.progress(update))
            }
            continuation.yield(.result(result))
            continuation.finish()
        }
    }

    func callToolEvents(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval,
        elicitationHandler: MCPClientElicitationHandler?
    ) -> AsyncThrowingStream<MCPClientToolEvent, Error> {
        _ = timeout
        recorder.recordToolCall(tool: toolName, arguments: arguments, metadata: metadata)
        let request = specification.elicitationRequest
        let progress = specification.toolProgress
        let result = specification.toolResult
        let capabilities = recorder.latestCapabilities ?? .none
        return AsyncThrowingStream { continuation in
            let task = Task {
                if let request {
                    let supported: Bool
                    switch request {
                    case .form, .url:
                        supported = capabilities.supportsFormElicitation
                    case .openAIForm:
                        supported = capabilities.supportsOpenAIFormElicitation
                    }
                    let response: MCPClientElicitationResponse
                    if supported, let elicitationHandler {
                        response = await elicitationHandler(request)
                    } else {
                        response = .cancel()
                    }
                    recorder.recordElicitation(request: request, response: response)
                }
                guard !Task.isCancelled else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                for update in progress {
                    continuation.yield(.progress(update))
                }
                continuation.yield(.result(result))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func readResource(uri: String, timeout: TimeInterval) throws -> ToolResult {
        _ = (uri, timeout)
        return ToolResult(ok: true)
    }

    func readResourceResult(uri: String, timeout: TimeInterval) throws -> MCPResourceReadResult {
        _ = timeout
        recorder.recordResource(uri)
        return specification.resourceResult
    }

    func getPrompt(name: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult {
        _ = (name, argumentsJSON, timeout)
        return ToolResult(ok: true)
    }
}

final class FakeMCPRecorder: @unchecked Sendable {
    struct ToolCall: Sendable, Equatable {
        var tool: String
        var arguments: MCPJSONValue?
        var metadata: MCPJSONValue?
    }

    struct Elicitation: Sendable, Equatable {
        var request: MCPClientElicitationRequest
        var response: MCPClientElicitationResponse
    }

    private let lock = NSLock()
    private var storedProbeDetails: [MCPProbeDetail] = []
    private var storedToolCalls: [ToolCall] = []
    private var storedCapabilities: [MCPClientCapabilities] = []
    private var storedElicitations: [Elicitation] = []
    private var storedResourceURIs: [String] = []
    private var storedLaunchCount = 0
    private var storedTerminationCount = 0

    var probeDetails: [MCPProbeDetail] { withLock { storedProbeDetails } }
    var toolCalls: [ToolCall] { withLock { storedToolCalls } }
    var configuredCapabilities: [MCPClientCapabilities] { withLock { storedCapabilities } }
    var latestCapabilities: MCPClientCapabilities? { withLock { storedCapabilities.last } }
    var elicitations: [Elicitation] { withLock { storedElicitations } }
    var resourceURIs: [String] { withLock { storedResourceURIs } }
    var launchCount: Int { withLock { storedLaunchCount } }
    var terminationCount: Int { withLock { storedTerminationCount } }

    func recordProbe(_ detail: MCPProbeDetail) { withLock { storedProbeDetails.append(detail) } }

    func recordToolCall(tool: String, arguments: MCPJSONValue?, metadata: MCPJSONValue?) {
        withLock { storedToolCalls.append(ToolCall(tool: tool, arguments: arguments, metadata: metadata)) }
    }

    func recordCapabilities(_ capabilities: MCPClientCapabilities) {
        withLock { storedCapabilities.append(capabilities) }
    }

    func recordElicitation(
        request: MCPClientElicitationRequest,
        response: MCPClientElicitationResponse
    ) {
        withLock { storedElicitations.append(Elicitation(request: request, response: response)) }
    }

    func recordResource(_ uri: String) { withLock { storedResourceURIs.append(uri) } }
    func recordLaunch() { withLock { storedLaunchCount += 1 } }
    func recordTermination() { withLock { storedTerminationCount += 1 } }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
