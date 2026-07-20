import Foundation
import QuillCodeCore
@testable import QuillCodeTools
import XCTest

final class ShellProcessSandboxTests: XCTestCase {
    func testDenialClassifierRequiresAnActiveSandbox() {
        let direct = ShellProcessLaunch(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [],
            isSandboxed: false
        )

        XCTAssertFalse(ShellProcessSandbox.isLikelyDenial(
            launch: direct,
            exitCode: 1,
            stdout: "",
            stderr: "Operation not permitted"
        ))
    }

    func testDenialClassifierRecognizesSandboxFailuresButNotCommandLookupFailures() {
        let sandboxed = ShellProcessLaunch(
            executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: [],
            isSandboxed: true
        )

        XCTAssertTrue(ShellProcessSandbox.isLikelyDenial(
            launch: sandboxed,
            exitCode: 1,
            stdout: "",
            stderr: "sh: file: Operation not permitted"
        ))
        XCTAssertTrue(ShellProcessSandbox.isLikelyDenial(
            launch: sandboxed,
            exitCode: 1,
            stdout: "",
            stderr: "sh: file: Read-only file system"
        ))
        XCTAssertFalse(ShellProcessSandbox.isLikelyDenial(
            launch: sandboxed,
            exitCode: 1,
            stdout: "",
            stderr: "test assertion failed"
        ))
        XCTAssertFalse(ShellProcessSandbox.isLikelyDenial(
            launch: sandboxed,
            exitCode: 127,
            stdout: "",
            stderr: "sh: command not found: Operation not permitted"
        ))
    }

    func testWorkspaceWriteSandboxAllowsWorkspaceAndBlocksOutsideWrite() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            throw XCTSkip("This integration test requires macOS Seatbelt.")
        }
        let workspace = try temporaryDirectory(prefix: "quillcode-shell-sandbox-workspace")
        let outside = try packageScratchDirectory()
        let allowedFile = workspace.appendingPathComponent("allowed.txt")
        let blockedFile = outside.appendingPathComponent("blocked.txt")
        let command = [
            "printf allowed > \(shellQuote(allowedFile.path))",
            "printf blocked > \(shellQuote(blockedFile.path))"
        ].joined(separator: "; ")

        let result = ShellToolExecutor(sandboxPolicy: .init(
            mode: .workspaceWrite,
            writableRoots: [workspace]
        )).run(.init(command: command, cwd: workspace))

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.failureKind, .sandboxDenied)
        XCTAssertEqual(try String(contentsOf: allowedFile, encoding: .utf8), "allowed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedFile.path))
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func packageScratchDirectory() throws -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = packageRoot.appendingPathComponent(
            ".shell-sandbox-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
