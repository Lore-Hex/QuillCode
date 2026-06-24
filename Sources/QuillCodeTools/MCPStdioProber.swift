import Foundation
import QuillCodeCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct MCPServerProbeResult: Sendable, Hashable {
    public var protocolVersion: String?
    public var serverName: String?
    public var serverVersion: String?
    public var toolDescriptors: [MCPToolDescriptor]
    public var toolNames: [String]
    public var resourceNames: [String]
    public var resourceURIs: [String]
    public var promptNames: [String]

    public init(
        protocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        toolDescriptors: [MCPToolDescriptor] = [],
        toolNames: [String] = [],
        resourceNames: [String] = [],
        resourceURIs: [String] = [],
        promptNames: [String] = []
    ) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.toolDescriptors = toolDescriptors.isEmpty
            ? toolNames.map { MCPToolDescriptor(name: $0) }
            : toolDescriptors
        self.toolNames = toolNames.isEmpty
            ? self.toolDescriptors.map(\.name)
            : toolNames
        self.resourceNames = resourceNames
        self.resourceURIs = resourceURIs
        self.promptNames = promptNames
    }
}

public struct MCPToolDescriptor: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var requiredArguments: [String]
    public var optionalArguments: [String]
    public var schemaSummary: String

    public init(
        name: String,
        description: String = "",
        requiredArguments: [String] = [],
        optionalArguments: [String] = [],
        schemaSummary: String = ""
    ) {
        self.name = name
        self.description = description
        self.requiredArguments = requiredArguments
        self.optionalArguments = optionalArguments
        self.schemaSummary = schemaSummary
    }
}

public enum MCPProbeError: LocalizedError, Equatable {
    case invalidMessage(String)
    case responseError(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMessage(let message):
            return message
        case .responseError(let message):
            return message
        case .timeout(let message):
            return message
        }
    }
}

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
        let resources = capabilities?["resources"] == nil
            ? []
            : optionalResourceList(deadline: deadline)
        let promptNames = capabilities?["prompts"] == nil
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

public extension ToolDefinition {
    static let mcpCall = ToolDefinition(
        name: "host.mcp.call",
        description: "Call a tool on a verified project-local MCP stdio server. Use only server IDs and tool names listed in the description supplied by QuillCode.",
        parametersJSON: #"{"type":"object","required":["serverID","toolName"],"properties":{"serverID":{"type":"string"},"toolName":{"type":"string"},"arguments":{"type":"object"},"argumentsJSON":{"type":"string","description":"JSON object string for tool arguments when object arguments are not convenient."}}}"#,
        host: .mcp,
        risk: .append
    )

    static let mcpReadResource = ToolDefinition(
        name: "host.mcp.resource.read",
        description: "Read an advertised resource from a verified project-local MCP stdio server. Use only server IDs and resource names or URIs listed in the description supplied by QuillCode.",
        parametersJSON: #"{"type":"object","required":["serverID"],"properties":{"serverID":{"type":"string"},"resourceURI":{"type":"string","description":"Advertised MCP resource URI."},"uri":{"type":"string","description":"Alias for resourceURI."},"resourceName":{"type":"string","description":"Advertised resource display name when the URI is not convenient."},"name":{"type":"string","description":"Alias for resourceName."}}}"#,
        host: .mcp,
        risk: .read
    )

    static let mcpGetPrompt = ToolDefinition(
        name: "host.mcp.prompt.get",
        description: "Get an advertised prompt from a verified project-local MCP stdio server. Use only server IDs and prompt names listed in the description supplied by QuillCode.",
        parametersJSON: #"{"type":"object","required":["serverID","promptName"],"properties":{"serverID":{"type":"string"},"promptName":{"type":"string"},"name":{"type":"string","description":"Alias for promptName."},"arguments":{"type":"object"},"argumentsJSON":{"type":"string","description":"JSON object string for prompt arguments when object arguments are not convenient."}}}"#,
        host: .mcp,
        risk: .read
    )
}
