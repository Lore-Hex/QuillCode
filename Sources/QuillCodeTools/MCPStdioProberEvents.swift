import Foundation
import QuillCodeCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension MCPStdioProber {
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

    func readResponse(id: Int, deadline: Date) throws -> [String: Any] {
        var tracker: MCPProgressTracker?
        return try readResponse(
            id: id,
            deadline: deadline,
            progressTracker: &tracker,
            onProgress: nil
        )
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
            if let data = try readAvailableData(timeout: remaining), !data.isEmpty {
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
        if let int = value as? Int { return int == id }
        if let number = value as? NSNumber { return number.intValue == id }
        if let string = value as? String { return string == "\(id)" }
        return false
    }

    private func readAvailableData(timeout: TimeInterval) throws -> Data? {
        let timeoutMilliseconds = Int32(max(1, min(timeout * 1000, Double(Int32.max))))
        var descriptor = pollfd(
            fd: Int32(standardOutput.fileDescriptor),
            events: Int16(POLLIN),
            revents: 0
        )
        let pollResult = poll(&descriptor, 1, timeoutMilliseconds)
        if pollResult == 0 { return nil }
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
