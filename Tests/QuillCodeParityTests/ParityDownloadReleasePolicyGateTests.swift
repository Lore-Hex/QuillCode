import XCTest

final class ParityDownloadReleasePolicyGateTests: QuillCodeParityTestCase {
    func testCurrentMainTesterBuildPasses() throws {
        let result = try runPolicy(refType: "branch", refName: "main")

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Validated tester download build at current main commit"))
        XCTAssertTrue(result.ghLog.isEmpty)
    }

    func testTesterBuildRejectsFeatureAndStaleMainRefs() throws {
        let feature = try runPolicy(refType: "branch", refName: "feature")
        let stale = try runPolicy(
            refType: "branch",
            refName: "main",
            mainCommit: String(repeating: "b", count: 40)
        )

        XCTAssertEqual(feature.exitCode, 2, feature.output)
        XCTAssertTrue(feature.output.contains("only be published from main"))
        XCTAssertEqual(stale.exitCode, 2, stale.output)
        XCTAssertTrue(stale.output.contains("Refusing to publish a stale tester build"))
    }

    func testStableBuildRequiresCanonicalTagOnMain() throws {
        let malformed = try runPolicy(refType: "tag", refName: "v1.2")
        let offMain = try runPolicy(refType: "tag", refName: "v1.2.3", isMainAncestor: false)

        XCTAssertEqual(malformed.exitCode, 2, malformed.output)
        XCTAssertTrue(malformed.output.contains("canonical vMAJOR.MINOR.PATCH"))
        XCTAssertEqual(offMain.exitCode, 2, offMain.output)
        XCTAssertTrue(offMain.output.contains("must point to a commit on main"))
    }

    func testStableBuildRequiresSuccessfulCIAndNewRelease() throws {
        let missingCI = try runPolicy(refType: "tag", refName: "v1.2.3", successfulCIRuns: 0)
        let existingRelease = try runPolicy(refType: "tag", refName: "v1.2.3", releaseExists: true)

        XCTAssertEqual(missingCI.exitCode, 2, missingCI.output)
        XCTAssertTrue(missingCI.output.contains("requires a successful CI run"))
        XCTAssertEqual(existingRelease.exitCode, 2, existingRelease.output)
        XCTAssertTrue(existingRelease.output.contains("already exists and is immutable"))
    }

    func testValidatedStableBuildPassesWithCIAndNoExistingRelease() throws {
        let result = try runPolicy(refType: "tag", refName: "v1.2.3")

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Validated immutable stable release v1.2.3"))
        XCTAssertTrue(result.ghLog.contains("run list --repo Lore-Hex/QuillCode --workflow ci.yml"))
        XCTAssertTrue(result.ghLog.contains("release view v1.2.3 --repo Lore-Hex/QuillCode"))
    }

    private struct PolicyResult {
        var exitCode: Int32
        var output: String
        var ghLog: String
    }

    private func runPolicy(
        refType: String,
        refName: String,
        commit: String = String(repeating: "a", count: 40),
        mainCommit: String? = nil,
        tagCommit: String? = nil,
        isMainAncestor: Bool = true,
        successfulCIRuns: Int = 1,
        releaseExists: Bool = false
    ) throws -> PolicyResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-release-policy-tests")
            .appendingPathComponent(UUID().uuidString)
        let binDirectory = temporaryDirectory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let gitURL = binDirectory.appendingPathComponent("git")
        let ghURL = binDirectory.appendingPathComponent("gh")
        let ghLogURL = temporaryDirectory.appendingPathComponent("gh.log")
        try fakeGit.write(to: gitURL, atomically: true, encoding: .utf8)
        try fakeGH.write(to: ghURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gitURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ghURL.path)

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.packageRoot()
                .appendingPathComponent("scripts")
                .appendingPathComponent("validate-download-build-ref.sh")
                .path
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binDirectory.path):\(environment["PATH"] ?? "")"
        environment["GITHUB_REF_TYPE"] = refType
        environment["GITHUB_REF_NAME"] = refName
        environment["GITHUB_SHA"] = commit
        environment["GITHUB_REPOSITORY"] = "Lore-Hex/QuillCode"
        environment["RELEASE_POLICY_MAIN_COMMIT"] = mainCommit ?? commit
        environment["RELEASE_POLICY_TAG_COMMIT"] = tagCommit ?? commit
        environment["RELEASE_POLICY_IS_MAIN_ANCESTOR"] = isMainAncestor ? "true" : "false"
        environment["RELEASE_POLICY_SUCCESSFUL_CI_RUNS"] = String(successfulCIRuns)
        environment["RELEASE_POLICY_RELEASE_EXISTS"] = releaseExists ? "true" : "false"
        environment["RELEASE_POLICY_GH_LOG"] = ghLogURL.path
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let ghLog = (try? String(contentsOf: ghLogURL, encoding: .utf8)) ?? ""
        return PolicyResult(exitCode: process.terminationStatus, output: output, ghLog: ghLog)
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
            refs/remotes/origin/main*) printf '%s\n' "${RELEASE_POLICY_MAIN_COMMIT:?}" ;;
            refs/tags/*) printf '%s\n' "${RELEASE_POLICY_TAG_COMMIT:?}" ;;
            *) printf '%s\n' "${GITHUB_SHA:?}" ;;
          esac
          exit 0
        fi
        if [[ "$1" == "merge-base" && "$2" == "--is-ancestor" ]]; then
          [[ "${RELEASE_POLICY_IS_MAIN_ANCESTOR:?}" == "true" ]]
          exit
        fi
        echo "unexpected git invocation: $*" >&2
        exit 9
        """
    }

    private var fakeGH: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${RELEASE_POLICY_GH_LOG:?}"
        if [[ "$1" == "run" && "$2" == "list" ]]; then
          printf '%s\n' "${RELEASE_POLICY_SUCCESSFUL_CI_RUNS:?}"
          exit 0
        fi
        if [[ "$1" == "release" && "$2" == "view" ]]; then
          [[ "${RELEASE_POLICY_RELEASE_EXISTS:?}" == "true" ]]
          exit
        fi
        echo "unexpected gh invocation: $*" >&2
        exit 9
        """
    }
}
