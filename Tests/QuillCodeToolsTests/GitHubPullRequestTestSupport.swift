import XCTest
import QuillCodeCore
@testable import QuillCodeTools

struct GitHubPullRequestCLIFixture {
    var root: URL
    var argumentsFile: URL
    var git: GitToolExecutor

    func arguments() throws -> [String] {
        try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    func router() -> ToolRouter {
        ToolRouter(workspaceRoot: root, git: git)
    }
}

extension XCTestCase {
    func makeGitHubPullRequestFixture() throws -> GitHubPullRequestCLIFixture {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeGitHubCLI = try makeFakeGitHubCLI(in: root, argumentsFile: argumentsFile)
        return GitHubPullRequestCLIFixture(
            root: root,
            argumentsFile: argumentsFile,
            git: GitToolExecutor(githubCLIExecutable: fakeGitHubCLI)
        )
    }

    func makeGitHubPullRequestReviewCommentFixture() throws -> GitHubPullRequestCLIFixture {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeGitHubCLI = try makeReviewCommentFakeGitHubCLI(in: root, argumentsFile: argumentsFile)
        return GitHubPullRequestCLIFixture(
            root: root,
            argumentsFile: argumentsFile,
            git: GitToolExecutor(githubCLIExecutable: fakeGitHubCLI)
        )
    }

    func assertGitHubToolResultOK(
        _ result: ToolResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)", file: file, line: line)
    }

    func assertGitHubArguments(
        _ fixture: GitHubPullRequestCLIFixture,
        _ expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try fixture.arguments(), expected, file: file, line: line)
    }

    func assertNoGitHubInvocation(
        _ fixture: GitHubPullRequestCLIFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.argumentsFile.path),
            file: file,
            line: line
        )
    }

    func makeReviewCommentFakeGitHubCLI(in root: URL, argumentsFile: URL) throws -> URL {
        let script = root.appendingPathComponent("fake-gh-review-comment")
        let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
          echo '{"number":123,"headRefOid":"abc123"}'
        elif [ "$1" = "repo" ] && [ "$2" = "view" ]; then
          echo '{"nameWithOwner":"example/repo"}'
        elif [ "$1" = "api" ]; then
          printf '%s\\n' "$@" > '\(argumentsPath)'
          echo '{"html_url":"https://github.com/example/repo/pull/123#discussion_r99"}'
        else
          printf '%s\\n' "$@" > '\(argumentsPath)'
          echo 'unexpected fake gh invocation' >&2
          exit 1
        fi
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
