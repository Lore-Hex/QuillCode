import Foundation

/// A single decoded Server-Sent Event.
public struct MCPSSEEvent: Sendable, Hashable {
    /// The `event:` field, or "message" when unset (per the SSE spec default).
    public var event: String
    /// The concatenated `data:` field values (multiple `data:` lines joined by "\n").
    public var data: String
    /// The `id:` field, if present. Used as the `Last-Event-ID` on reconnect.
    public var id: String?

    public init(event: String = "message", data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Incremental parser for the `text/event-stream` wire format (WHATWG SSE), hardened against
/// hostile input. All bytes fed in are untrusted:
///
/// - Frames are split on blank lines (LF or CRLF). A frame that never terminates is capped by
///   `maxEventBytes`; exceeding it throws rather than buffering without bound.
/// - Partial frames are retained across `append` calls until a terminator arrives.
/// - Non-UTF-8 bytes in a completed frame are lossily decoded (never crash).
/// - Comment lines (`:`-prefixed) and unknown fields are ignored per spec.
///
/// The parser only accumulates the current in-flight frame; completed events are returned and
/// dropped, so steady-state memory is bounded by `maxEventBytes` regardless of stream length.
public struct MCPSSEParser: Sendable {
    /// Maximum size of a single unterminated frame before the stream is rejected. Guards against
    /// a server that streams megabytes without ever emitting a blank line.
    public let maxEventBytes: Int

    private var buffer = Data()

    public init(maxEventBytes: Int = 8 * 1024 * 1024) {
        self.maxEventBytes = max(1, maxEventBytes)
    }

    /// Feed the next chunk of bytes and return any events that completed. Throws
    /// `MCPProbeError.invalidMessage` if a single frame grows past `maxEventBytes`.
    public mutating func append(_ chunk: Data) throws -> [MCPSSEEvent] {
        buffer.append(chunk)
        var events: [MCPSSEEvent] = []
        while let frame = try nextFrame() {
            if let event = Self.decodeFrame(frame) {
                events.append(event)
            }
        }
        return events
    }

    /// Extract the leading complete frame (up to and including its blank-line terminator) from
    /// the buffer, if one is present. Returns the frame bytes WITHOUT the terminator.
    private mutating func nextFrame() throws -> Data? {
        // A frame ends at the first blank line: "\n\n", "\r\n\r\n", or "\r\r".
        if let range = Self.firstFrameTerminator(in: buffer) {
            let frame = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            return frame
        }
        // No terminator yet — enforce the size cap on the pending frame.
        guard buffer.count <= maxEventBytes else {
            throw MCPProbeError.invalidMessage("MCP SSE frame exceeded \(maxEventBytes) bytes.")
        }
        return nil
    }

    /// Find the byte range of the first blank-line terminator in `data`. Recognizes LF, CRLF,
    /// and lone-CR line endings so a mixed-newline server cannot desync the parser.
    private static func firstFrameTerminator(in data: Data) -> Range<Data.Index>? {
        let bytes = [UInt8](data)
        let base = data.startIndex
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x0A { // LF
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    return base.advanced(by: index)..<base.advanced(by: index + 2)
                }
                if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A {
                    return base.advanced(by: index)..<base.advanced(by: index + 3)
                }
            } else if byte == 0x0D { // CR
                if index + 1 < bytes.count, bytes[index + 1] == 0x0D {
                    return base.advanced(by: index)..<base.advanced(by: index + 2)
                }
                if index + 3 < bytes.count,
                   bytes[index + 1] == 0x0A,
                   bytes[index + 2] == 0x0D,
                   bytes[index + 3] == 0x0A {
                    return base.advanced(by: index)..<base.advanced(by: index + 4)
                }
            }
            index += 1
        }
        return nil
    }

    /// Decode one frame's field lines into an event. Returns nil for a frame that carried no
    /// `data:` field (e.g. a keep-alive comment or a bare `id:` line).
    static func decodeFrame(_ frame: Data) -> MCPSSEEvent? {
        // Lossy decode: never trap on a malformed UTF-8 sequence from a hostile server.
        let text = String(decoding: frame, as: UTF8.self)
        var eventName: String?
        var dataLines: [String] = []
        var id: String?

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix(":") {
                continue // blank line or comment
            }
            let (field, value) = Self.splitField(line)
            switch field {
            case "event":
                eventName = value
            case "data":
                dataLines.append(value)
            case "id":
                // The spec forbids a NUL in the id; ignore such an id rather than storing it.
                if !value.contains("\u{0}") {
                    id = value
                }
            default:
                break // "retry" and unknown fields are ignored
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return MCPSSEEvent(
            event: eventName?.isEmpty == false ? eventName! : "message",
            data: dataLines.joined(separator: "\n"),
            id: id
        )
    }

    /// Split an SSE field line into (name, value). Per spec, the value has a single leading
    /// space stripped after the colon; a line with no colon is a field with an empty value.
    private static func splitField(_ line: String) -> (field: String, value: String) {
        guard let colon = line.firstIndex(of: ":") else {
            return (line, "")
        }
        let field = String(line[line.startIndex..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") {
            value.removeFirst()
        }
        return (field, value)
    }
}
