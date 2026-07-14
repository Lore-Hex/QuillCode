import Foundation
import XCTest
@testable import QuillCodeTools

final class GitBranchPublicationInspectorTests: XCTestCase {
    func testInspectionFindsCleanUnpublishedBranchAndOpenPullRequest() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.commitFeatureChange()
        let gh = try fixture.fakeGitHubCLI(
            stdout: #"{"number":42,"title":"Publish worktree","url":"https://github.test/pull/42","state":"OPEN","isDraft":false,"baseRefName":"main","headRefName":"feature/publish"}"#
        )

        let inspection = try GitBranchPublicationInspector(githubCLIExecutable: gh).inspect(
            cwd: fixture.root,
            expectedBranch: "feature/publish",
            baseBranch: "main"
        )

        XCTAssertFalse(inspection.hasUncommittedChanges)
        XCTAssertEqual(inspection.commitsAheadOfBase, 1)
        XCTAssertNil(inspection.upstream)
        XCTAssertTrue(inspection.needsPush)
        XCTAssertEqual(inspection.upstreamRemote, nil)
        XCTAssertEqual(inspection.openPullRequest?.number, 42)
        XCTAssertEqual(inspection.openPullRequest?.url, "https://github.test/pull/42")
        XCTAssertNil(inspection.pullRequestLookupWarning)
    }

    func testInspectionTracksDirtyStateAndUpstreamAheadCount() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.commitFeatureChange()
        try fixture.runGit(["push", "-u", "origin", "feature/publish"])
        try "next\n".write(
            to: fixture.root.appendingPathComponent("next.txt"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.runGit(["add", "next.txt"])
        try fixture.runGit(["commit", "-m", "Next"])
        try "dirty\n".write(
            to: fixture.root.appendingPathComponent("dirty.txt"),
            atomically: true,
            encoding: .utf8
        )
        let gh = try fixture.fakeGitHubCLI(stderr: "no pull requests found for branch")

        let inspection = try GitBranchPublicationInspector(githubCLIExecutable: gh).inspect(
            cwd: fixture.root,
            expectedBranch: "feature/publish",
            baseBranch: "main"
        )

        XCTAssertTrue(inspection.hasUncommittedChanges)
        XCTAssertEqual(inspection.upstream, "origin/feature/publish")
        XCTAssertEqual(inspection.upstreamRemote, "origin")
        XCTAssertEqual(inspection.commitsAheadOfUpstream, 1)
        XCTAssertEqual(inspection.commitsBehindUpstream, 0)
        XCTAssertTrue(inspection.needsPush)
        XCTAssertNil(inspection.pullRequest)
        XCTAssertNil(inspection.pullRequestLookupWarning)
    }

    func testInspectionRejectsAChangedOwnedBranch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gh = try fixture.fakeGitHubCLI(stderr: "no pull requests found")

        XCTAssertThrowsError(
            try GitBranchPublicationInspector(githubCLIExecutable: gh).inspect(
                cwd: fixture.root,
                expectedBranch: "feature/other",
                baseBranch: "main"
            )
        ) { error in
            XCTAssertEqual(
                error as? GitBranchPublicationInspectionError,
                .branchChanged(expected: "feature/other", actual: "feature/publish")
            )
        }
    }

    func testInspectionSurfacesUnexpectedGitHubLookupFailureWithoutBlockingGitState() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.commitFeatureChange()
        let gh = try fixture.fakeGitHubCLI(stderr: "authentication required")

        let inspection = try GitBranchPublicationInspector(githubCLIExecutable: gh).inspect(
            cwd: fixture.root,
            expectedBranch: "feature/publish",
            baseBranch: "main"
        )

        XCTAssertNil(inspection.pullRequest)
        XCTAssertEqual(inspection.pullRequestLookupWarning, "authentication required")
        XCTAssertEqual(inspection.commitsAheadOfBase, 1)
    }
}

private final class Fixture {
    let root: URL
    private let remote: URL

    init() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-publication-\(UUID().uuidString)")
        root = parent.appendingPathComponent("repo")
        remote = parent.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], cwd: parent)
        try runGit(["init", "-b", "main"], cwd: root)
        try runGit(["config", "user.email", "quillcode@example.test"], cwd: root)
        try runGit(["config", "user.name", "QuillCode Tests"], cwd: root)
        try "base\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], cwd: root)
        try runGit(["commit", "-m", "Initial"], cwd: root)
        try runGit(["remote", "add", "origin", remote.path], cwd: root)
        try runGit(["push", "-u", "origin", "main"], cwd: root)
        try runGit(["switch", "-c", "feature/publish"], cwd: root)
    }

    func commitFeatureChange() throws {
        try "feature\n".write(
            to: root.appendingPathComponent("feature.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "feature.txt"])
        try runGit(["commit", "-m", "Feature"])
    }

    func fakeGitHubCLI(stdout: String = "", stderr: String = "") throws -> URL {
        let script = root.deletingLastPathComponent().appendingPathComponent("fake-gh-\(UUID().uuidString)")
        let status = stderr.isEmpty ? 0 : 1
        let contents = """
        #!/bin/sh
        printf '%s' \(shellQuote(stdout))
        printf '%s' \(shellQuote(stderr)) >&2
        exit \(status)
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    func runGit(_ arguments: [String]) throws {
        try runGit(arguments, cwd: root)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func runGit(_ arguments: [String], cwd: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = cwd
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "GitBranchPublicationInspectorTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: detail
            ])
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
