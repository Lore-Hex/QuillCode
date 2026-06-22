import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceTerminalEngineTests: XCTestCase {
    func testSyncSessionResetsProjectScopedStateOnlyWhenProjectChanges() {
        let firstID = UUID()
        let secondID = UUID()
        var terminal = TerminalState(
            projectID: firstID,
            currentDirectoryPath: "/tmp/first/nested",
            environmentOverrides: ["QUILL_TEST": "one"],
            removedEnvironmentKeys: ["PATH"],
            isVisible: true,
            draft: "pwd",
            entries: [
                TerminalCommandState(command: "pwd", stdout: "", stderr: "", exitCode: nil, ok: false, status: .running)
            ]
        )

        WorkspaceTerminalEngine.syncSessionToSelectedProject(
            terminal: &terminal,
            selectedProjectID: firstID,
            selectedProjectDisplayPath: "/tmp/first"
        )

        XCTAssertEqual(terminal.currentDirectoryPath, "/tmp/first/nested")
        XCTAssertEqual(terminal.environmentOverrides, ["QUILL_TEST": "one"])
        XCTAssertEqual(terminal.removedEnvironmentKeys, ["PATH"])
        XCTAssertTrue(terminal.isVisible)
        XCTAssertEqual(terminal.draft, "pwd")
        XCTAssertEqual(terminal.entries.count, 1)

        WorkspaceTerminalEngine.syncSessionToSelectedProject(
            terminal: &terminal,
            selectedProjectID: secondID,
            selectedProjectDisplayPath: "/tmp/second"
        )

        XCTAssertEqual(terminal.projectID, secondID)
        XCTAssertEqual(terminal.currentDirectoryPath, "/tmp/second")
        XCTAssertEqual(terminal.environmentOverrides, [:])
        XCTAssertEqual(terminal.removedEnvironmentKeys, [])
        XCTAssertTrue(terminal.isVisible)
        XCTAssertEqual(terminal.draft, "pwd")
        XCTAssertEqual(terminal.entries.count, 1)
    }

    func testCurrentDirectoryURLFallsBackToActiveRootWhenTerminalProjectIsStale() {
        let activeRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quill-active-root")
        let terminal = TerminalState(
            projectID: UUID(),
            currentDirectoryPath: "/wrong/project"
        )

        let current = WorkspaceTerminalEngine.currentDirectoryURL(
            terminal: terminal,
            selectedProjectID: UUID(),
            selectedProjectIsRemote: false,
            activeWorkspaceRoot: activeRoot
        )

        XCTAssertEqual(current, activeRoot)
        XCTAssertNil(WorkspaceTerminalEngine.currentDirectoryURL(
            terminal: terminal,
            selectedProjectID: terminal.projectID,
            selectedProjectIsRemote: true,
            activeWorkspaceRoot: activeRoot
        ))
    }

    func testClearHistoryRefusesRunningTerminalAndPreservesSession() {
        var running = TerminalState(
            currentDirectoryPath: "/tmp/project",
            environmentOverrides: ["QUILL_TEST": "one"],
            removedEnvironmentKeys: ["OLDPWD"],
            isVisible: true,
            draft: "pwd",
            isRunning: true,
            entries: [
                TerminalCommandState(command: "pwd", stdout: "out", stderr: "", exitCode: 0, ok: true)
            ]
        )

        XCTAssertFalse(WorkspaceTerminalEngine.clearHistory(terminal: &running))
        XCTAssertEqual(running.entries.count, 1)
        XCTAssertEqual(running.currentDirectoryPath, "/tmp/project")
        XCTAssertEqual(running.environmentOverrides, ["QUILL_TEST": "one"])

        running.isRunning = false
        XCTAssertTrue(WorkspaceTerminalEngine.clearHistory(terminal: &running))
        XCTAssertEqual(running.entries, [])
        XCTAssertEqual(running.currentDirectoryPath, "/tmp/project")
        XCTAssertEqual(running.environmentOverrides, ["QUILL_TEST": "one"])
        XCTAssertEqual(running.draft, "pwd")
    }

    func testStoppedEntryIgnoresLateOutputAndFinish() {
        let id = UUID()
        var terminal = TerminalState(entries: [
            TerminalCommandState(
                id: id,
                command: "sleep 1",
                stdout: "before",
                stderr: "stopped",
                exitCode: nil,
                ok: false,
                status: .stopped
            )
        ])

        WorkspaceTerminalEngine.appendOutput(id: id, stdout: "late", stderr: "ignored", terminal: &terminal)
        WorkspaceTerminalEngine.finishEntry(
            id: id,
            stdout: "done",
            stderr: "",
            exitCode: 0,
            ok: true,
            status: .done,
            terminal: &terminal
        )

        XCTAssertEqual(terminal.entries[0].stdout, "before")
        XCTAssertEqual(terminal.entries[0].stderr, "stopped")
        XCTAssertNil(terminal.entries[0].exitCode)
        XCTAssertFalse(terminal.entries[0].ok)
        XCTAssertEqual(terminal.entries[0].status, .stopped)
    }

    func testStopRunningEntriesMarksRunningEntriesStopped() {
        var terminal = TerminalState(
            isRunning: true,
            entries: [
                TerminalCommandState(command: "sleep 1", stdout: "", stderr: "", exitCode: nil, ok: false, status: .running),
                TerminalCommandState(command: "true", stdout: "", stderr: "", exitCode: 0, ok: true, status: .done)
            ]
        )

        WorkspaceTerminalEngine.stopRunningEntries(terminal: &terminal)

        XCTAssertEqual(terminal.entries[0].stderr, "Command stopped.")
        XCTAssertNil(terminal.entries[0].exitCode)
        XCTAssertFalse(terminal.entries[0].ok)
        XCTAssertEqual(terminal.entries[0].status, .stopped)
        XCTAssertEqual(terminal.entries[1].status, .done)
    }

    func testLocalExecutionContextWrapsCommandAndMarkers() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = WorkspaceTerminalEngine.localExecutionContext(
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

        let connection = WorkspaceTerminalEngine.remoteConnection(
            for: project,
            terminalCurrentDirectoryPath: "ssh://quill@feather.local:2222/srv/base/nested"
        )

        XCTAssertEqual(connection.path, "/srv/base/nested")
        XCTAssertEqual(connection.displayLabel, "ssh://quill@feather.local:2222/srv/base/nested")
    }

    func testRemoteEnvironmentPreambleFiltersInvalidKeysAndQuotesValues() {
        let preamble = WorkspaceTerminalEngine.remoteEnvironmentPreamble(
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

        let metadata = try XCTUnwrap(WorkspaceTerminalEngine.remoteMetadata(from: stdout, marker: marker))
        let delta = try XCTUnwrap(WorkspaceTerminalEngine.remoteEnvironmentDelta(metadata))

        XCTAssertEqual(metadata.stdout, "visible output")
        XCTAssertEqual(metadata.cwd, "/srv/new")
        XCTAssertEqual(delta.overrides, ["A": "changed", "C": "3"])
        XCTAssertEqual(delta.removedKeys, ["B"])
    }

    func testSessionResultReadsLocalMarkersAndRemovesThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = WorkspaceTerminalEngine.localExecutionContext(
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

        let result = WorkspaceTerminalEngine.sessionResult(for: context, stdout: "visible")

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
