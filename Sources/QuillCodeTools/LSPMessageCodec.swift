import Foundation

/// Content-Length framing for JSON-RPC 2.0 over a byte stream — the base protocol of the Language
/// Server Protocol (and of MCP-over-stdio, which frames identically). A message is a
/// `Content-Length: N\r\n\r\n` header block followed by exactly N bytes of UTF-8 JSON.
///
/// Every byte handled here comes from an *untrusted* external subprocess, so parsing is bounded and
/// defensive: a missing/negative/non-numeric length, an oversized body, or a non-object body is a
/// thrown `LSPError.invalidMessage`, never a crash. Partial frames (a header without its full body,
/// or a body split across reads) return `nil` so the caller reads more and retries — it never blocks
/// waiting on bytes it already has.
public enum LSPMessageCodec {
    /// Upper bound on a single framed body. sourcekit-lsp can emit large `workspace/symbol` and
    /// `documentSymbol` payloads, so this is generous, but still finite so a bogus `Content-Length`
    /// can never make us allocate unboundedly.
    public static let maxMessageBytes = 16_000_000

    private static let headerSeparator = Data("\r\n\r\n".utf8)

    /// Frames a JSON object as a Content-Length message ready to write to the server's stdin.
    public static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw LSPError.invalidMessage("outgoing message is not a valid JSON object")
        }
        let body = try JSONSerialization.data(withJSONObject: object, options: [])
        var data = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        data.append(body)
        return data
    }

    /// Pulls the next complete message off the front of `buffer`, consuming its bytes, or returns
    /// `nil` when the buffer does not yet hold a full header+body. Throws on a structurally invalid
    /// frame (bad header, oversized length) — a caller that catches this should treat the stream as
    /// corrupt and tear the server down rather than resync mid-stream.
    public static func nextMessage(from buffer: inout Data) throws -> Data? {
        guard let headerRange = buffer.firstRange(of: headerSeparator) else {
            // Guard against a peer that never sends the separator: an unbounded header is an attack.
            if buffer.count > maxMessageBytes {
                throw LSPError.invalidMessage("header exceeded \(maxMessageBytes) bytes with no terminator")
            }
            return nil
        }

        let headerData = buffer[buffer.startIndex..<headerRange.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else {
            throw LSPError.invalidMessage("message header is not UTF-8")
        }
        let length = try contentLength(from: header)
        guard length <= maxMessageBytes else {
            throw LSPError.invalidMessage("message body of \(length) bytes exceeds \(maxMessageBytes)")
        }

        let bodyStart = headerRange.upperBound
        guard let bodyEnd = buffer.index(bodyStart, offsetBy: length, limitedBy: buffer.endIndex),
              bodyEnd <= buffer.endIndex,
              buffer.distance(from: bodyStart, to: buffer.endIndex) >= length
        else {
            return nil // body not fully arrived yet
        }

        let message = Data(buffer[bodyStart..<bodyEnd])
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return message
    }

    /// Parses a framed body into a JSON object, rejecting a body that is valid JSON but not an object
    /// (e.g. a bare array or number) — a JSON-RPC message is always an object.
    public static func decode(_ data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw LSPError.invalidMessage("message body is not JSON: \(error.localizedDescription)")
        }
        guard let dictionary = object as? [String: Any] else {
            throw LSPError.invalidMessage("message body is not a JSON object")
        }
        return dictionary
    }

    /// Extracts the `Content-Length` value from a header block, tolerating extra headers (e.g. the
    /// optional `Content-Type`) and case-insensitive names, per the LSP spec.
    private static func contentLength(from header: String) throws -> Int {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
            guard let length = Int(parts[1]), length >= 0 else {
                throw LSPError.invalidMessage("Content-Length value is not a non-negative integer")
            }
            return length
        }
        throw LSPError.invalidMessage("message is missing a Content-Length header")
    }
}
