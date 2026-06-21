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
    public var toolNames: [String]

    public init(
        protocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        toolNames: [String] = []
    ) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.toolNames = toolNames
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

public enum MCPStdioMessageCodec {
    public static let maxMessageBytes = 5_000_000

    public static func encodeJSONObject(_ object: [String: Any]) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: object, options: [])
        let header = "Content-Length: \(body.count)\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    public static func nextMessageData(from buffer: inout Data) throws -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else {
            return nil
        }

        let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8) else {
            throw MCPProbeError.invalidMessage("MCP message header is not UTF-8.")
        }
        let contentLength = try contentLength(from: header)
        guard contentLength <= maxMessageBytes else {
            throw MCPProbeError.invalidMessage("MCP message exceeded \(maxMessageBytes) bytes.")
        }

        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard buffer.count >= bodyEnd else {
            return nil
        }

        let message = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return message
    }

    public static func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw MCPProbeError.invalidMessage("MCP message body is not a JSON object.")
        }
        return dictionary
    }

    private static func contentLength(from header: String) throws -> Int {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2,
                  parts[0].lowercased() == "content-length"
            else {
                continue
            }
            guard let length = Int(parts[1]),
                  length >= 0
            else {
                break
            }
            return length
        }
        throw MCPProbeError.invalidMessage("MCP message is missing a valid Content-Length header.")
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
        let toolNames = tools
            .compactMap { ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let serverInfo = initializeResult["serverInfo"] as? [String: Any]
        return MCPServerProbeResult(
            protocolVersion: initializeResult["protocolVersion"] as? String,
            serverName: serverInfo?["name"] as? String,
            serverVersion: serverInfo?["version"] as? String,
            toolNames: toolNames
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
        let arguments = try Self.argumentsObject(from: argumentsJSON)
        let requestID = nextID()
        try write(method: "tools/call", id: requestID, params: [
            "name": toolName,
            "arguments": arguments
        ])
        let response = try readResponse(id: requestID, deadline: Date().addingTimeInterval(timeout))
        let result = try resultDictionary(from: response)
        return Self.toolResult(from: result)
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

    private static func argumentsObject(from json: String) throws -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let data = trimmed.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            throw MCPProbeError.invalidMessage("MCP tool arguments must be a JSON object.")
        }
        return object
    }

    private static func toolResult(from result: [String: Any]) -> ToolResult {
        let isError = (result["isError"] as? Bool) ?? false
        let content = (result["content"] as? [[String: Any]]) ?? []
        let text = content
            .compactMap { item -> String? in
                if let text = item["text"] as? String {
                    return text
                }
                if let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]) {
                    return String(decoding: data, as: UTF8.self)
                }
                return nil
            }
            .joined(separator: "\n")
        if isError {
            return ToolResult(ok: false, stderr: text, error: text.isEmpty ? "MCP tool returned an error." : text)
        }
        if !text.isEmpty {
            return ToolResult(ok: true, stdout: text)
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            return ToolResult(ok: true, stdout: String(decoding: data, as: UTF8.self))
        }
        return ToolResult(ok: true)
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
}
