import XCTest

final class ParityDownloadPublicationFreshnessGateTests: QuillCodeParityTestCase {
    func testCurrentMainTesterBuildRemainsPublishable() throws {
        let result = try runPlanner(refType: "branch", refName: "main")

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.publishRequired, "true")
        XCTAssertTrue(result.output.contains("is still current main"), result.output)
    }

    func testSupersededTesterBuildSkipsPublicationWithoutFailingTheWorkflow() throws {
        let result = try runPlanner(
            refType: "branch",
            refName: "main",
            mainCommit: String(repeating: "b", count: 40)
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.publishRequired, "false")
        XCTAssertTrue(result.output.contains("Skipping superseded tester build"), result.output)
    }

    func testImmutableStableTagRemainsPublishableWhenMainAdvances() throws {
        let result = try runPlanner(
            refType: "tag",
            refName: "v1.2.3",
            mainCommit: String(repeating: "b", count: 40)
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.publishRequired, "true")
        XCTAssertTrue(result.output.contains("Immutable stable tag v1.2.3"), result.output)
    }

    func testUnsupportedRefAndMovedStableTagFailClosed() throws {
        let feature = try runPlanner(refType: "branch", refName: "feature")
        let movedTag = try runPlanner(
            refType: "tag",
            refName: "v1.2.3",
            tagCommit: String(repeating: "b", count: 40)
        )

        XCTAssertEqual(feature.exitCode, 2, feature.output)
        XCTAssertNil(feature.publishRequired)
        XCTAssertTrue(feature.output.contains("only be published from main"), feature.output)
        XCTAssertEqual(movedTag.exitCode, 2, movedTag.output)
        XCTAssertNil(movedTag.publishRequired)
        XCTAssertTrue(movedTag.output.contains("no longer resolves"), movedTag.output)
    }

    private struct PlannerResult {
        var exitCode: Int32
        var output: String
        var publishRequired: String?
    }

    private func runPlanner(
        refType: String,
        refName: String,
        commit: String = String(repeating: "a", count: 40),
        mainCommit: String? = nil,
        tagCommit: String? = nil
    ) throws -> PlannerResult {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-publication-freshness-tests")
            .appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("bin")
        let outputURL = root.appendingPathComponent("github-output")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gitURL = bin.appendingPathComponent("git")
        try fakeGit.write(to: gitURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gitURL.path)

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.packageRoot()
                .appendingPathComponent("scripts")
                .appendingPathComponent("plan-download-publication.sh")
                .path
        ]
        process.standardOutput = pipe
        process.standardError = pipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(bin.path):\(environment["PATH"] ?? "")"
        environment["GITHUB_REF_TYPE"] = refType
        environment["GITHUB_REF_NAME"] = refName
        environment["GITHUB_SHA"] = commit
        environment["GITHUB_OUTPUT"] = outputURL.path
        environment["PUBLICATION_MAIN_COMMIT"] = mainCommit ?? commit
        environment["PUBLICATION_TAG_COMMIT"] = tagCommit ?? commit
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let githubOutput = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let publishRequired = githubOutput
            .split(separator: "\n")
            .first { $0.hasPrefix("publish-required=") }?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
        return PlannerResult(
            exitCode: process.terminationStatus,
            output: output,
            publishRequired: publishRequired
        )
    }

    private var fakeGit: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        if [[ "$1" == "fetch" ]]; then
          exit 0
        fi
        if [[ "$1" == "rev-parse" && "$2" == "--verify" ]]; then
          case "$3" in
            refs/remotes/origin/main*) printf '%s\n' "${PUBLICATION_MAIN_COMMIT:?}" ;;
            *) printf '%s\n' "${GITHUB_SHA:?}" ;;
          esac
          exit 0
        fi
        if [[ "$1" == "ls-remote" && "$2" == "--refs" && "$3" == "origin" ]]; then
          printf '%s\t%s\n' "${PUBLICATION_TAG_COMMIT:?}" "$4"
          exit 0
        fi
        echo "unexpected git invocation: $*" >&2
        exit 9
        """
    }
}
