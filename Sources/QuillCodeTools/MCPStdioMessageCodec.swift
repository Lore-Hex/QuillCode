import Foundation

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
