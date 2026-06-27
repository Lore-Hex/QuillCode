import XCTest
@testable import QuillCodeTools

final class GitHubPullRequestMetadataResolverTests: XCTestCase {
    func testResolverUsesGitHubCLIAndDecodesMetadata() throws {
        let fixture = try makeFixture()
        let resolver = GitHubPullRequestMetadataResolver(
            runner: GitProcessRunner(githubCLIExecutable: fixture.executable)
        )

        let pullRequest = try resolver.pullRequest(selector: "123", cwd: fixture.root)
        let repository = try resolver.repository(cwd: fixture.root)

        XCTAssertEqual(pullRequest, GitHubPullRequestMetadata(number: 123, headRefOid: "abc123"))
        XCTAssertEqual(repository, GitHubRepositoryMetadata(nameWithOwner: "example/repo"))
        XCTAssertEqual(try fixture.invocations(), [
            "pr view 123 --json number,headRefOid",
            "repo view --json nameWithOwner"
        ])
    }

    func testResolverRejectsInvalidPullRequestMetadata() throws {
        let fixture = try makeFixture(
            pullRequestOutput: #"{"number":0,"headRefOid":""}"#
        )
        let resolver = GitHubPullRequestMetadataResolver(
            runner: GitProcessRunner(githubCLIExecutable: fixture.executable)
        )

        XCTAssertThrowsError(try resolver.pullRequest(selector: "123", cwd: fixture.root)) { error in
            XCTAssertEqual(
                error as? GitHubPullRequestMetadataError,
                .invalidPullRequestMetadata(#"{"number":0,"headRefOid":""}"#)
            )
        }
    }

    func testResolverRejectsInvalidRepositoryMetadata() throws {
        let fixture = try makeFixture(
            repositoryOutput: #"{"nameWithOwner":"bad owner/repo"}"#
        )
        let resolver = GitHubPullRequestMetadataResolver(
            runner: GitProcessRunner(githubCLIExecutable: fixture.executable)
        )

        XCTAssertThrowsError(try resolver.repository(cwd: fixture.root)) { error in
            XCTAssertEqual(
                error as? GitHubPullRequestMetadataError,
                .invalidRepositoryMetadata(#"{"nameWithOwner":"bad owner/repo"}"#)
            )
        }
    }
}

private extension GitHubPullRequestMetadataResolverTests {
    struct Fixture {
        var root: URL
        var executable: URL
        var invocationsFile: URL

        func invocations() throws -> [String] {
            try String(contentsOf: invocationsFile, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
        }
    }

    func makeFixture(
        pullRequestOutput: String = #"{"number":123,"headRefOid":"abc123"}"#,
        repositoryOutput: String = #"{"nameWithOwner":"example/repo"}"#
    ) throws -> Fixture {
        let root = try makeTempDirectory()
        let invocationsFile = root.appendingPathComponent("gh-invocations.txt")
        let executable = root.appendingPathComponent("fake-gh")
        let invocationsPath = shellSingleQuoted(invocationsFile.path)
        let pullRequestOutput = shellSingleQuoted(pullRequestOutput)
        let repositoryOutput = shellSingleQuoted(repositoryOutput)

        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> \(invocationsPath)
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
          printf '%s\\n' \(pullRequestOutput)
        elif [ "$1" = "repo" ] && [ "$2" = "view" ]; then
          printf '%s\\n' \(repositoryOutput)
        else
          echo 'unexpected fake gh invocation' >&2
          exit 1
        fi
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return Fixture(root: root, executable: executable, invocationsFile: invocationsFile)
    }

    func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
