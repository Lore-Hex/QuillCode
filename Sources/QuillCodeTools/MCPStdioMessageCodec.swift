import Foundation

public enum MCPStdioMessageCodec {
    public static let maxMessageBytes = 5_000_000

    private static let legacyHeaderPrefix = Data("Content-Length:".utf8)
    private static let legacyHeaderSeparator = Data("\r\n\r\n".utf8)

    public static func encodeJSONObject(_ object: [String: Any]) throws -> Data {
        var data = try jsonBody(object)
        guard data.count <= maxMessageBytes else {
            throw MCPProbeError.invalidMessage("MCP message exceeded \(maxMessageBytes) bytes.")
        }
        data.append(0x0A)
        return data
    }

    /// Serialize a JSON-RPC message to bare JSON bytes. The HTTP transport supplies its own framing;
    /// the stdio transport appends one newline through `encodeJSONObject` as required by MCP.
    public static func jsonBody(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }

    public static func nextMessageData(from buffer: inout Data) throws -> Data? {
        while !buffer.isEmpty {
            if buffer.starts(with: legacyHeaderPrefix) {
                return try nextLegacyMessageData(from: &buffer)
            }
            if legacyHeaderPrefix.starts(with: buffer) {
                return nil
            }

            guard let newline = buffer.firstIndex(of: 0x0A) else {
                guard buffer.count <= maxMessageBytes else {
                    throw MCPProbeError.invalidMessage("MCP message exceeded \(maxMessageBytes) bytes.")
                }
                return nil
            }

            var message = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if message.last == 0x0D { message.removeLast() }
            if message.isEmpty { continue }
            guard message.count <= maxMessageBytes else {
                throw MCPProbeError.invalidMessage("MCP message exceeded \(maxMessageBytes) bytes.")
            }
            return message
        }
        return nil
    }

    /// Accept the framing used by early QuillCode builds so an upgraded client can still connect to
    /// a legacy local server. New outbound messages always use MCP's newline-delimited JSON format.
    static func encodeLegacyJSONObject(_ object: [String: Any]) throws -> Data {
        let body = try jsonBody(object)
        guard body.count <= maxMessageBytes else {
            throw MCPProbeError.invalidMessage("MCP message exceeded \(maxMessageBytes) bytes.")
        }
        var data = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        data.append(body)
        return data
    }

    public static func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw MCPProbeError.invalidMessage("MCP message body is not a JSON object.")
        }
        return dictionary
    }

    private static func nextLegacyMessageData(from buffer: inout Data) throws -> Data? {
        guard let headerRange = buffer.range(of: legacyHeaderSeparator) else { return nil }
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
