import Foundation
@testable import QuillCodePlatform
import XCTest

final class TCPSocketTests: XCTestCase {
    func testLoopbackListenerAcceptsFullDuplexConnection() async throws {
        let listener = try TCPSocketListener(host: "127.0.0.1", port: 0)
        XCTAssertGreaterThan(listener.port, 0)
        defer { listener.close() }

        async let accepted = listener.accept()
        let client = try TCPSocketConnection.connect(host: "127.0.0.1", port: listener.port)
        let server = try await accepted
        defer {
            client.close()
            server.close()
        }

        try await client.send(Data("hello".utf8))
        let serverMessage = try await server.receive(maxBytes: 5)
        XCTAssertEqual(serverMessage, Data("hello".utf8))
        try await server.send(Data("world".utf8))
        let clientMessage = try await client.receive(maxBytes: 5)
        XCTAssertEqual(clientMessage, Data("world".utf8))
    }

    func testListenerRejectsHostnamesAndUnavailableAddresses() {
        XCTAssertThrowsError(try TCPSocketListener(host: "localhost", port: 0))
        XCTAssertThrowsError(try TCPSocketListener(host: "not-an-address", port: 0))
        XCTAssertThrowsError(try TCPSocketListener(host: "192.0.2.1", port: 0))
    }

    func testIPv6LoopbackWhenAvailable() async throws {
        let listener: TCPSocketListener
        do {
            listener = try TCPSocketListener(host: "::1", port: 0)
        } catch {
            throw XCTSkip("IPv6 loopback is unavailable: \(error)")
        }
        defer { listener.close() }
        async let accepted = listener.accept()
        let client = try TCPSocketConnection.connect(host: "::1", port: listener.port)
        let server = try await accepted
        client.close()
        server.close()
    }
}
