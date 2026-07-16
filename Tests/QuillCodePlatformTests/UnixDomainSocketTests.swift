import CQuillPlatform
import Foundation
@testable import QuillCodePlatform
import XCTest

final class UnixDomainSocketTests: XCTestCase {
    func testRoundTripsDataAndCreatesPrivateSocket() async throws {
        try await withTemporarySocket { socketURL in
            let listener = try UnixDomainSocketListener(socketURL: socketURL)
            defer { listener.close() }
            let accept = Task { try await listener.accept() }
            let client = try UnixDomainSocketConnection.connect(to: socketURL)
            let server = try await accept.value
            defer {
                client.close()
                server.close()
            }

            try await client.send(Data("request\n".utf8))
            let request = try await server.receive()
            XCTAssertEqual(request, Data("request\n".utf8))
            try await server.send(Data("response\n".utf8))
            let response = try await client.receive()
            XCTAssertEqual(response, Data("response\n".utf8))

            let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        }
    }

    func testCloseCancelsPendingAcceptAndRemovesOwnedSocket() async throws {
        try await withTemporarySocket { socketURL in
            let listener = try UnixDomainSocketListener(socketURL: socketURL)
            let accept = Task { try await listener.accept() }
            try await Task.sleep(for: .milliseconds(20))

            listener.close()

            do {
                _ = try await accept.value
                XCTFail("Expected cancellation")
            } catch let error as UnixDomainSocketError {
                XCTAssertEqual(error, .cancelled)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
        }
    }

    func testActiveListenerCannotBeReplaced() async throws {
        try await withTemporarySocket { socketURL in
            let first = try UnixDomainSocketListener(socketURL: socketURL)
            defer { first.close() }

            XCTAssertThrowsError(try UnixDomainSocketListener(socketURL: socketURL)) { error in
                XCTAssertEqual(
                    error as? UnixDomainSocketError,
                    .listenerUnavailable(socketURL.path)
                )
            }
            let accept = Task { try await first.accept() }
            let client = try UnixDomainSocketConnection.connect(to: socketURL)
            let server = try await accept.value
            client.close()
            server.close()
        }
    }

    func testSimultaneousStartsLeaveOneReachableWinner() async throws {
        try await withTemporarySocket { socketURL in
            let listeners = await withTaskGroup(
                of: UnixDomainSocketListener?.self,
                returning: [UnixDomainSocketListener].self
            ) { group in
                for _ in 0..<12 {
                    group.addTask {
                        try? UnixDomainSocketListener(socketURL: socketURL)
                    }
                }
                var opened: [UnixDomainSocketListener] = []
                for await listener in group {
                    if let listener { opened.append(listener) }
                }
                return opened
            }
            defer { listeners.forEach { $0.close() } }

            XCTAssertEqual(listeners.count, 1)
            let winner = try XCTUnwrap(listeners.first)
            let accept = Task { try await winner.accept() }
            let client = try UnixDomainSocketConnection.connect(to: socketURL)
            let server = try await accept.value
            client.close()
            server.close()
        }
    }

    func testRegularFileCannotBeReplaced() async throws {
        try await withTemporarySocket { socketURL in
            let original = Data("keep me".utf8)
            try original.write(to: socketURL)

            XCTAssertThrowsError(try UnixDomainSocketListener(socketURL: socketURL))
            XCTAssertEqual(try Data(contentsOf: socketURL), original)
        }
    }

    func testClosePreservesPathReplacedAfterBind() async throws {
        try await withTemporarySocket { socketURL in
            let listener = try UnixDomainSocketListener(socketURL: socketURL)
            try FileManager.default.removeItem(at: socketURL)
            let replacement = Data("replacement".utf8)
            try replacement.write(to: socketURL)

            listener.close()

            XCTAssertEqual(try Data(contentsOf: socketURL), replacement)
        }
    }

    func testStaleOwnedSocketIsRecovered() async throws {
        try await withTemporarySocket { socketURL in
            var device: UInt64 = 0
            var inode: UInt64 = 0
            let staleDescriptor = socketURL.path.withCString {
                cquill_unix_open($0, &device, &inode)
            }
            XCTAssertGreaterThanOrEqual(staleDescriptor, 0)
            XCTAssertEqual(cquill_descriptor_close(staleDescriptor), 0)

            let recovered = try UnixDomainSocketListener(socketURL: socketURL)
            recovered.close()
            XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
        }
    }

    func testRejectsRelativeAndOversizedPaths() throws {
        XCTAssertThrowsError(
            try UnixDomainSocketListener(socketURL: URL(string: "relative.sock")!)
        )
        let oversized = "/tmp/" + String(repeating: "x", count: 512)
        XCTAssertThrowsError(
            try UnixDomainSocketListener(socketURL: URL(fileURLWithPath: oversized))
        )
    }

    private func withTemporarySocket(
        _ operation: (URL) async throws -> Void
    ) async throws {
        let suffix = UUID().uuidString.prefix(8)
        let root = URL(fileURLWithPath: "/tmp/qc-us-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try await operation(root.appendingPathComponent("app-server.sock"))
    }
}
