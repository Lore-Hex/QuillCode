import Foundation
import QuillCodePlatform

enum AppServerWebSocketProtocolError: Error, LocalizedError, Sendable, Equatable {
    case connectionClosed
    case invalidHTTPRequest(String)
    case invalidUpgrade(String)
    case malformedFrame(String)
    case messageTooLarge(limit: Int)

    var errorDescription: String? {
        switch self {
        case .connectionClosed:
            "The WebSocket connection closed."
        case .invalidHTTPRequest(let reason):
            "Invalid HTTP request: \(reason)"
        case .invalidUpgrade(let reason):
            "Invalid WebSocket upgrade: \(reason)"
        case .malformedFrame(let reason):
            "Invalid WebSocket frame: \(reason)"
        case .messageTooLarge(let limit):
            "WebSocket message exceeds the \(limit)-byte limit."
        }
    }
}

struct AppServerHTTPRequest: Sendable, Equatable {
    let method: String
    let target: String
    let version: String
    private let headerValues: [String: [String]]

    init(method: String, target: String, version: String, headerValues: [String: [String]]) {
        self.method = method
        self.target = target
        self.version = version
        self.headerValues = headerValues
    }

    func header(_ name: String) -> String? {
        let values = headerValues[name.lowercased()]
        guard values?.count == 1 else { return nil }
        return values?.first
    }

    func hasHeader(_ name: String) -> Bool {
        headerValues[name.lowercased()]?.isEmpty == false
    }

    func headerContainsToken(_ name: String, token: String) -> Bool {
        headerValues[name.lowercased(), default: []]
            .flatMap { $0.split(separator: ",") }
            .contains { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(token) == .orderedSame }
    }
}

enum AppServerWebSocketInboundEvent: Sendable, Equatable {
    case text(Data)
    case binary
    case ping(Data)
    case pong
    case close(Data)
}

/// Implements the small RFC 6455 server surface required by Codex app-server clients. One reader
/// owns the mutable receive buffer; writes are independently serialized by
/// `AppServerWebSocketWriter`, so notifications and control frames never interleave on the wire.
final class AppServerWebSocketReader: @unchecked Sendable {
    private static let maximumHeaderBytes = 32 * 1_024

    private let connection: any SocketByteConnection
    private let maximumMessageBytes: Int
    private var buffer = Data()
    private var fragmentedOpcode: UInt8?
    private var fragmentedPayload = Data()

    init(connection: any SocketByteConnection, maximumMessageBytes: Int) {
        precondition(maximumMessageBytes > 0)
        self.connection = connection
        self.maximumMessageBytes = maximumMessageBytes
    }

