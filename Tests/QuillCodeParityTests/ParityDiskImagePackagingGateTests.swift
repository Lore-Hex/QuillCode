import XCTest

final class ParityDiskImagePackagingGateTests: QuillCodeParityTestCase {
    func testRetriesEachTransientImageOperationAndPublishesOnlyVerifiedCandidate() throws {
        for stage in ["create", "verify", "attach"] {
            var overrides = [failureKey(for: stage): "1"]
            if stage == "attach" {
                overrides["FAKE_ATTACH_PARTIAL_MOUNT"] = "true"
            }
            let result = try runPackager(overrides: overrides)

            XCTAssertEqual(result.exitCode, 0, "\(stage): \(result.output)")
            XCTAssertEqual(result.publishedBytes, Data("candidate-2".utf8), result.output)
            XCTAssertTrue(
                result.output.contains("Disk-image \(stage) failed on attempt 1/3"),
                result.output
            )
            XCTAssertTrue(
                result.output.contains("Retrying disk-image packaging after transient \(stage) failure"),
                result.output
            )
            XCTAssertTrue(result.output.contains("Disk image ready after 2 attempt(s)"), result.output)
            XCTAssertEqual(result.operationCount(stage), 2, result.operationLog)
            XCTAssertEqual(result.sleepCount, 1, result.sleepLog)
            if stage == "attach" {
                XCTAssertTrue(result.operationLog.contains("detach -force"), result.operationLog)
            }
        }
    }

    func testExhaustedRetriesKeepExistingOutputAndNameTheLastStage() throws {
        let result = try runPackager(
            existingOutput: Data("last-good-image".utf8),
            overrides: [failureKey(for: "create"): "3"]
        )

        XCTAssertEqual(result.exitCode, 1, result.output)
        XCTAssertEqual(result.publishedBytes, Data("last-good-image".utf8))
        XCTAssertEqual(result.operationCount("create"), 3, result.operationLog)
        XCTAssertEqual(result.sleepCount, 2, result.sleepLog)
        XCTAssertTrue(
            result.output.contains("failed after 3 attempts; last failed stage: create"),
            result.output
        )
    }

    func testInvalidMountedSignatureFailsWithoutRetryOrPublication() throws {
        let result = try runPackager(overrides: ["FAKE_CODESIGN_FAIL": "true"])

        XCTAssertEqual(result.exitCode, 1, result.output)
        XCTAssertNil(result.publishedBytes)
        XCTAssertEqual(result.operationCount("create"), 1, result.operationLog)
        XCTAssertEqual(result.operationCount("verify"), 1, result.operationLog)
        XCTAssertEqual(result.operationCount("attach"), 1, result.operationLog)
        XCTAssertEqual(result.codesignCount, 1, result.codesignLog)
        XCTAssertEqual(result.sleepCount, 0, result.sleepLog)
        XCTAssertTrue(result.output.contains("invalid code signature; refusing to retry"), result.output)
    }

    func testRejectsInvalidRetryPolicyBeforeDiskImageWork() throws {
        let result = try runPackager(overrides: ["QUILLCODE_DISK_IMAGE_MAX_ATTEMPTS": "6"])

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertNil(result.publishedBytes)
        XCTAssertTrue(result.operationLog.isEmpty, result.operationLog)
        XCTAssertTrue(result.output.contains("must be an integer from 1 through 5"), result.output)
    }

    private struct PackagingResult {
        var exitCode: Int32
        var output: String
        var publishedBytes: Data?
        var operationLog: String
        var codesignLog: String
        var sleepLog: String

        func operationCount(_ operation: String) -> Int {
            operationLog
                .split(separator: "\n")
                .filter { $0.split(separator: " ").first == Substring(operation) }
                .count
        }

        var codesignCount: Int {
            codesignLog.split(separator: "\n").count
        }

        var sleepCount: Int {
            sleepLog.split(separator: "\n").count
        }
    }

    private func runPackager(
        existingOutput: Data? = nil,
        overrides: [String: String] = [:]
    ) throws -> PackagingResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-disk-image-packaging-tests")
            .appendingPathComponent(UUID().uuidString)
        let binDirectory = temporaryDirectory.appendingPathComponent("bin")
        let appURL = temporaryDirectory.appendingPathComponent("Quill Cowork.app")
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/Quill Cowork")
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let outputURL = temporaryDirectory.appendingPathComponent("downloads/Quill-Cowork.dmg")
        let operationLogURL = temporaryDirectory.appendingPathComponent("hdiutil.log")
        let stateDirectory = temporaryDirectory.appendingPathComponent("hdiutil-state")
        let codesignLogURL = temporaryDirectory.appendingPathComponent("codesign.log")
        let sleepLogURL = temporaryDirectory.appendingPathComponent("sleep.log")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try Data("plist-fixture".utf8).write(to: infoPlistURL)
        if let existingOutput {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try existingOutput.write(to: outputURL)
        }

