import Foundation
import QuillCodeCore

public final class MCPStdioProber: @unchecked Sendable {
    let standardInput: FileHandle
    let standardOutput: FileHandle
    let ioLock = NSLock()
    var readBuffer = Data()
    var nextRequestID = 1
    var clientCapabilities = MCPClientCapabilities.none

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
                "name": "quillcode-mcp-client",
                "title": "QuillCode",
                "version": "0.1.0"
            ]
        ])

        let initialize = try readResponse(id: initializeID, deadline: deadline)
        let initializeResult = try resultDictionary(from: initialize)

        try writeNotification(method: "notifications/initialized", params: [:])
        let toolsListID = nextID()
        let toolsListContext = try MCPProgressRequestContext(metadata: nil)
        try write(method: "tools/list", id: toolsListID, params: [
            "_meta": MCPJSONValue.object(toolsListContext.metadata).foundationObject
        ])

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

    func nextID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    func write(method: String, id: Int, params: [String: Any]) throws {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        standardInput.write(try MCPStdioMessageCodec.encodeJSONObject(message))
    }

    func writeNotification(method: String, params: [String: Any]) throws {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        standardInput.write(try MCPStdioMessageCodec.encodeJSONObject(message))
    }

    func resultDictionary(from response: [String: Any]) throws -> [String: Any] {
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

}
