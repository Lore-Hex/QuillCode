import XCTest

final class ParityStableReleaseStartGateTests: QuillCodeParityTestCase {
    func testCheckOnlyPassesWithoutCreatingATag() throws {
        let result = try runStarter(arguments: ["--check-only", "v1.2.3"])

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Stable release preflight passed."))
        XCTAssertTrue(result.output.contains("Apple distribution secret names: 7/7"))
        XCTAssertFalse(result.gitLog.contains("tag -a"), result.gitLog)
        XCTAssertFalse(result.gitLog.contains("push origin refs/tags/v1.2.3"), result.gitLog)
        XCTAssertTrue(
            result.ghLog.contains("run list --repo Lore-Hex/QuillCode --workflow ci.yml --commit \(Self.commitA)"),
            result.ghLog
        )
        XCTAssertTrue(
            result.ghLog.contains("secret list --repo Lore-Hex/QuillCode --app actions --json name"),
            result.ghLog
        )
    }

    func testPublishCreatesAndPushesOneAnnotatedExactCommitTag() throws {
        let result = try runStarter(arguments: ["v1.2.3"])

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(
            result.gitLog.contains(
                "tag -a v1.2.3 -m Quill Cowork 1.2.3 \(Self.commitA)"
            ),
            result.gitLog
        )
        XCTAssertTrue(
            result.gitLog.contains("push origin refs/tags/v1.2.3:refs/tags/v1.2.3"),
            result.gitLog
        )
        XCTAssertFalse(result.gitLog.contains("--force"), result.gitLog)
    }