        let tools = [
            "hdiutil": fakeHDIUtil,
            "ditto": fakeDitto,
            "codesign": fakeCodesign,
            "PlistBuddy": fakePlistBuddy,
            "sleep": fakeSleep,
        ]
        for (name, contents) in tools {
            let url = binDirectory.appendingPathComponent(name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.packageRoot()
                .appendingPathComponent("scripts/create-macos-disk-image.sh")
                .path,
            "--app", appURL.path,
            "--output", outputURL.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binDirectory.path):\(environment["PATH"] ?? "")"
        environment["QUILLCODE_DISK_IMAGE_PLATFORM"] = "Darwin"
        environment["QUILLCODE_HDIUTIL_BIN"] = binDirectory.appendingPathComponent("hdiutil").path
        environment["QUILLCODE_DITTO_BIN"] = binDirectory.appendingPathComponent("ditto").path
        environment["QUILLCODE_CODESIGN_BIN"] = binDirectory.appendingPathComponent("codesign").path
        environment["QUILLCODE_PLIST_BUDDY_BIN"] = binDirectory.appendingPathComponent("PlistBuddy").path
        environment["QUILLCODE_DISK_IMAGE_RETRY_DELAY_SECONDS"] = "0"
        environment["FAKE_DISK_IMAGE_APP"] = appURL.path
        environment["FAKE_HDIUTIL_LOG"] = operationLogURL.path
        environment["FAKE_HDIUTIL_STATE"] = stateDirectory.path
        environment["FAKE_CODESIGN_LOG"] = codesignLogURL.path
        environment["FAKE_SLEEP_LOG"] = sleepLogURL.path
        for (key, value) in overrides {
            environment[key] = value
        }
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        return PackagingResult(
            exitCode: process.terminationStatus,
            output: String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            publishedBytes: try? Data(contentsOf: outputURL),
            operationLog: (try? String(contentsOf: operationLogURL, encoding: .utf8)) ?? "",
            codesignLog: (try? String(contentsOf: codesignLogURL, encoding: .utf8)) ?? "",
            sleepLog: (try? String(contentsOf: sleepLogURL, encoding: .utf8)) ?? ""
        )
    }

    private func failureKey(for stage: String) -> String {
        switch stage {
        case "create": "FAKE_CREATE_FAILURES"
        case "verify": "FAKE_VERIFY_FAILURES"
        case "attach": "FAKE_ATTACH_FAILURES"
        default: preconditionFailure("Unsupported fake disk-image stage: \(stage)")
        }
    }

    private var fakeHDIUtil: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        operation="$1"
        shift
        printf '%s %s\n' "$operation" "$*" >> "${FAKE_HDIUTIL_LOG:?}"
        count_file="${FAKE_HDIUTIL_STATE:?}/$operation"
        count=0
        if [[ -f "$count_file" ]]; then
          read -r count < "$count_file"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$count_file"

        failure_limit=0
        case "$operation" in
          create) failure_limit="${FAKE_CREATE_FAILURES:-0}" ;;
          verify) failure_limit="${FAKE_VERIFY_FAILURES:-0}" ;;
          attach) failure_limit="${FAKE_ATTACH_FAILURES:-0}" ;;
        esac
        if (( count <= failure_limit )); then
          if [[ "$operation" == "attach" && "${FAKE_ATTACH_PARTIAL_MOUNT:-false}" == "true" ]]; then
            mount_point=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "-mountpoint" ]]; then
                mount_point="$2"
                break
              fi
              shift
            done
            touch "$mount_point/partial-mount"
          fi
          echo "simulated $operation failure" >&2
          exit 17
        fi

        case "$operation" in
          create)
            candidate=""
            for argument in "$@"; do
              candidate="$argument"
            done
            printf 'candidate-%s' "$count" > "$candidate"
            ;;
          verify)
            [[ -s "$1" ]]
            ;;
          attach)
            mount_point=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "-mountpoint" ]]; then
                mount_point="$2"
                break
              fi
              shift
            done
            [[ -n "$mount_point" ]]
            cp -R "${FAKE_DISK_IMAGE_APP:?}" "$mount_point/Quill Cowork.app"
            ln -s /Applications "$mount_point/Applications"
            ;;
          detach)
            ;;
          *)
            echo "unexpected hdiutil operation: $operation" >&2
            exit 19
            ;;
        esac
        """
    }

    private var fakeDitto: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        cp -R "$1" "$2"
        """
    }

    private var fakeCodesign: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${FAKE_CODESIGN_LOG:?}"
        [[ "${FAKE_CODESIGN_FAIL:-false}" != "true" ]]
        """
    }

    private var fakePlistBuddy: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' 'Quill Cowork'
        """
    }

    private var fakeSleep: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${FAKE_SLEEP_LOG:?}"
        """
    }
}