    func readHTTPRequest() async throws -> AppServerHTTPRequest {
        let terminator = Data("\r\n\r\n".utf8)
        while buffer.range(of: terminator) == nil {
            guard buffer.count < Self.maximumHeaderBytes else {
                throw AppServerWebSocketProtocolError.invalidHTTPRequest("headers are too large")
            }
            guard let chunk = try await connection.receive(
                maxBytes: min(8 * 1_024, Self.maximumHeaderBytes - buffer.count)
            ) else {
                throw AppServerWebSocketProtocolError.connectionClosed
            }
            buffer.append(chunk)
        }
        guard let headerRange = buffer.range(of: terminator) else {
            throw AppServerWebSocketProtocolError.invalidHTTPRequest("missing header terminator")
        }
        let headerData = buffer[..<headerRange.lowerBound]
        buffer.removeSubrange(..<headerRange.upperBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw AppServerWebSocketProtocolError.invalidHTTPRequest("headers must be UTF-8")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw AppServerWebSocketProtocolError.invalidHTTPRequest("missing request line")
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3,
              requestParts[1].hasPrefix("/"),
              requestParts[2].hasPrefix("HTTP/1.")
        else {
            throw AppServerWebSocketProtocolError.invalidHTTPRequest("malformed request line")
        }

        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                throw AppServerWebSocketProtocolError.invalidHTTPRequest("malformed header")
            }
            let rawName = line[..<separator]
            let rawValue = line[line.index(after: separator)...]
            let name = rawName.lowercased()
            guard !name.isEmpty,
                  name.allSatisfy({ $0.isLetter || $0.isNumber || "!#$%&'*+-.^_`|~".contains($0) })
            else {
                throw AppServerWebSocketProtocolError.invalidHTTPRequest("invalid header name")
            }
            let value = rawValue.trimmingCharacters(in: .whitespaces)
            guard !value.contains("\r"), !value.contains("\n") else {
                throw AppServerWebSocketProtocolError.invalidHTTPRequest("invalid header value")
            }
            headers[name, default: []].append(value)
        }
        return AppServerHTTPRequest(
            method: String(requestParts[0]),
            target: String(requestParts[1]),
            version: String(requestParts[2]),
            headerValues: headers
        )
    }

    func receiveEvent() async throws -> AppServerWebSocketInboundEvent {
        while true {
            let frame = try await readFrame()
            switch frame.opcode {
            case 0x0:
                guard let fragmentedOpcode else {
                    throw AppServerWebSocketProtocolError.malformedFrame("unexpected continuation")
                }
                try appendMessageBytes(frame.payload)
                if frame.isFinal {
                    let payload = fragmentedPayload
                    self.fragmentedOpcode = nil
                    fragmentedPayload.removeAll(keepingCapacity: true)
                    return try completedEvent(opcode: fragmentedOpcode, payload: payload)
                }
            case 0x1, 0x2:
                guard fragmentedOpcode == nil else {
                    throw AppServerWebSocketProtocolError.malformedFrame(
                        "new data frame before fragmented message completed"
                    )
                }
                if frame.isFinal {
                    return try completedEvent(opcode: frame.opcode, payload: frame.payload)
                }
                fragmentedOpcode = frame.opcode
                fragmentedPayload.removeAll(keepingCapacity: true)
                try appendMessageBytes(frame.payload)
            case 0x8:
                try validateClosePayload(frame.payload)
                return .close(frame.payload)
            case 0x9:
                return .ping(frame.payload)
            case 0xA:
                return .pong
            default:
                throw AppServerWebSocketProtocolError.malformedFrame("unsupported opcode")
            }
        }
    }

    private func completedEvent(opcode: UInt8, payload: Data) throws -> AppServerWebSocketInboundEvent {
        guard payload.count <= maximumMessageBytes else {
            throw AppServerWebSocketProtocolError.messageTooLarge(limit: maximumMessageBytes)
        }
        if opcode == 0x2 { return .binary }
        guard String(data: payload, encoding: .utf8) != nil else {
            throw AppServerWebSocketProtocolError.malformedFrame("text is not valid UTF-8")
        }
        return .text(payload)
    }

    private func appendMessageBytes(_ bytes: Data) throws {
        guard bytes.count <= maximumMessageBytes - fragmentedPayload.count else {
            throw AppServerWebSocketProtocolError.messageTooLarge(limit: maximumMessageBytes)
        }
        fragmentedPayload.append(bytes)
    }

    private func validateClosePayload(_ payload: Data) throws {
        guard payload.count != 1 else {
            throw AppServerWebSocketProtocolError.malformedFrame("close code is truncated")
        }
        guard payload.count >= 2 else { return }
        let code = UInt16(payload[payload.startIndex]) << 8
            | UInt16(payload[payload.index(after: payload.startIndex)])
        let isReserved = [1_004, 1_005, 1_006, 1_015].contains(code)
        guard (1_000...4_999).contains(code), !isReserved else {
            throw AppServerWebSocketProtocolError.malformedFrame("invalid close code")
        }
        let reason = payload.dropFirst(2)
        guard String(data: reason, encoding: .utf8) != nil else {
            throw AppServerWebSocketProtocolError.malformedFrame("close reason is not valid UTF-8")
        }
    }

    private func readFrame() async throws -> Frame {
        let header = try await readExactly(2)
        let first = header[header.startIndex]
        let second = header[header.index(after: header.startIndex)]
        let isFinal = first & 0x80 != 0
        guard first & 0x70 == 0 else {
            throw AppServerWebSocketProtocolError.malformedFrame("reserved bits are set")
        }
        let opcode = first & 0x0F
        let isControl = opcode >= 0x8
        guard second & 0x80 != 0 else {
            throw AppServerWebSocketProtocolError.malformedFrame("client frames must be masked")
        }
        let shortLength = UInt64(second & 0x7F)
        let payloadLength: UInt64
        switch shortLength {
        case 126:
            payloadLength = try await readUnsignedInteger(byteCount: 2)
            guard payloadLength >= 126 else {
                throw AppServerWebSocketProtocolError.malformedFrame("non-canonical length")
            }
        case 127:
            payloadLength = try await readUnsignedInteger(byteCount: 8)
            guard payloadLength >= 65_536, payloadLength & (1 << 63) == 0 else {
                throw AppServerWebSocketProtocolError.malformedFrame("invalid 64-bit length")
            }
        default:
            payloadLength = shortLength
        }
        if isControl, (!isFinal || payloadLength > 125) {
            throw AppServerWebSocketProtocolError.malformedFrame("invalid control frame")
        }
        guard payloadLength <= UInt64(maximumMessageBytes),
              payloadLength <= UInt64(Int.max)
        else {
            throw AppServerWebSocketProtocolError.messageTooLarge(limit: maximumMessageBytes)
        }
        let mask = try await readExactly(4)
        var payload = try await readExactly(Int(payloadLength))
        let maskBytes = Array(mask)
        payload.withUnsafeMutableBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<rawBuffer.count {
                bytes[index] ^= maskBytes[index % 4]
            }
        }
        return Frame(isFinal: isFinal, opcode: opcode, payload: payload)
    }

    private func readUnsignedInteger(byteCount: Int) async throws -> UInt64 {
        let data = try await readExactly(byteCount)
        return data.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private func readExactly(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        while buffer.count < count {
            guard let chunk = try await connection.receive(
                maxBytes: min(64 * 1_024, count - buffer.count)
            ) else {
                throw AppServerWebSocketProtocolError.connectionClosed
            }
            buffer.append(chunk)
        }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    private struct Frame {
        let isFinal: Bool
        let opcode: UInt8
        let payload: Data
    }
}

actor AppServerWebSocketWriter {
    private let connection: any SocketByteConnection
    private var isClosed = false

    init(connection: any SocketByteConnection) {
        self.connection = connection
    }

    func sendHTTP(status: String, headers: [String: String] = [:], body: Data = Data()) async throws {
        guard !isClosed else { throw AppServerWebSocketProtocolError.connectionClosed }
        var lines = ["HTTP/1.1 \(status)"]
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name): \(value)")
        }
        lines.append("Content-Length: \(body.count)")
        lines.append("Connection: close")
        lines.append("")
        lines.append("")
        var response = Data(lines.joined(separator: "\r\n").utf8)
        response.append(body)
        try await connection.send(response)
    }

    func acceptUpgrade(key: String) async throws {
        guard let decodedKey = Data(base64Encoded: key), decodedKey.count == 16 else {
            throw AppServerWebSocketProtocolError.invalidUpgrade("invalid Sec-WebSocket-Key")
        }
        let magic = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let accept = Data(SHA1.digest(Array(magic.utf8))).base64EncodedString()
        let response = [
            "HTTP/1.1 101 Switching Protocols",
            "Connection: Upgrade",
            "Upgrade: websocket",
            "Sec-WebSocket-Accept: \(accept)",
            "",
            ""
        ].joined(separator: "\r\n")
        try await connection.send(Data(response.utf8))
    }

    func sendText(_ data: Data) async throws {
        try await sendFrame(opcode: 0x1, payload: data)
    }

    func sendPong(_ data: Data) async throws {
        try await sendFrame(opcode: 0xA, payload: data)
    }

    func sendClose(_ data: Data = Data()) async throws {
        guard !isClosed else { return }
        try await sendFrame(opcode: 0x8, payload: Data(data.prefix(125)))
        isClosed = true
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.close()
    }

    private func sendFrame(opcode: UInt8, payload: Data) async throws {
        guard !isClosed else { throw AppServerWebSocketProtocolError.connectionClosed }
        var frame = Data([0x80 | opcode])
        switch payload.count {
        case 0...125:
            frame.append(UInt8(payload.count))
        case 126...65_535:
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        default:
            frame.append(127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }
        frame.append(payload)
        try await connection.send(frame)
    }
}

