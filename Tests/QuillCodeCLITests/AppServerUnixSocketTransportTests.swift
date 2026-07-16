import Foundation
@testable import QuillCodeCLI
import XCTest

final class AppServerUnixSocketTransportTests: XCTestCase {
    func testDefaultSocketUsesPrivateControlDirectoryInsideConfiguredHome() throws {
        try withTemporaryDirectory { root in
            let home = root.appendingPathComponent("home", isDirectory: true)
            let request = CLIAppServerRequest(
                transport: .unix(path: nil),
                live: false,
                home: home
            )

            let socketURL = try AppServerUnixSocketTransport.socketURL(for: request)

            XCTAssertEqual(
                socketURL.path,
                home.appendingPathComponent("app-server-control/app-server-control.sock").path
            )
            let attributes = try FileManager.default.attributesOfItem(
                atPath: socketURL.deletingLastPathComponent().path
            )
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue & 0o777, 0o700)
        }
    }

    func testExplicitSocketDoesNotCreateOrRewriteItsParent() throws {
        try withTemporaryDirectory { root in
            let parent = root.appendingPathComponent("missing", isDirectory: true)
            let explicit = parent.appendingPathComponent("custom.sock")
            let request = CLIAppServerRequest(
                transport: .unix(path: explicit.path),
                live: false,
                home: root.appendingPathComponent("unused-home")
            )

            XCTAssertEqual(
                try AppServerUnixSocketTransport.socketURL(for: request),
                explicit
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path))
        }
    }

    func testDefaultControlPathRejectsFilesAndSymbolicLinks() throws {
        try withTemporaryDirectory { root in
            let home = root.appendingPathComponent("home", isDirectory: true)
            let request = CLIAppServerRequest(
                transport: .unix(path: nil),
                live: false,
                home: home
            )
            let firstSocket = try AppServerUnixSocketTransport.socketURL(for: request)
            let controlDirectory = firstSocket.deletingLastPathComponent()
            try FileManager.default.removeItem(at: controlDirectory)
            try Data("keep".utf8).write(to: controlDirectory)
            XCTAssertThrowsError(try AppServerUnixSocketTransport.socketURL(for: request))
            XCTAssertEqual(try Data(contentsOf: controlDirectory), Data("keep".utf8))

            try FileManager.default.removeItem(at: controlDirectory)
            let target = root.appendingPathComponent("target", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: target.path
            )
            try FileManager.default.createSymbolicLink(
                at: controlDirectory,
                withDestinationURL: target
            )

            XCTAssertThrowsError(try AppServerUnixSocketTransport.socketURL(for: request))
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue & 0o777, 0o755)
        }
    }

    private func withTemporaryDirectory(
        _ operation: (URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "app-server-unix-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try operation(root)
    }
}
