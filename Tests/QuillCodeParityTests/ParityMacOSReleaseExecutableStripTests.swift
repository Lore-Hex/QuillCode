import Foundation
import XCTest

final class ParityMacOSReleaseExecutableStripTests: QuillCodeParityTestCase {
    func testStripHelperUsesSizeOptimizedSymbolPolicy() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runStrip(fixture: fixture, executable: fixture.executable)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.arguments, ["-S", "-x", fixture.executable.path])
        XCTAssertEqual(try Data(contentsOf: fixture.executable), Data("stripped-release-binary".utf8))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: fixture.executable.path))
        XCTAssertTrue(result.output.contains("Stripped release executable:"))
        XCTAssertTrue(result.output.contains("removed"))
    }

    func testStripHelperRejectsSymlinkBeforeInvokingTool() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let symlink = fixture.root.appendingPathComponent("linked-executable")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: fixture.executable
        )
        let original = try Data(contentsOf: fixture.executable)

        let result = try runStrip(fixture: fixture, executable: symlink)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("must be a regular executable file"))
        XCTAssertTrue(result.arguments.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.executable), original)
    }

    func testReleaseBuildStripsAfterCopyAndBeforeSigning() throws {
        let root = Self.packageRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-macos-app.sh"),
            encoding: .utf8
        )
        let stripScript = try String(
            contentsOf: root.appendingPathComponent("scripts/strip-macos-release-executable.sh"),
            encoding: .utf8
        )

        Self.assertSource(buildScript, containsAll: [
            #"if [[ "$CONFIGURATION" == "release" ]]; then"#,
            #""$ROOT_DIR/scripts/strip-macos-release-executable.sh" "$MACOS_DIR/$APP_NAME""#,
        ])
        Self.assertSource(stripScript, containsAll: [
            #"STRIP_BIN="${QUILLCODE_MACOS_STRIP_BIN:-/usr/bin/strip}""#,
            #""$STRIP_BIN" -S -x "$EXECUTABLE""#,
            #"[[ -L "$EXECUTABLE" || ! -f "$EXECUTABLE" || ! -x "$EXECUTABLE" ]]"#,
        ])

        let copy = try XCTUnwrap(buildScript.range(
            of: #"cp "$SOURCE_EXECUTABLE" "$MACOS_DIR/$APP_NAME""#
        ))
        let strip = try XCTUnwrap(buildScript.range(of: "strip-macos-release-executable.sh"))
        let signing = try XCTUnwrap(buildScript.range(of: #"if [[ -n "$SIGNING_IDENTITY" ]]; then"#))
        XCTAssertLessThan(copy.lowerBound, strip.lowerBound)
        XCTAssertLessThan(strip.lowerBound, signing.lowerBound)
    }

    private struct Fixture {
        var root: URL
        var executable: URL
        var stripTool: URL
        var argumentsLog: URL
    }

    private struct StripResult {
        var exitCode: Int32
        var output: String
        var arguments: [String]
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-release-strip-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let executable = root.appendingPathComponent("Quill Cowork")
        try Data(repeating: 0x51, count: 4_096).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let stripTool = root.appendingPathComponent("strip")
        let argumentsLog = root.appendingPathComponent("strip-arguments.txt")
        let fakeStrip = """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$@" > "${STRIP_TEST_ARGUMENTS_LOG:?}"
        printf 'stripped-release-binary' > "${@: -1}"
        """
        try fakeStrip.write(to: stripTool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: stripTool.path
        )
        return Fixture(
            root: root,
            executable: executable,
            stripTool: stripTool,
            argumentsLog: argumentsLog
        )
    }

    private func runStrip(fixture: Fixture, executable: URL) throws -> StripResult {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.packageRoot()
                .appendingPathComponent("scripts/strip-macos-release-executable.sh")
                .path,
            executable.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        var environment = ProcessInfo.processInfo.environment
        environment["QUILLCODE_MACOS_STRIP_BIN"] = fixture.stripTool.path
        environment["STRIP_TEST_ARGUMENTS_LOG"] = fixture.argumentsLog.path
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let arguments = ((try? String(contentsOf: fixture.argumentsLog, encoding: .utf8)) ?? "")
            .split(separator: "\n")
            .map(String.init)
        return StripResult(
            exitCode: process.terminationStatus,
            output: output,
            arguments: arguments
        )
    }
}
