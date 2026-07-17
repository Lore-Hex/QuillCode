import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeSafety
import QuillCodeTools
import XCTest

final class AppServerGitDiffToRemoteTests: XCTestCase {
    func testReturnsUpstreamSHAAndCompleteWorkingTreeDiff() async throws {
        let fixture = try await makeFixture(withUpstream: true)

        try await fixture.request(id: 1, cwd: ".")
        var records = try await fixture.output.records()
        XCTAssertEqual(fixture.result(id: 1, records: records)?["sha"]?.stringValue, fixture.baseSHA)
        XCTAssertEqual(fixture.result(id: 1, records: records)?["diff"]?.stringValue, "")

        try write("base\ncommitted ahead\n", to: fixture.workspace.appendingPathComponent("tracked.txt"))
        try write("committed new file\n", to: fixture.workspace.appendingPathComponent("committed.txt"))
        try fixture.git("add", "tracked.txt", "committed.txt")
        try fixture.git("commit", "-m", "ahead")
        try write(
            "base\ncommitted ahead\nstaged line\n",
            to: fixture.workspace.appendingPathComponent("tracked.txt")
        )
        try fixture.git("add", "tracked.txt")
        try write(
            "base\ncommitted ahead\nstaged line\nunstaged line\n",
            to: fixture.workspace.appendingPathComponent("tracked.txt")
        )
        try write("ignored.txt\n", to: fixture.workspace.appendingPathComponent(".gitignore"))
        try write("ignored\n", to: fixture.workspace.appendingPathComponent("ignored.txt"))
        try write("untracked line\n", to: fixture.workspace.appendingPathComponent("untracked.txt"))
        try Data([0, 0xFF, 0x01, 0x7F]).write(
            to: fixture.workspace.appendingPathComponent("binary.dat")
        )
        let textConversionSentinel = fixture.root.appendingPathComponent("textconv-ran")
        try write(
            "tracked.txt diff=quill-probe\n",
            to: fixture.workspace.appendingPathComponent(".gitattributes")
        )
        try fixture.git(
            "config",
            "diff.quill-probe.textconv",
            "/usr/bin/touch \(textConversionSentinel.path)"
        )
        try fixture.git("config", "diff.external", "/usr/bin/false")

        try await fixture.request(id: 2, cwd: fixture.workspace.path)
        records = try await fixture.output.records()
        let result = try XCTUnwrap(fixture.result(id: 2, records: records))
        XCTAssertEqual(result["sha"]?.stringValue, fixture.baseSHA)
        let diff = try XCTUnwrap(result["diff"]?.stringValue)
        XCTAssertTrue(diff.contains("diff --git a/committed.txt b/committed.txt"))
        XCTAssertTrue(diff.contains("+committed ahead"))
        XCTAssertTrue(diff.contains("+staged line"))
        XCTAssertTrue(diff.contains("+unstaged line"))
        XCTAssertTrue(diff.contains("diff --git a/.gitignore b/.gitignore"))
        XCTAssertTrue(diff.contains("diff --git a/untracked.txt b/untracked.txt"))
        XCTAssertTrue(diff.contains("diff --git a/binary.dat b/binary.dat"))
        XCTAssertTrue(diff.contains("GIT binary patch"))
        XCTAssertFalse(diff.contains("diff --git a/ignored.txt b/ignored.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: textConversionSentinel.path))
        XCTAssertLessThan(
            try XCTUnwrap(diff.range(of: "diff --git a/tracked.txt")).lowerBound,
            try XCTUnwrap(diff.range(of: "diff --git a/.gitignore")).lowerBound
        )
    }

    func testUsesCurrentUpstreamTipRatherThanMergeBase() async throws {
        let fixture = try await makeFixture(withUpstream: true)
        let peer = fixture.root.appendingPathComponent("peer", isDirectory: true)
        try fixture.git(["clone", fixture.remote.path, peer.path], cwd: fixture.root)
        try fixture.git(["config", "user.email", "probe@example.com"], cwd: peer)
        try fixture.git(["config", "user.name", "Probe"], cwd: peer)
        try write("remote only\n", to: peer.appendingPathComponent("remote-only.txt"))
        try fixture.git(["add", "remote-only.txt"], cwd: peer)
        try fixture.git(["commit", "-m", "remote ahead"], cwd: peer)
        try fixture.git(["push"], cwd: peer)
        try fixture.git("fetch", "origin")
        let upstreamSHA = try fixture.gitOutput("rev-parse", "@{upstream}")

        try await fixture.request(id: 1, cwd: fixture.workspace.path)

        let records = try await fixture.output.records()
        let result = try XCTUnwrap(fixture.result(id: 1, records: records))
        XCTAssertEqual(result["sha"]?.stringValue, upstreamSHA)
        let diff = try XCTUnwrap(result["diff"]?.stringValue)
        XCTAssertTrue(diff.contains("diff --git a/remote-only.txt b/remote-only.txt"))
        XCTAssertTrue(diff.contains("deleted file mode 100644"))
    }

    func testRejectsMissingInvalidAndUnpublishedRepositoriesWithCodexErrors() async throws {
        let fixture = try await makeFixture(withUpstream: false)
        let nonRepository = fixture.root.appendingPathComponent("not-git", isDirectory: true)
        try FileManager.default.createDirectory(at: nonRepository, withIntermediateDirectories: true)

        try await fixture.request(id: 1, cwd: fixture.workspace.path)
        try await fixture.request(id: 2, params: [:])
        try await fixture.request(id: 3, cwd: nonRepository.path)
        try await fixture.request(id: 4, cwd: "")

        let records = try await fixture.output.records()
        XCTAssertEqual(
            fixture.errorMessage(id: 1, records: records),
            "failed to compute git diff to remote for cwd: \"\(fixture.workspace.path)\""
        )
        XCTAssertEqual(
            fixture.errorMessage(id: 2, records: records),
            "Invalid request: missing field `cwd`"
        )
        XCTAssertEqual(
            fixture.errorMessage(id: 3, records: records),
            "failed to compute git diff to remote for cwd: \"\(nonRepository.path)\""
        )
        XCTAssertEqual(
            fixture.errorMessage(id: 4, records: records),
            "failed to compute git diff to remote for cwd: \"\""
        )
        for id in 1...4 {
            XCTAssertEqual(fixture.errorCode(id: id, records: records), -32600)
        }
    }

    func testReaderFailsClosedWhenDiffExceedsConfiguredLimit() async throws {
        let fixture = try await makeFixture(withUpstream: true)
        try write(
            String(repeating: "large untracked line\n", count: 32),
            to: fixture.workspace.appendingPathComponent("large.txt")
        )
        let reader = AppServerGitDiffToRemoteReader(
            limits: AppServerGitDiffToRemoteLimits(
                maximumDiffBytes: 64,
                maximumUntrackedInventoryBytes: 1_024,
                maximumUntrackedFiles: 10
            )
        )

        XCTAssertThrowsError(try reader.read(cwd: fixture.workspace)) { error in
            XCTAssertEqual(error as? AppServerGitDiffToRemoteError, .outputTooLarge)
        }
    }

    private func makeFixture(withUpstream: Bool) async throws -> GitDiffFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-git-diff-test-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let runner = GitProcessRunner()
        try runGit(runner, ["init", "-b", "main"], cwd: workspace)
        try runGit(runner, ["config", "user.email", "probe@example.com"], cwd: workspace)
        try runGit(runner, ["config", "user.name", "Probe"], cwd: workspace)
        try write("base\n", to: workspace.appendingPathComponent("tracked.txt"))
        try runGit(runner, ["add", "tracked.txt"], cwd: workspace)
        try runGit(runner, ["commit", "-m", "base"], cwd: workspace)
        let baseSHA = try gitOutput(runner, ["rev-parse", "HEAD"], cwd: workspace)
        if withUpstream {
            try runGit(runner, ["init", "--bare", remote.path], cwd: root)
            try runGit(runner, ["remote", "add", "origin", remote.path], cwd: workspace)
            try runGit(runner, ["push", "-u", "origin", "main"], cwd: workspace)
            try runGit(
                runner,
                ["--git-dir=\(remote.path)", "symbolic-ref", "HEAD", "refs/heads/main"],
                cwd: root
            )
        }

        let output = GitDiffOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: MockLLMClient(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps
                )
            },
            sink: { line in await output.append(line) }
        )
        let fixture = GitDiffFixture(
            session: session,
            output: output,
            runner: runner,
            root: root,
            workspace: workspace,
            remote: remote,
            baseSHA: baseSHA
        )
        try await fixture.send([
            "id": 100,
            "method": "initialize",
            "params": ["clientInfo": ["name": "GitDiffTests", "version": "1"]]
        ])
        try await fixture.send(["method": "initialized", "params": [:]])
        return fixture
    }

    private func runGit(_ runner: GitProcessRunner, _ arguments: [String], cwd: URL) throws {
        let result = runner.runGit(arguments, cwd: cwd, timeoutSeconds: 30)
        guard result.ok else { throw GitDiffTestError.gitFailed(arguments, result.stderr) }
    }

    private func gitOutput(_ runner: GitProcessRunner, _ arguments: [String], cwd: URL) throws -> String {
        let result = runner.runGit(arguments, cwd: cwd, timeoutSeconds: 30)
        guard result.ok else { throw GitDiffTestError.gitFailed(arguments, result.stderr) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ value: String, to url: URL) throws {
        try value.write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct GitDiffFixture {
    let session: AppServerSession
    let output: GitDiffOutputCollector
    let runner: GitProcessRunner
    let root: URL
    let workspace: URL
    let remote: URL
    let baseSHA: String

    func request(id: Int, cwd: String) async throws {
        try await request(id: id, params: ["cwd": cwd])
    }

    func request(id: Int, params: [String: Any]) async throws {
        try await send(["id": id, "method": "gitDiffToRemote", "params": params])
    }

    func send(_ value: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        await session.receive(data)
    }

    func git(_ arguments: String...) throws {
        try git(arguments, cwd: workspace)
    }

    func git(_ arguments: [String], cwd: URL) throws {
        let result = runner.runGit(arguments, cwd: cwd, timeoutSeconds: 30)
        guard result.ok else { throw GitDiffTestError.gitFailed(arguments, result.stderr) }
    }

    func gitOutput(_ arguments: String...) throws -> String {
        let result = runner.runGit(arguments, cwd: workspace, timeoutSeconds: 30)
        guard result.ok else { throw GitDiffTestError.gitFailed(arguments, result.stderr) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func result(id: Int, records: [[String: CLIJSONValue]]) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    func errorMessage(id: Int, records: [[String: CLIJSONValue]]) -> String? {
        let record = records.first { $0["id"]?.numberValue == Double(id) }
        return record?["error"]?.objectValue?["message"]?.stringValue
    }

    func errorCode(id: Int, records: [[String: CLIJSONValue]]) -> Double? {
        let record = records.first { $0["id"]?.numberValue == Double(id) }
        return record?["error"]?.objectValue?["code"]?.numberValue
    }
}

private actor GitDiffOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw GitDiffTestError.invalidRecord
            }
            return object
        }
    }
}

private enum GitDiffTestError: Error {
    case gitFailed([String], String)
    case invalidRecord
}
