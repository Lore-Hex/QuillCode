import XCTest

final class ParityDownloadBuildCIGateTests: QuillCodeParityTestCase {
    private let commit = String(repeating: "a", count: 40)

    func testWaitsForActiveExactRunAndAcceptsLaterSuccess() throws {
        let successfulURL = "https://github.com/Lore-Hex/QuillCode/actions/runs/13"
        let firstSnapshot = [
            row(id: 10, status: "completed", conclusion: "success", branch: "feature"),
            row(id: 11, status: "completed", conclusion: "success", event: "pull_request"),
            row(id: 12, status: "in_progress", conclusion: ""),
        ].joined(separator: "\n")
        let result = try runGate(responses: [
            firstSnapshot,
            row(id: 13, status: "completed", conclusion: "success", url: successfulURL),
        ])

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("1 matching CI run(s) are still active"), result.output)
        XCTAssertTrue(result.output.contains("Validated successful exact-main CI"), result.output)
        XCTAssertTrue(result.output.contains(successfulURL), result.output)
        XCTAssertEqual(result.ghLog.components(separatedBy: "run list").count - 1, 2)
        XCTAssertEqual(result.sleepLog.trimmingCharacters(in: .whitespacesAndNewlines), "1")
    }

    func testRejectsCompletedFailureAtBoundedDeadline() throws {
        let result = try runGate(
            responses: [row(id: 20, status: "completed", conclusion: "failure")],
            waitSeconds: "0"
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("1 matching CI run(s) completed without success"),
            result.output
        )
        XCTAssertTrue(result.output.contains("did not produce a successful exact-main CI run"))
        XCTAssertTrue(result.sleepLog.isEmpty)
    }

    func testRetriesTransientGitHubQueryFailure() throws {
        let result = try runGate(
            responses: [
                "",
                row(id: 21, status: "completed", conclusion: "success"),
            ],
            failingCalls: [1]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("GitHub CI query is temporarily unavailable"), result.output)
        XCTAssertTrue(result.output.contains("Validated successful exact-main CI"), result.output)
        XCTAssertEqual(result.ghLog.components(separatedBy: "run list").count - 1, 2)
        XCTAssertEqual(result.sleepLog.trimmingCharacters(in: .whitespacesAndNewlines), "1")
    }

    func testExtendsOnceWhenObservedExactRunIsStillActive() throws {
        let successfulURL = "https://github.com/Lore-Hex/QuillCode/actions/runs/23"
        let result = try runGate(
            responses: [
                row(id: 22, status: "in_progress", conclusion: ""),
                row(id: 23, status: "completed", conclusion: "success", url: successfulURL),
            ],
            waitSeconds: "0",
            activeGraceSeconds: "2"
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Extending exact-main CI wait once by up to 2s"),
            result.output
        )
        XCTAssertTrue(result.output.contains(successfulURL), result.output)
        XCTAssertEqual(result.ghLog.components(separatedBy: "run list").count - 1, 2)
        XCTAssertEqual(result.sleepLog.trimmingCharacters(in: .whitespacesAndNewlines), "1")
    }

    func testObservedActiveRunGraceSurvivesTransientQueryFailure() throws {
        let result = try runGate(
            responses: [
                row(id: 24, status: "in_progress", conclusion: ""),
                "",
                row(id: 25, status: "completed", conclusion: "success"),
            ],
            waitSeconds: "0",
            activeGraceSeconds: "2",
            failingCalls: [2]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("temporarily unavailable"), result.output)
        XCTAssertEqual(
            result.output.components(separatedBy: "Extending exact-main CI wait once").count - 1,
            1,
            result.output
        )
        XCTAssertEqual(result.ghLog.components(separatedBy: "run list").count - 1, 3)
    }

    func testActiveRunGraceExpiresAtCombinedBound() throws {
        let result = try runGate(
            responses: [row(id: 26, status: "in_progress", conclusion: "")],
            waitSeconds: "2",
            activeGraceSeconds: "1",
            useRealSleep: true
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("matching CI run(s) are still active"), result.output)
        XCTAssertTrue(result.output.contains("within 3s"), result.output)
        XCTAssertLessThanOrEqual(
            result.output.components(separatedBy: "Extending exact-main CI wait once").count - 1,
            1,
            result.output
        )
    }

    func testSlowQueryCannotMoveCombinedDeadline() throws {
        let result = try runGate(
            responses: [row(id: 27, status: "in_progress", conclusion: "")],
            waitSeconds: "0",
            activeGraceSeconds: "1",
            delayedCalls: [1: 2],
            useRealSleep: true
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("within 1s"), result.output)
        XCTAssertFalse(result.output.contains("Extending exact-main CI wait"), result.output)
        XCTAssertEqual(result.ghLog.components(separatedBy: "run list").count - 1, 1)
    }

    func testDoesNotExtendMissingOrTerminalCI() throws {
        let missing = try runGate(
            responses: [""],
            waitSeconds: "0",
            activeGraceSeconds: "2"
        )
        let terminal = try runGate(
            responses: [row(id: 27, status: "completed", conclusion: "failure")],
            waitSeconds: "0",
            activeGraceSeconds: "2"
        )

        XCTAssertEqual(missing.exitCode, 2, missing.output)
        XCTAssertEqual(terminal.exitCode, 2, terminal.output)
        XCTAssertFalse(missing.output.contains("Extending exact-main CI wait"), missing.output)
        XCTAssertFalse(terminal.output.contains("Extending exact-main CI wait"), terminal.output)
        XCTAssertTrue(missing.output.contains("within 0s"), missing.output)
        XCTAssertTrue(terminal.output.contains("within 0s"), terminal.output)
    }

    func testRejectsPullRequestAndMismatchedRuns() throws {
        let result = try runGate(responses: [[
            row(id: 30, status: "completed", conclusion: "success", branch: "feature"),
            row(id: 31, status: "completed", conclusion: "success", event: "pull_request"),
            row(
                id: 32,
                status: "completed",
                conclusion: "success",
                sha: String(repeating: "b", count: 40)
            ),
        ].joined(separator: "\n")], waitSeconds: "0")

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("no matching main-branch CI run exists yet"), result.output)
    }

    func testRejectsInvalidBoundsBeforeQueryingGitHub() throws {
        let excessiveWait = try runGate(responses: [""], waitSeconds: "3601")
        let excessiveGrace = try runGate(responses: [""], activeGraceSeconds: "3601")
        let excessiveCombined = try runGate(
            responses: [""],
            waitSeconds: "1801",
            activeGraceSeconds: "1800"
        )
        let zeroPoll = try runGate(responses: [""], waitSeconds: "0", pollSeconds: "0")

        XCTAssertEqual(excessiveWait.exitCode, 2, excessiveWait.output)
        XCTAssertTrue(excessiveWait.output.contains("must not exceed 3600"), excessiveWait.output)
        XCTAssertTrue(excessiveWait.ghLog.isEmpty)
        XCTAssertEqual(excessiveGrace.exitCode, 2, excessiveGrace.output)
        XCTAssertTrue(excessiveGrace.output.contains("must not exceed 3600"), excessiveGrace.output)
        XCTAssertTrue(excessiveGrace.ghLog.isEmpty)
        XCTAssertEqual(excessiveCombined.exitCode, 2, excessiveCombined.output)
        XCTAssertTrue(
            excessiveCombined.output.contains("combined exact-main CI wait"),
            excessiveCombined.output
        )
        XCTAssertTrue(excessiveCombined.ghLog.isEmpty)
        XCTAssertEqual(zeroPoll.exitCode, 2, zeroPoll.output)
        XCTAssertTrue(zeroPoll.output.contains("must be a positive integer"), zeroPoll.output)
        XCTAssertTrue(zeroPoll.ghLog.isEmpty)
    }

    func testWorkflowBudgetsOneHourForAnObservedActiveRun() throws {
        let workflow = try Self.workflowText(named: "download-builds.yml")
        let scriptURL = Self.packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("wait-for-successful-ci.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        Self.assertSource(workflow, containsAll: [
            "timeout-minutes: 65",
            "DOWNLOAD_BUILD_CI_WAIT_SECONDS: \"1800\"",
            "DOWNLOAD_BUILD_CI_ACTIVE_GRACE_SECONDS: \"1800\"",
        ])
        Self.assertSource(script, containsAll: [
            "DOWNLOAD_BUILD_CI_WAIT_SECONDS:-1800",
            "DOWNLOAD_BUILD_CI_ACTIVE_GRACE_SECONDS:-1800",
            "combined exact-main CI wait and active grace must not exceed 3600 seconds",
            "Extending exact-main CI wait once",
        ])
    }

    private struct GateResult {
        var exitCode: Int32
        var output: String
        var ghLog: String
        var sleepLog: String
    }

    private func runGate(
        responses: [String],
        waitSeconds: String = "3",
        activeGraceSeconds: String = "0",
        pollSeconds: String = "1",
        failingCalls: Set<Int> = [],
        delayedCalls: [Int: Int] = [:],
        useRealSleep: Bool = false
    ) throws -> GateResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-download-ci-gate-tests")
            .appendingPathComponent(UUID().uuidString)
        let binDirectory = temporaryDirectory.appendingPathComponent("bin")
        let responsesDirectory = temporaryDirectory.appendingPathComponent("responses")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: responsesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        for (index, response) in responses.enumerated() {
            try response.write(
                to: responsesDirectory.appendingPathComponent("\(index + 1).txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        for call in failingCalls {
            try Data().write(to: responsesDirectory.appendingPathComponent("\(call).fail"))
        }
        for (call, delay) in delayedCalls {
            try "\(delay)\n".write(
                to: responsesDirectory.appendingPathComponent("\(call).delay"),
                atomically: true,
                encoding: .utf8
            )
        }

        let ghURL = binDirectory.appendingPathComponent("gh")
        let sleepURL = binDirectory.appendingPathComponent("sleep")
        let ghLogURL = temporaryDirectory.appendingPathComponent("gh.log")
        let sleepLogURL = temporaryDirectory.appendingPathComponent("sleep.log")
        let callCountURL = temporaryDirectory.appendingPathComponent("calls.txt")
        try fakeGH.write(to: ghURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ghURL.path)
        if !useRealSleep {
            try fakeSleep.write(to: sleepURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sleepURL.path)
        }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.packageRoot()
                .appendingPathComponent("scripts")
                .appendingPathComponent("wait-for-successful-ci.sh")
                .path
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binDirectory.path):\(environment["PATH"] ?? "")"
        environment["GITHUB_REPOSITORY"] = "Lore-Hex/QuillCode"
        environment["GITHUB_SHA"] = commit
        environment["DOWNLOAD_BUILD_CI_WAIT_SECONDS"] = waitSeconds
        environment["DOWNLOAD_BUILD_CI_ACTIVE_GRACE_SECONDS"] = activeGraceSeconds
        environment["DOWNLOAD_BUILD_CI_POLL_SECONDS"] = pollSeconds
        environment["CI_GATE_RESPONSES_DIR"] = responsesDirectory.path
        environment["CI_GATE_RESPONSE_COUNT"] = String(responses.count)
        environment["CI_GATE_CALL_COUNT_FILE"] = callCountURL.path
        environment["CI_GATE_GH_LOG"] = ghLogURL.path
        environment["CI_GATE_SLEEP_LOG"] = sleepLogURL.path
        environment.removeValue(forKey: "GITHUB_OUTPUT")
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        return GateResult(
            exitCode: process.terminationStatus,
            output: String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            ghLog: (try? String(contentsOf: ghLogURL, encoding: .utf8)) ?? "",
            sleepLog: (try? String(contentsOf: sleepLogURL, encoding: .utf8)) ?? ""
        )
    }

    private func row(
        id: Int,
        status: String,
        conclusion: String,
        sha: String? = nil,
        branch: String = "main",
        event: String = "workflow_dispatch",
        url: String? = nil
    ) -> String {
        [
            String(id),
            status,
            conclusion,
            sha ?? commit,
            branch,
            event,
            url ?? "https://github.com/Lore-Hex/QuillCode/actions/runs/\(id)",
        ].joined(separator: "\u{1F}")
    }

    private var fakeGH: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${CI_GATE_GH_LOG:?}"
        if [[ "$1" != "run" || "$2" != "list" ]]; then
          echo "unexpected gh invocation: $*" >&2
          exit 9
        fi
        count=0
        if [[ -f "${CI_GATE_CALL_COUNT_FILE:?}" ]]; then
          read -r count < "$CI_GATE_CALL_COUNT_FILE"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$CI_GATE_CALL_COUNT_FILE"
        response_index="$count"
        if (( response_index > CI_GATE_RESPONSE_COUNT )); then
          response_index="$CI_GATE_RESPONSE_COUNT"
        fi
        delay_file="${CI_GATE_RESPONSES_DIR:?}/${count}.delay"
        if [[ -f "$delay_file" ]]; then
          read -r delay_seconds < "$delay_file"
          /bin/sleep "$delay_seconds"
        fi
        if [[ -f "${CI_GATE_RESPONSES_DIR:?}/${response_index}.fail" ]]; then
          exit 1
        fi
        cat "${CI_GATE_RESPONSES_DIR:?}/${response_index}.txt"
        """
    }

    private var fakeSleep: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${CI_GATE_SLEEP_LOG:?}"
        """
    }
}
