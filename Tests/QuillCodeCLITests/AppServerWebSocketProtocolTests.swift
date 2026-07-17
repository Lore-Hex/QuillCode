import Foundation
@testable import QuillCodeCLI
import QuillCodePlatform
import QuillCodeTools
import XCTest

final class AppServerWebSocketProtocolTests: XCTestCase {
    func testParsesUpgradeAndUsesRFC6455AcceptValue() async throws {
        let request = """
        GET / HTTP/1.1\r
        Host: 127.0.0.1\r
        Upgrade: websocket\r
        Connection: keep-alive, Upgrade\r
        Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
        Sec-WebSocket-Version: 13\r
        \r

        """
        let socket = TestSocketConnection(incoming: [Data(request.utf8)])
        let reader = AppServerWebSocketReader(connection: socket, maximumMessageBytes: 1_024)
        let writer = AppServerWebSocketWriter(connection: socket)

        let parsed = try await reader.readHTTPRequest()
        XCTAssertEqual(parsed.method, "GET")
        XCTAssertTrue(parsed.headerContainsToken("connection", token: "upgrade"))
        try await writer.acceptUpgrade(key: try XCTUnwrap(parsed.header("sec-websocket-key")))

        let response = try XCTUnwrap(String(data: socket.sentData, encoding: .utf8))
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 101 Switching Protocols\r\n"))
        XCTAssertTrue(response.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo="))
    }

    func testReadsMaskedTextFragmentationAndInterleavedPing() async throws {
        let first = clientFrame(opcode: 0x1, payload: Data("hel".utf8), isFinal: false)
        let ping = clientFrame(opcode: 0x9, payload: Data("ok".utf8))
        let second = clientFrame(opcode: 0x0, payload: Data("lo".utf8))
        let socket = TestSocketConnection(incoming: [first + ping + second])
        let reader = AppServerWebSocketReader(connection: socket, maximumMessageBytes: 16)

        let pingEvent = try await reader.receiveEvent()
        XCTAssertEqual(pingEvent, .ping(Data("ok".utf8)))
        let textEvent = try await reader.receiveEvent()
        XCTAssertEqual(textEvent, .text(Data("hello".utf8)))
    }

    func testDropsCompleteBinaryMessageAndRejectsUnmaskedFrame() async throws {
        let binary = clientFrame(opcode: 0x2, payload: Data([1, 2, 3]))
        let socket = TestSocketConnection(incoming: [binary])
        let reader = AppServerWebSocketReader(connection: socket, maximumMessageBytes: 16)
        let binaryEvent = try await reader.receiveEvent()
        XCTAssertEqual(binaryEvent, .binary)

        let invalidSocket = TestSocketConnection(incoming: [Data([0x81, 0x01, 0x61])])
        let invalidReader = AppServerWebSocketReader(
            connection: invalidSocket,
            maximumMessageBytes: 16
        )
        await XCTAssertThrowsErrorAsync(try await invalidReader.receiveEvent()) { error in
            XCTAssertTrue(error.localizedDescription.contains("masked"))
        }
    }

    func testRejectsOversizedPayloadBeforeReadingBody() async {
        let header = Data([0x81, 0xFE, 0x01, 0x00])
        let socket = TestSocketConnection(incoming: [header])
        let reader = AppServerWebSocketReader(connection: socket, maximumMessageBytes: 32)
        await XCTAssertThrowsErrorAsync(try await reader.receiveEvent()) { error in
            XCTAssertEqual(
                error as? AppServerWebSocketProtocolError,
                .messageTooLarge(limit: 32)
            )
        }
    }

    func testRejectsMalformedClosePayloads() async {
        let truncated = clientFrame(opcode: 0x8, payload: Data([0x03]))
        let truncatedReader = AppServerWebSocketReader(
            connection: TestSocketConnection(incoming: [truncated]),
            maximumMessageBytes: 16
        )
        await XCTAssertThrowsErrorAsync(try await truncatedReader.receiveEvent())

        let invalidCode = clientFrame(opcode: 0x8, payload: Data([0x03, 0xED]))
        let invalidCodeReader = AppServerWebSocketReader(
            connection: TestSocketConnection(incoming: [invalidCode]),
            maximumMessageBytes: 16
        )
        await XCTAssertThrowsErrorAsync(try await invalidCodeReader.receiveEvent())

        let invalidUTF8 = clientFrame(opcode: 0x8, payload: Data([0x03, 0xE8, 0xFF]))
        let invalidUTF8Reader = AppServerWebSocketReader(
            connection: TestSocketConnection(incoming: [invalidUTF8]),
            maximumMessageBytes: 16
        )
        await XCTAssertThrowsErrorAsync(try await invalidUTF8Reader.receiveEvent())
    }

    func testCapabilityTokenPolicyUsesBearerHeaderAndDigest() throws {
        let digest = MCPCrypto.sha256(Array("correct-token".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let policy = try AppServerWebSocketAuthPolicy(configuration: .init(
            mode: .capabilityToken,
            tokenSHA256: digest
        ))
        XCTAssertNoThrow(try policy.authorize(request(authorization: "Bearer correct-token")))
        XCTAssertThrowsError(try policy.authorize(request(authorization: "Bearer wrong-token")))
        XCTAssertThrowsError(try policy.authorize(request(authorization: nil)))
    }

    func testSignedBearerPolicyValidatesSignatureTimeIssuerAndAudience() throws {
        let secret = "0123456789abcdef0123456789abcdef"
        let secretURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quillcode-websocket-secret-\(UUID().uuidString)"
        )
        try Data(secret.utf8).write(to: secretURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: secretURL) }
        let policy = try AppServerWebSocketAuthPolicy(configuration: .init(
            mode: .signedBearerToken,
            sharedSecretFile: secretURL.path,
            issuer: "issuer",
            audience: "client",
            maxClockSkewSeconds: 5
        ))
        let now = Date(timeIntervalSince1970: 2_000)
        let valid = try signedToken(
            secret: Array(secret.utf8),
            claims: ["exp": 2_030, "nbf": 1_990, "iss": "issuer", "aud": ["other", "client"]]
        )
        XCTAssertNoThrow(try policy.authorize(request(authorization: "Bearer \(valid)"), now: now))

        let expired = try signedToken(
            secret: Array(secret.utf8),
            claims: ["exp": 1_990, "iss": "issuer", "aud": "client"]
        )
        XCTAssertThrowsError(
            try policy.authorize(request(authorization: "Bearer \(expired)"), now: now)
        )

        let wrongIssuer = try signedToken(
            secret: Array(secret.utf8),
            claims: ["exp": 2_030, "iss": "wrong", "aud": "client"]
        )
        XCTAssertThrowsError(
            try policy.authorize(request(authorization: "Bearer \(wrongIssuer)"), now: now)
        )
    }

    func testHTTPParserRetainsPipelinedFirstFrame() async throws {
        let request = Data("GET / HTTP/1.1\r\nHost: local\r\n\r\n".utf8)
        let frame = clientFrame(opcode: 0x1, payload: Data("message".utf8))
        let socket = TestSocketConnection(incoming: [request + frame])
        let reader = AppServerWebSocketReader(connection: socket, maximumMessageBytes: 32)
        _ = try await reader.readHTTPRequest()
        let event = try await reader.receiveEvent()
        XCTAssertEqual(event, .text(Data("message".utf8)))
    }

    private func request(authorization: String?) -> AppServerHTTPRequest {
        var headers = ["host": ["127.0.0.1"]]
        if let authorization { headers["authorization"] = [authorization] }
        return AppServerHTTPRequest(
            method: "GET",
            target: "/",
            version: "HTTP/1.1",
            headerValues: headers
        )
    }

    private func clientFrame(
        opcode: UInt8,
        payload: Data,
        isFinal: Bool = true,
        mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
    ) -> Data {
        precondition(payload.count <= 125)
        var frame = Data([(isFinal ? 0x80 : 0) | opcode, 0x80 | UInt8(payload.count)])
        frame.append(contentsOf: mask)
        for (index, byte) in payload.enumerated() {
            frame.append(byte ^ mask[index % 4])
        }
        return frame
    }

    private func signedToken(secret: [UInt8], claims: [String: Any]) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        let headerSegment = base64URL(header)
        let payloadSegment = base64URL(payload)
        let signed = Array("\(headerSegment).\(payloadSegment)".utf8)
        let signature = hmacSHA256(key: secret, message: signed)
        return "\(headerSegment).\(payloadSegment).\(base64URL(Data(signature)))"
    }

    private func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var normalized = key.count > 64 ? MCPCrypto.sha256(key) : key
        normalized.append(contentsOf: repeatElement(0, count: max(0, 64 - normalized.count)))
        return MCPCrypto.sha256(
            normalized.map { $0 ^ 0x5C }
                + MCPCrypto.sha256(normalized.map { $0 ^ 0x36 } + message)
        )
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class TestSocketConnection: SocketByteConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [Data]
    private var sent = Data()
    private var closed = false

    init(incoming: [Data]) {
        self.incoming = incoming
    }

    var sentData: Data { lock.withLock { sent } }

    func receive(maxBytes: Int) async throws -> Data? {
        lock.withLock {
            guard !closed, !incoming.isEmpty else { return nil }
            let chunk = incoming.removeFirst()
            if chunk.count <= maxBytes { return chunk }
            incoming.insert(Data(chunk.dropFirst(maxBytes)), at: 0)
            return Data(chunk.prefix(maxBytes))
        }
    }

    func send(_ data: Data) async throws {
        lock.withLock {
            guard !closed else { return }
            sent.append(data)
        }
    }

    func close() { lock.withLock { closed = true } }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (any Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        handler(error)
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return operation()
    }
}