    func testPreflightRejectsDirtyStaleAndUntestedMainBeforeMutation() throws {
        let dirty = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_DIRTY": "true"]
        )
        let stale = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_MAIN_COMMIT": Self.commitB]
        )
        let untested = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_TESTER_COMMIT": Self.commitB]
        )

        XCTAssertEqual(dirty.exitCode, 2, dirty.output)
        XCTAssertTrue(dirty.output.contains("clean worktree"), dirty.output)
        XCTAssertEqual(stale.exitCode, 2, stale.output)
        XCTAssertTrue(stale.output.contains("not exact origin/main"), stale.output)
        XCTAssertEqual(untested.exitCode, 2, untested.output)
        XCTAssertTrue(untested.output.contains("tester-latest"), untested.output)
        for result in [dirty, stale, untested] {
            XCTAssertFalse(result.gitLog.contains("tag -a"), result.gitLog)
        }
    }

    func testPreflightRejectsMissingCISecretAndWrongRemoteBeforeMutation() throws {
        let missingCI = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_CI_URL": ""]
        )
        let missingSecret = try runStarter(
            arguments: ["v1.2.3"],
            overrides: [
                "STABLE_RELEASE_SECRET_NAMES": Self.requiredSecrets
                    .filter { $0 != "APPLE_TEAM_ID" }
                    .joined(separator: "\n")
            ]
        )
        let wrongRemote = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_REMOTE_URL": "git@github.com:Elsewhere/Other.git"]
        )

        XCTAssertEqual(missingCI.exitCode, 2, missingCI.output)
        XCTAssertTrue(missingCI.output.contains("successful exact-commit CI"), missingCI.output)
        XCTAssertEqual(missingSecret.exitCode, 2, missingSecret.output)
        XCTAssertTrue(missingSecret.output.contains("APPLE_TEAM_ID"), missingSecret.output)
        XCTAssertEqual(wrongRemote.exitCode, 2, wrongRemote.output)
        XCTAssertTrue(wrongRemote.output.contains("does not point to"), wrongRemote.output)
        for result in [missingCI, missingSecret, wrongRemote] {
            XCTAssertFalse(result.gitLog.contains("tag -a"), result.gitLog)
        }
    }

    func testPreflightRejectsMalformedNonMonotonicAndExistingReleases() throws {
        let malformed = try runStarter(arguments: ["v1.2"])
        let nonMonotonic = try runStarter(arguments: ["v1.2.1"])
        let remoteTag = try runStarter(
            arguments: ["v1.2.3"],
            overrides: [
                "STABLE_RELEASE_REMOTE_VERSION_TAGS":
                    "\(Self.commitB)\trefs/tags/v1.2.3"
            ]
        )
        let existingRelease = try runStarter(
            arguments: ["v1.2.3"],
            overrides: [
                "STABLE_RELEASE_ROWS": "tester-latest\ttrue\nv1.2.3\tfalse"
            ]
        )

        XCTAssertEqual(malformed.exitCode, 2, malformed.output)
        XCTAssertTrue(malformed.output.contains("canonical vMAJOR.MINOR.PATCH"), malformed.output)
        XCTAssertEqual(nonMonotonic.exitCode, 2, nonMonotonic.output)
        XCTAssertTrue(nonMonotonic.output.contains("must be newer"), nonMonotonic.output)
        XCTAssertEqual(remoteTag.exitCode, 2, remoteTag.output)
        XCTAssertTrue(remoteTag.output.contains("will not be moved"), remoteTag.output)
        XCTAssertEqual(existingRelease.exitCode, 2, existingRelease.output)
        XCTAssertTrue(existingRelease.output.contains("already exists and is immutable"), existingRelease.output)
    }

    func testPreflightRejectsWrongBranchLocalTagPrivateRepoAndMissingTesterRelease() throws {
        let wrongBranch = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_BRANCH": "feature"]
        )
        let localTag = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_LOCAL_TAG_EXISTS": "true"]
        )
        let privateRepository = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_VISIBILITY": "PRIVATE"]
        )
        let missingTesterRelease = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_ROWS": ""]
        )

        XCTAssertEqual(wrongBranch.exitCode, 2, wrongBranch.output)
        XCTAssertTrue(wrongBranch.output.contains("must start from the main branch"), wrongBranch.output)
        XCTAssertEqual(localTag.exitCode, 2, localTag.output)
        XCTAssertTrue(localTag.output.contains("Local tag v1.2.3 already exists"), localTag.output)
        XCTAssertEqual(privateRepository.exitCode, 2, privateRepository.output)
        XCTAssertTrue(privateRepository.output.contains("repository to be public"), privateRepository.output)
        XCTAssertEqual(missingTesterRelease.exitCode, 2, missingTesterRelease.output)
        XCTAssertTrue(missingTesterRelease.output.contains("tester-latest prerelease is missing"), missingTesterRelease.output)
        for result in [wrongBranch, localTag, privateRepository, missingTesterRelease] {
            XCTAssertFalse(result.gitLog.contains("tag -a"), result.gitLog)
        }
    }

    func testFailedPushRemovesOnlyTheNewLocalTag() throws {
        let result = try runStarter(
            arguments: ["v1.2.3"],
            overrides: ["STABLE_RELEASE_PUSH_SUCCEEDS": "false"]
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.gitLog.contains("tag -a v1.2.3"), result.gitLog)
        XCTAssertTrue(result.gitLog.contains("tag -d v1.2.3"), result.gitLog)
        XCTAssertTrue(result.output.contains("newly created local tag was removed"), result.output)
    }

    private struct StarterResult {
        var exitCode: Int32
        var output: String
        var gitLog: String
        var ghLog: String
    }

    private func runStarter(
        arguments: [String],
        overrides: [String: String] = [:]
    ) throws -> StarterResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-stable-release-start-tests")
            .appendingPathComponent(UUID().uuidString)
        let binDirectory = temporaryDirectory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let gitURL = binDirectory.appendingPathComponent("git")
        let ghURL = binDirectory.appendingPathComponent("gh")
        let gitLogURL = temporaryDirectory.appendingPathComponent("git.log")
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
                .appendingPathComponent("start-stable-release.sh")
                .path
        ] + arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binDirectory.path):\(environment["PATH"] ?? "")"
        environment["STABLE_RELEASE_GIT_LOG"] = gitLogURL.path
        environment["STABLE_RELEASE_GH_LOG"] = ghLogURL.path
        environment["STABLE_RELEASE_BRANCH"] = "main"
        environment["STABLE_RELEASE_DIRTY"] = "false"
        environment["STABLE_RELEASE_HEAD_COMMIT"] = Self.commitA
        environment["STABLE_RELEASE_MAIN_COMMIT"] = Self.commitA
        environment["STABLE_RELEASE_TESTER_COMMIT"] = Self.commitA
        environment["STABLE_RELEASE_REMOTE_URL"] = "git@github.com:Lore-Hex/QuillCode.git"
        environment["STABLE_RELEASE_REMOTE_VERSION_TAGS"] =
            "\(Self.commitB)\trefs/tags/v1.2.2"
        environment["STABLE_RELEASE_LOCAL_TAG_EXISTS"] = "false"
        environment["STABLE_RELEASE_VISIBILITY"] = "PUBLIC"
        environment["STABLE_RELEASE_ROWS"] = "tester-latest\ttrue"
        environment["STABLE_RELEASE_CI_URL"] =
            "https://github.com/Lore-Hex/QuillCode/actions/runs/1"
        environment["STABLE_RELEASE_SECRET_NAMES"] = Self.requiredSecrets.joined(separator: "\n")
        environment["STABLE_RELEASE_PUSH_SUCCEEDS"] = "true"
        for (key, value) in overrides {
            environment[key] = value
        }
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let gitLog = (try? String(contentsOf: gitLogURL, encoding: .utf8)) ?? ""
        let ghLog = (try? String(contentsOf: ghLogURL, encoding: .utf8)) ?? ""
        return StarterResult(
            exitCode: process.terminationStatus,
            output: output,
            gitLog: gitLog,
            ghLog: ghLog
        )
    }

    private var fakeGit: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${STABLE_RELEASE_GIT_LOG:?}"
        case "$1" in
          remote)
            [[ "$2" == "get-url" ]]
            printf '%s\n' "${STABLE_RELEASE_REMOTE_URL:?}"
            ;;
          symbolic-ref)
            printf '%s\n' "${STABLE_RELEASE_BRANCH:-}"
            ;;
          status)
            if [[ "${STABLE_RELEASE_DIRTY:?}" == "true" ]]; then
              printf '%s\n' ' M README.md'
            fi
            ;;
          fetch)
            ;;
          rev-parse)
            case "$3" in
              HEAD*) printf '%s\n' "${STABLE_RELEASE_HEAD_COMMIT:?}" ;;
              refs/remotes/*) printf '%s\n' "${STABLE_RELEASE_MAIN_COMMIT:?}" ;;
              *) exit 9 ;;
            esac
            ;;
          show-ref)
            [[ "${STABLE_RELEASE_LOCAL_TAG_EXISTS:?}" == "true" ]]
            ;;
          ls-remote)
            if [[ "$*" == *"refs/tags/tester-latest"* ]]; then
              printf '%s\trefs/tags/tester-latest\n' "${STABLE_RELEASE_TESTER_COMMIT:?}"
            else
              printf '%s\n' "${STABLE_RELEASE_REMOTE_VERSION_TAGS:-}"
            fi
            ;;
          tag)
            ;;
          push)
            [[ "${STABLE_RELEASE_PUSH_SUCCEEDS:?}" == "true" ]]
            ;;
          *)
            echo "unexpected git invocation: $*" >&2
            exit 9
            ;;
        esac
        """
    }

    private var fakeGH: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${STABLE_RELEASE_GH_LOG:?}"
        if [[ "$1" == "repo" && "$2" == "view" ]]; then
          printf '%s\n' "${STABLE_RELEASE_VISIBILITY:?}"
          exit 0
        fi
        if [[ "$1" == "release" && "$2" == "list" ]]; then
          printf '%s\n' "${STABLE_RELEASE_ROWS:-}"
          exit 0
        fi
        if [[ "$1" == "run" && "$2" == "list" ]]; then
          printf '%s\n' "${STABLE_RELEASE_CI_URL:-}"
          exit 0
        fi
        if [[ "$1" == "secret" && "$2" == "list" ]]; then
          printf '%s\n' "${STABLE_RELEASE_SECRET_NAMES:-}"
          exit 0
        fi
        echo "unexpected gh invocation: $*" >&2
        exit 9
        """
    }

    private static let commitA = String(repeating: "a", count: 40)
    private static let commitB = String(repeating: "b", count: 40)
    private static let requiredSecrets = [
        "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64",
        "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD",
        "APPLE_DEVELOPER_ID_APPLICATION_IDENTITY",
        "APPLE_TEAM_ID",
        "APPLE_NOTARY_KEY_ID",
        "APPLE_NOTARY_ISSUER_ID",
        "APPLE_NOTARY_PRIVATE_KEY_BASE64"
    ]
}
