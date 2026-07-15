import Foundation
import QuillCodeCore
@testable import QuillCodeTools
import XCTest

final class GitProcessRunnerTests: XCTestCase {
    func testLargeOutputIsDrainedWhileGitRuns() throws {
        let repository = try temporaryDirectory()
        let runner = GitProcessRunner()
        try requireSuccess(runner.runGit(["init", "--quiet"], cwd: repository, timeoutSeconds: 5))
        try requireSuccess(runner.runGit(
            ["config", "user.email", "quillcode-tests@example.invalid"],
            cwd: repository,
            timeoutSeconds: 5
        ))
        try requireSuccess(runner.runGit(
            ["config", "user.name", "QuillCode Tests"],
            cwd: repository,
            timeoutSeconds: 5
        ))

        let marker = "large-git-output-marker"
        let content = Array(repeating: String(repeating: "x", count: 120) + marker, count: 1_200)
            .joined(separator: "\n")
        try content.write(
            to: repository.appendingPathComponent("large.txt"),
            atomically: true,
            encoding: .utf8
        )
        try requireSuccess(runner.runGit(["add", "large.txt"], cwd: repository, timeoutSeconds: 5))
        try requireSuccess(runner.runGit(
            ["commit", "--quiet", "-m", "Large output fixture"],
            cwd: repository,
            timeoutSeconds: 5
        ))

        let result = runner.runGit(
            ["show", "--format=", "--no-ext-diff", "HEAD", "--"],
            cwd: repository,
            timeoutSeconds: 5
        )

        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertGreaterThan(result.stdout.utf8.count, 128 * 1_024)
        XCTAssertTrue(result.stdout.contains(marker))
    }

    private func requireSuccess(_ result: ToolResult) throws {
        guard result.ok else {
            throw GitProcessRunnerTestError.fixtureFailed(result.error ?? result.stderr)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-git-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private enum GitProcessRunnerTestError: Error {
    case fixtureFailed(String)
}