private enum SHA1 {
    static func digest(_ message: [UInt8]) -> [UInt8] {
        var padded = message
        let bitLength = UInt64(message.count) * 8
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            padded.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        for offset in stride(from: 0, to: padded.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 80)
            for index in 0..<16 {
                let start = offset + index * 4
                words[index] = UInt32(padded[start]) << 24
                    | UInt32(padded[start + 1]) << 16
                    | UInt32(padded[start + 2]) << 8
                    | UInt32(padded[start + 3])
            }
            for index in 16..<80 {
                words[index] = rotateLeft(
                    words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16],
                    by: 1
                )
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4
            for index in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch index {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temporary = rotateLeft(a, by: 5)
                    &+ f &+ e &+ k &+ words[index]
                e = d
                d = c
                c = rotateLeft(b, by: 30)
                b = a
                a = temporary
            }
            h0 &+= a
            h1 &+= b
            h2 &+= c
            h3 &+= d
            h4 &+= e
        }

        var digest: [UInt8] = []
        digest.reserveCapacity(20)
        for word in [h0, h1, h2, h3, h4] {
            digest.append(UInt8((word >> 24) & 0xFF))
            digest.append(UInt8((word >> 16) & 0xFF))
            digest.append(UInt8((word >> 8) & 0xFF))
            digest.append(UInt8(word & 0xFF))
        }
        return digest
    }

    private static func rotateLeft(_ value: UInt32, by count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }
}
