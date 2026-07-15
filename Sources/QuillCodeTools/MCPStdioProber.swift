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

    public init(standardInput: FileHandle, standardOutput: FileHandle) {
        self.standardInput = standardInput
        self.standardOutput = standardOutput
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
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
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
        var params: [String: Any] = [
            "name": toolName,
            "arguments": (arguments ?? .object([:])).foundationObject
        ]
        if let metadata { params["_meta"] = metadata.foundationObject }
        let requestID = nextID()
        try write(method: "tools/call", id: requestID, params: params)
        let response = try readResponse(id: requestID, deadline: Date().addingTimeInterval(timeout))
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
        while Date() < deadline {
            if let message = try MCPStdioMessageCodec.nextMessageData(from: &readBuffer) {
                let object = try MCPStdioMessageCodec.decodeJSONObject(message)
                if matchesResponseID(object["id"], id: id) {
                    return object
                }
                continue
            }

            let remaining = max(0.05, deadline.timeIntervalSinceNow)
            if let data = try readAvailableData(timeout: remaining),
               !data.isEmpty {
                readBuffer.append(data)
            }
        }
        throw MCPProbeError.timeout("MCP server did not respond before the request timed out.")
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
