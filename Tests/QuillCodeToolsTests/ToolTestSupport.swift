import XCTest
import QuillCodeCore
@testable import QuillCodeTools

extension XCTestCase {
    func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeToolTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    func makeTempGitRepoWithInitialCommit() throws -> URL {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("README.md")
        try "# Test repo\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "README.md").ok)
        let commit = ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root))
        XCTAssertTrue(commit.ok, "\(commit.error ?? "") \(commit.stderr)")
        return root
    }

    func initializeGitRepo(at root: URL) throws {
        let result = ShellToolExecutor().run(.init(
            command: "git init && git config user.email test@example.com && git config user.name QuillCodeTests",
            cwd: root
        ))
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }

    func currentBranchName(in root: URL) -> String {
        let result = ShellToolExecutor().run(.init(command: "git branch --show-current", cwd: root))
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makeFakeGitHubCLI(in root: URL, argumentsFile: URL) throws -> URL {
        let script = root.appendingPathComponent("fake-gh")
        let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsPath)'
        echo 'https://github.com/example/repo/pull/123'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    func makeFakeSSH(in root: URL, argumentsFile: URL) throws -> URL {
        let script = root.appendingPathComponent("fake-ssh")
        let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsPath)'
        echo 'remote-ok'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
