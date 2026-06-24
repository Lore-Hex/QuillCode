import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceTerminalSessionAdapterTests: XCTestCase {
    func testLocalExecutionContextWrapsCommandAndMarkers() throws {
        let root = try makeQuillCodeTestDirectory()
        let context = WorkspaceTerminalSessionAdapter.localExecutionContext(
            command: "printf hello",
            workingDirectory: root,
            environment: ["QUILL_TEST": "value"],
            executionContext: .local(path: root.path)
        )

        XCTAssertEqual(context.request.cwd, root)
        XCTAssertEqual(context.request.environment, ["QUILL_TEST": "value"])
        XCTAssertEqual(context.surface, .local(path: root.path))
        XCTAssertTrue(context.request.command.contains("printf hello"))
        XCTAssertTrue(context.request.command.contains("printf '%s"))
        XCTAssertTrue(context.request.command.contains("\"$PWD\" >"))
        XCTAssertTrue(context.request.command.contains("/usr/bin/env -0"))
        XCTAssertNotNil(context.cwdMarkerURL)
        XCTAssertNotNil(context.environmentMarkerURL)
    }

    func testRemoteConnectionUsesPersistedDisplayPathForSSHRemoteCWD() {
        let project = ProjectRef(
            name: "Feather",
            path: "ssh://quill@feather.local:2222/srv/base",
            connection: .ssh(path: "/srv/base", host: "feather.local", user: "quill", port: 2222)
        )

        let connection = WorkspaceTerminalSessionAdapter.remoteConnection(
            for: project,
            terminalCurrentDirectoryPath: "ssh://quill@feather.local:2222/srv/base/nested"
        )

        XCTAssertEqual(connection.path, "/srv/base/nested")
        XCTAssertEqual(connection.displayLabel, "ssh://quill@feather.local:2222/srv/base/nested")
    }

    func testRemoteEnvironmentPreambleFiltersInvalidKeysAndQuotesValues() {
        let preamble = WorkspaceTerminalSessionAdapter.remoteEnvironmentPreamble(
            overrides: [
                "VALID": "can't stop",
                "BAD-KEY": "ignored"
            ],
            removedKeys: ["_OK", "BAD KEY"]
        )

        XCTAssertTrue(preamble.contains("unset _OK"))
        XCTAssertTrue(preamble.contains("export VALID='can'\\''t stop'"))
        XCTAssertFalse(preamble.contains("BAD-KEY"))
        XCTAssertFalse(preamble.contains("BAD KEY"))
    }

    func testRemoteMetadataStripsMarkersAndComputesEnvironmentDelta() throws {
        let marker = "__TEST_MARKER__"
        let baseHex = hexEncodedEnvironment(["A": "1", "B": "2", "PWD": "/old"])
        let finalHex = hexEncodedEnvironment(["A": "changed", "C": "3", "PWD": "/new"])
        let stdout = [
            "visible output",
            "\(marker):cwd",
            "/srv/new",
            "\(marker):base-env",
            baseHex,
            "\(marker):final-env",
            finalHex,
            "\(marker):end",
            ""
        ].joined(separator: "\n")

        let metadata = try XCTUnwrap(WorkspaceTerminalSessionAdapter.remoteMetadata(from: stdout, marker: marker))
        let delta = try XCTUnwrap(WorkspaceTerminalSessionAdapter.remoteEnvironmentDelta(metadata))

        XCTAssertEqual(metadata.stdout, "visible output")
        XCTAssertEqual(metadata.cwd, "/srv/new")
        XCTAssertEqual(delta.overrides, ["A": "changed", "C": "3"])
        XCTAssertEqual(delta.removedKeys, ["B"])
    }

    func testSessionResultReadsLocalMarkersAndRemovesThem() throws {
        let root = try makeQuillCodeTestDirectory()
        let context = WorkspaceTerminalSessionAdapter.localExecutionContext(
            command: "pwd",
            workingDirectory: root,
            environment: [:],
            executionContext: .local(path: root.path)
        )
        let cwdMarker = try XCTUnwrap(context.cwdMarkerURL)
        let environmentMarker = try XCTUnwrap(context.environmentMarkerURL)
        let nested = root.appendingPathComponent("nested").standardizedFileURL

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try nested.path.write(to: cwdMarker, atomically: true, encoding: .utf8)
        try environmentData(ProcessInfo.processInfo.environment.merging(["QUILL_ENGINE_TEST": "1"]) { _, new in new })
            .write(to: environmentMarker)

        let result = WorkspaceTerminalSessionAdapter.sessionResult(for: context, stdout: "visible")

        XCTAssertEqual(result.stdout, "visible")
        XCTAssertEqual(result.currentDirectoryPath, nested.path)
        XCTAssertEqual(result.environmentDelta?.overrides["QUILL_ENGINE_TEST"], "1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwdMarker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: environmentMarker.path))
    }

    private func hexEncodedEnvironment(_ environment: [String: String]) -> String {
        environmentData(environment)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func environmentData(_ environment: [String: String]) -> Data {
        var data = Data()
        for key in environment.keys.sorted() {
            guard let value = environment[key] else { continue }
            data.append(Data("\(key)=\(value)".utf8))
            data.append(0)
        }
        return data
    }
}
