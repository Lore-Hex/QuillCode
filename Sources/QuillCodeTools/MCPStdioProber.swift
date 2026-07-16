import Foundation
import QuillCodeCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class MCPStdioProber: @unchecked Sendable {
    private let standardInput: FileHandle
    private let standardOutput: FileHandle
    private let ioLock = NSLock()
    private var readBuffer = Data()
    private var nextRequestID = 1
    private var clientCapabilities = MCPClientCapabilities.none

    public init(standardInput: FileHandle, standardOutput: FileHandle) {
        self.standardInput = standardInput
        self.standardOutput = standardOutput
    }

    public func configure(clientCapabilities: MCPClientCapabilities) {
        ioLock.lock()
        self.clientCapabilities = clientCapabilities
        ioLock.unlock()
    }

    public func probe(timeout: TimeInterval = 2.0) throws -> MCPServerProbeResult {
        try probe(detail: .full, timeout: timeout)
    }

    public func probe(
        detail: MCPProbeDetail,
        timeout: TimeInterval = 2.0
    ) throws -> MCPServerProbeResult {
        ioLock.lock()
        defer { ioLock.unlock() }

        let deadline = Date().addingTimeInterval(timeout)
        let initializeID = nextID()
        try write(method: "initialize", id: initializeID, params: [
            "protocolVersion": "2025-06-18",
            "capabilities": clientCapabilities.initializeObject,
            "clientInfo": [
                "name": "QuillCode",
                "version": "0.1.0"
            ]
        ])

        let initialize = try readResponse(id: initializeID, deadline: deadline)
        let initializeResult = try resultDictionary(from: initialize)

        try writeNotification(method: "notifications/initialized", params: [:])
        let toolsListID = nextID()
        try write(method: "tools/list", id: toolsListID, params: [:])

        let toolsList = try readResponse(id: toolsListID, deadline: deadline)
        let toolsResult = try resultDictionary(from: toolsList)
        let tools = (toolsResult["tools"] as? [[String: Any]]) ?? []
        let toolDescriptors = MCPStdioResultMapper.toolDescriptors(from: tools)

        let capabilities = initializeResult["capabilities"] as? [String: Any]
        let resourceEntries = detail == .toolsAndAuthOnly || capabilities?["resources"] == nil
            ? []
            : optionalList(method: "resources/list", resultKey: "resources", deadline: deadline)
        let resources = MCPStdioResultMapper.resourceList(from: ["resources": resourceEntries])
        let resourceTemplates = detail == .toolsAndAuthOnly || capabilities?["resources"] == nil
            ? []
            : optionalList(
                method: "resources/templates/list",
                resultKey: "resourceTemplates",
                deadline: deadline
            )
        let promptNames = detail == .toolsAndAuthOnly || capabilities?["prompts"] == nil
            ? []
            : optionalListNames(
                method: "prompts/list",
                resultKey: "prompts",
                nameKeys: ["name"],
                deadline: deadline
            )

        let serverInfo = initializeResult["serverInfo"] as? [String: Any]
        return MCPServerProbeResult(
            protocolVersion: initializeResult["protocolVersion"] as? String,
            serverName: serverInfo?["name"] as? String,
            serverVersion: serverInfo?["version"] as? String,
            serverInfo: MCPStdioResultMapper.jsonValue(from: serverInfo),
            tools: MCPStdioResultMapper.jsonValues(from: tools),
            resources: MCPStdioResultMapper.jsonValues(from: resourceEntries),
            resourceTemplates: MCPStdioResultMapper.jsonValues(from: resourceTemplates),
            toolDescriptors: toolDescriptors,
            resourceNames: resources.map(\.displayName),
            resourceURIs: resources.map(\.uri),
            promptNames: promptNames
        )
    }

    public func callTool(
        toolName: String,
        argumentsJSON: String = "{}",
        timeout: TimeInterval = 10.0
    ) throws -> ToolResult {
        ioLock.lock()
        defer { ioLock.unlock() }

        let toolName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            return ToolResult(ok: false, error: "MCP tool name is required.")
        }
        let arguments = try MCPStdioResultMapper.argumentsObject(from: argumentsJSON)
        let requestID = nextID()
        try write(method: "tools/call", id: requestID, params: [
            "name": toolName,
            "arguments": arguments
        ])
        let response = try readResponse(id: requestID, deadline: Date().addingTimeInterval(timeout))
        let result = try resultDictionary(from: response)
        return MCPStdioResultMapper.toolResult(from: result)
    }

    public func callToolResult(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval = 10.0
    ) throws -> MCPToolCallResult {
        ioLock.lock()
        defer { ioLock.unlock() }

        let toolName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            throw MCPProbeError.invalidMessage("MCP tool name is required.")
        }
        return try callToolResultLocked(
            toolName: toolName,
            arguments: arguments,
            metadata: metadata,
            timeout: timeout,
            progressContext: nil,
            onProgress: nil
        )
    }

    public func callToolEvents(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval = 10.0
    ) -> AsyncThrowingStream<MCPClientToolEvent, Error> {
        callToolEvents(
            toolName: toolName,
            arguments: arguments,
            metadata: metadata,
            timeout: timeout,
            elicitationHandler: nil
        )
    }

    public func callToolEvents(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval = 10.0,
        elicitationHandler: MCPClientElicitationHandler?
    ) -> AsyncThrowingStream<MCPClientToolEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    let progressContext = try MCPProgressRequestContext(metadata: metadata)
                    let result = try performStreamingToolCall(
                        toolName: toolName,
                        arguments: arguments,
                        metadata: metadata,
                        timeout: timeout,
                        progressContext: progressContext,
                        onProgress: { continuation.yield(.progress($0)) },
                        elicitationHandler: elicitationHandler
                    )
                    continuation.yield(.result(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performStreamingToolCall(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval,
        progressContext: MCPProgressRequestContext,
        onProgress: @escaping @Sendable (ToolExecutionProgress) -> Void,
        elicitationHandler: MCPClientElicitationHandler?
    ) throws -> MCPToolCallResult {
        ioLock.lock()
        defer { ioLock.unlock() }
        return try callToolResultLocked(
            toolName: toolName,
            arguments: arguments,
            metadata: metadata,
            timeout: timeout,
            progressContext: progressContext,
            onProgress: onProgress,
            elicitationHandler: elicitationHandler
        )
    }

    private func callToolResultLocked(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval,
        progressContext: MCPProgressRequestContext?,
        onProgress: ((ToolExecutionProgress) -> Void)?,
        elicitationHandler: MCPClientElicitationHandler? = nil
    ) throws -> MCPToolCallResult {
        let toolName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            throw MCPProbeError.invalidMessage("MCP tool name is required.")
        }
        var params: [String: Any] = [
            "name": toolName,
            "arguments": (arguments ?? .object([:])).foundationObject
        ]
        if let progressContext {
            params["_meta"] = MCPJSONValue.object(progressContext.metadata).foundationObject
        } else if let metadata {
            params["_meta"] = metadata.foundationObject
        }
        let requestID = nextID()
        try write(method: "tools/call", id: requestID, params: params)
        var tracker = progressContext.map { MCPProgressTracker(token: $0.token) }
        let response = try readResponse(
            id: requestID,
            deadline: Date().addingTimeInterval(timeout),
            progressTracker: &tracker,
            onProgress: onProgress,
            elicitationHandler: elicitationHandler
        )
        return MCPStdioResultMapper.toolCallResult(from: try resultDictionary(from: response))
    }

    public func readResource(
        uri: String,
        timeout: TimeInterval = 10.0
    ) throws -> ToolResult {
        ioLock.lock()
        defer { ioLock.unlock() }

        let uri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else {
            return ToolResult(ok: false, error: "MCP resource URI is required.")
        }

        let requestID = nextID()
        try write(method: "resources/read", id: requestID, params: ["uri": uri])
        let response = try readResponse(id: requestID, deadline: Date().addingTimeInterval(timeout))
        let result = try resultDictionary(from: response)
        return MCPStdioResultMapper.resourceResult(from: result, uri: uri)
    }

    public func readResourceResult(
        uri: String,
        timeout: TimeInterval = 10.0
    ) throws -> MCPResourceReadResult {
        ioLock.lock()
        defer { ioLock.unlock() }

        let uri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else {
            throw MCPProbeError.invalidMessage("MCP resource URI is required.")
        }
        let requestID = nextID()
        try write(method: "resources/read", id: requestID, params: ["uri": uri])
        let response = try readResponse(id: requestID, deadline: Date().addingTimeInterval(timeout))
        return MCPStdioResultMapper.resourceReadResult(from: try resultDictionary(from: response))
    }

    public func getPrompt(
        name: String,
        argumentsJSON: String = "{}",
        timeout: TimeInterval = 10.0
    ) throws -> ToolResult {
        ioLock.lock()
        defer { ioLock.unlock() }

        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return ToolResult(ok: false, error: "MCP prompt name is required.")
        }
        let arguments = try MCPStdioResultMapper.argumentsObject(from: argumentsJSON)
        let requestID = nextID()
        try write(method: "prompts/get", id: requestID, params: [
            "name": name,
            "arguments": arguments
        ])
        let response = try readResponse(id: requestID, deadline: Date().addingTimeInterval(timeout))
        let result = try resultDictionary(from: response)
        return MCPStdioResultMapper.promptResult(from: result, name: name)
    }

    private func nextID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func write(method: String, id: Int, params: [String: Any]) throws {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        standardInput.write(try MCPStdioMessageCodec.encodeJSONObject(message))
    }

    private func writeNotification(method: String, params: [String: Any]) throws {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        standardInput.write(try MCPStdioMessageCodec.encodeJSONObject(message))
    }

    private func readResponse(id: Int, deadline: Date) throws -> [String: Any] {
        var tracker: MCPProgressTracker?
        return try readResponse(
            id: id,
            deadline: deadline,
            progressTracker: &tracker,
            onProgress: nil
        )
    }

    private func readResponse(
        id: Int,
        deadline: Date,
        progressTracker: inout MCPProgressTracker?,
        onProgress: ((ToolExecutionProgress) -> Void)?,
        elicitationHandler: MCPClientElicitationHandler? = nil
    ) throws -> [String: Any] {
        while Date() < deadline {
            if Task.isCancelled { throw CancellationError() }
            if let message = try MCPStdioMessageCodec.nextMessageData(from: &readBuffer) {
                let object = try MCPStdioMessageCodec.decodeJSONObject(message)
                if object["method"] == nil, matchesResponseID(object["id"], id: id) {
                    return object
                }
                if try handleElicitationRequest(
                    object,
                    deadline: deadline,
                    handler: elicitationHandler
                ) {
                    continue
                }
                if var tracker = progressTracker {
                    let progress = tracker.consume(object)
                    progressTracker = tracker
                    if let progress { onProgress?(progress) }
                }
                continue
            }

            let remaining = min(0.1, max(0.05, deadline.timeIntervalSinceNow))
            if let data = try readAvailableData(timeout: remaining),
               !data.isEmpty {
                readBuffer.append(data)
            }
        }
        throw MCPProbeError.timeout("MCP server did not respond before the request timed out.")
    }

    private func handleElicitationRequest(
        _ object: [String: Any],
        deadline: Date,
        handler: MCPClientElicitationHandler?
    ) throws -> Bool {
        guard let requestID = MCPServerElicitationEnvelope.requestIDIfRecognized(in: object) else {
            return false
        }

        let response: MCPClientElicitationResponse
        do {
            let envelope = try MCPServerElicitationEnvelope.decode(from: object)
            guard clientCapabilities.supports(envelope.request) else {
                try writeResponse(id: requestID, response: .cancel())
                return true
            }
            response = try MCPAsyncElicitationBridge.resolve(
                envelope.request,
                using: handler,
                deadline: deadline
            )
        } catch is CancellationError {
            try writeResponse(id: requestID, response: .cancel())
            throw CancellationError()
        } catch {
            response = .cancel()
        }
        try writeResponse(id: requestID, response: response)
        return true
    }

    private func writeResponse(
        id: MCPJSONRPCRequestID,
        response: MCPClientElicitationResponse
    ) throws {
        standardInput.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": id.foundationObject,
            "result": response.foundationObject
        ]))
    }

    private func matchesResponseID(_ value: Any?, id: Int) -> Bool {
        if let int = value as? Int {
            return int == id
        }
        if let number = value as? NSNumber {
            return number.intValue == id
        }
        if let string = value as? String {
            return string == "\(id)"
        }
        return false
    }

    private func resultDictionary(from response: [String: Any]) throws -> [String: Any] {
        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "MCP server returned an error."
            throw MCPProbeError.responseError(message)
        }
        guard let result = response["result"] as? [String: Any] else {
            throw MCPProbeError.invalidMessage("MCP response did not include a result object.")
        }
        return result
    }

    private func optionalListNames(
        method: String,
        resultKey: String,
        nameKeys: [String],
        deadline: Date
    ) -> [String] {
        do {
            let requestID = nextID()
            try write(method: method, id: requestID, params: [:])
            let response = try readResponse(id: requestID, deadline: deadline)
            let result = try resultDictionary(from: response)
            return MCPStdioResultMapper.names(
                from: result,
                resultKey: resultKey,
                nameKeys: nameKeys
            )
        } catch {
            return []
        }
    }

    private func optionalResourceList(deadline: Date) -> [MCPStdioResultMapper.ResourceListEntry] {
        do {
            let requestID = nextID()
            try write(method: "resources/list", id: requestID, params: [:])
            let response = try readResponse(id: requestID, deadline: deadline)
            let result = try resultDictionary(from: response)
            return MCPStdioResultMapper.resourceList(from: result)
        } catch {
            return []
        }
    }

    private func optionalList(
        method: String,
        resultKey: String,
        deadline: Date
    ) -> [[String: Any]] {
        do {
            let requestID = nextID()
            try write(method: method, id: requestID, params: [:])
            let response = try readResponse(id: requestID, deadline: deadline)
            return (try resultDictionary(from: response)[resultKey] as? [[String: Any]]) ?? []
        } catch {
            return []
        }
    }

    private func readAvailableData(timeout: TimeInterval) throws -> Data? {
        let timeoutMilliseconds = Int32(max(1, min(timeout * 1000, Double(Int32.max))))
        var descriptor = pollfd(
            fd: Int32(standardOutput.fileDescriptor),
            events: Int16(POLLIN),
            revents: 0
        )
        let pollResult = poll(&descriptor, 1, timeoutMilliseconds)
        if pollResult == 0 {
            return nil
        }
        guard pollResult > 0 else {
            throw MCPProbeError.invalidMessage("MCP stdout poll failed with errno \(errno).")
        }

        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        let byteCount = read(descriptor.fd, &bytes, bytes.count)
        guard byteCount >= 0 else {
            throw MCPProbeError.invalidMessage("MCP stdout read failed with errno \(errno).")
        }
        return Data(bytes.prefix(byteCount))
    }

}
