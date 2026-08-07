import XCTest

final class ParityDownloadBuildPlanGateTests: QuillCodeParityTestCase {
    func testNonScheduledAndTaggedRunsAlwaysBuildWithoutReleaseLookup() throws {
        let cases = [
            (event: "workflow_dispatch", refType: "branch"),
            (event: "push", refType: "branch"),
            (event: "schedule", refType: "tag")
        ]

        for testCase in cases {
            let result = try runPlanner(eventName: testCase.event, refType: testCase.refType)
            XCTAssertEqual(result.exitCode, 0, result.output)
            XCTAssertEqual(result.buildRequired, "true")
            XCTAssertTrue(result.ghLog.isEmpty)
        }
    }

    func testScheduledRunSkipsAnAlreadyPublishedCommit() throws {
        let commit = String(repeating: "a", count: 40)
        let result = try runPlanner(commit: commit, publishedCommit: commit)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.buildRequired, "false")
        XCTAssertTrue(result.output.contains("already publishes commit \(commit)"))
        XCTAssertTrue(result.ghLog.contains("release download tester-latest"))
    }

    func testScheduledRunBuildsWhenPublishedCommitIsStale() throws {
        let result = try runPlanner(publishedCommit: String(repeating: "b", count: 40))

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.buildRequired, "true")
        XCTAssertTrue(result.output.contains("instead of"))
    }

    func testScheduledRunRepairsMissingOrMalformedManifest() throws {
        let missing = try runPlanner(manifestAvailable: false)
        let malformed = try runPlanner(manifestMalformed: true)

        XCTAssertEqual(missing.exitCode, 0, missing.output)
        XCTAssertEqual(missing.buildRequired, "true")
        XCTAssertTrue(missing.output.contains("manifest is unavailable"))
        XCTAssertEqual(malformed.exitCode, 0, malformed.output)
        XCTAssertEqual(malformed.buildRequired, "true")
        XCTAssertTrue(malformed.output.contains("manifest is malformed"))
    }

    private struct PlannerResult {
        var exitCode: Int32
        var output: String
        var buildRequired: String?
        var ghLog: String
    }

    private func runPlanner(
        eventName: String = "schedule",
        refType: String = "branch",
        commit: String = String(repeating: "a", count: 40),
        publishedCommit: String = String(repeating: "a", count: 40),
        manifestAvailable: Bool = true,
        manifestMalformed: Bool = false
    ) throws -> PlannerResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-download-plan-tests")
            .appendingPathComponent(UUID().uuidString)
        let binDirectory = temporaryDirectory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let ghURL = binDirectory.appendingPathComponent("gh")
        let ghLogURL = temporaryDirectory.appendingPathComponent("gh.log")
        let githubOutputURL = temporaryDirectory.appendingPathComponent("github-output")
        try fakeGH.write(to: ghURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ghURL.path)

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.packageRoot()
                .appendingPathComponent("scripts")
                .appendingPathComponent("plan-download-build.sh")
                .path
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binDirectory.path):\(environment["PATH"] ?? "")"
        environment["GITHUB_EVENT_NAME"] = eventName
        environment["GITHUB_REF_TYPE"] = refType
        environment["GITHUB_SHA"] = commit
        environment["GITHUB_REPOSITORY"] = "Lore-Hex/QuillCode"
        environment["GITHUB_OUTPUT"] = githubOutputURL.path
        environment["DOWNLOAD_PLAN_MANIFEST_AVAILABLE"] = manifestAvailable ? "true" : "false"
        environment["DOWNLOAD_PLAN_MANIFEST_MALFORMED"] = manifestMalformed ? "true" : "false"
        environment["DOWNLOAD_PLAN_PUBLISHED_COMMIT"] = publishedCommit
        environment["DOWNLOAD_PLAN_GH_LOG"] = ghLogURL.path
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let githubOutput = (try? String(contentsOf: githubOutputURL, encoding: .utf8)) ?? ""
        let buildRequired = githubOutput
            .split(separator: "\n")
            .first { $0.hasPrefix("build-required=") }
            .map { String($0.dropFirst("build-required=".count)) }
        let ghLog = (try? String(contentsOf: ghLogURL, encoding: .utf8)) ?? ""
        return PlannerResult(
            exitCode: process.terminationStatus,
            output: output,
            buildRequired: buildRequired,
            ghLog: ghLog
        )
    }

    private var fakeGH: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${DOWNLOAD_PLAN_GH_LOG:?}"
        if [[ "$1" == "release" && "$2" == "download" ]]; then
          [[ "${DOWNLOAD_PLAN_MANIFEST_AVAILABLE:?}" == "true" ]] || exit 1
          output_directory="${!#}"
          if [[ "${DOWNLOAD_PLAN_MANIFEST_MALFORMED:?}" == "true" ]]; then
            printf '%s\n' '{not-json' > "$output_directory/latest-tester-build.json"
          else
            printf '{"commit":"%s"}\n' "${DOWNLOAD_PLAN_PUBLISHED_COMMIT:?}" \
              > "$output_directory/latest-tester-build.json"
          fi
          exit 0
        fi
        echo "unexpected gh invocation: $*" >&2
        exit 9
        """
    }
}
