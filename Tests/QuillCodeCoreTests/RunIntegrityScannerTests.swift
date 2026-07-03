import XCTest
@testable import QuillCodeCore

/// The heart of issue #875: a FIXTURE CORPUS of sneaky transcripts. Each fixture is a run whose
/// transcript could fool a human skimming it, and each asserts the exact badge the scanner must produce.
/// The bias is HIGH PRECISION — the "incidental pass" and "no tests, no claim" fixtures guard against
/// false yellows/reds, which are the failure mode the issue explicitly calls out.
final class RunIntegrityScannerTests: XCTestCase {

    // MARK: - Transcript builders (mirror the real event shapes from AgentToolStepRunner)

    /// Appends the queued -> running -> completed/failed event triple for a shell command, exactly as
    /// the agent records it (`toolQueued` carries the ToolCall, the result event carries the ToolResult).
    private func shell(
        _ cmd: String,
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        error: String? = nil
    ) -> [ThreadEvent] {
        let ok = exitCode == 0
        let call = ToolCall(name: RunIntegrityScanner.shellRunToolName, argumentsJSON: encodedArgs(cmd: cmd))
        let result = ToolResult(ok: ok, stdout: stdout, stderr: stderr, exitCode: exitCode, error: error)
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? "{}"
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        return [
            ThreadEvent(kind: .toolQueued, summary: "\(call.name) queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "\(call.name) running"),
            ThreadEvent(
                kind: ok ? .toolCompleted : .toolFailed,
                summary: "\(call.name) \(ok ? "completed" : "failed")",
                payloadJSON: resultJSON
            )
        ]
    }

    /// A test command that was queued and started but NEVER produced a result event (silently skipped /
    /// abandoned mid-flight).
    private func danglingShell(_ cmd: String) -> [ThreadEvent] {
        let call = ToolCall(name: RunIntegrityScanner.shellRunToolName, argumentsJSON: encodedArgs(cmd: cmd))
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? "{}"
        return [
            ThreadEvent(kind: .toolQueued, summary: "\(call.name) queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "\(call.name) running")
        ]
    }

    private func encodedArgs(cmd: String) -> String {
        let object = ["cmd": cmd]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func thread(
        assistantText: [String] = [],
        events: [ThreadEvent] = []
    ) -> ChatThread {
        let messages = assistantText.map { ChatMessage(role: .assistant, content: $0) }
        return ChatThread(messages: messages, events: events)
    }

    // MARK: - Fixture corpus

    /// 1. Clean verified run: tests ran and passed, and the model said so. -> VERIFIED
    func testCleanVerifiedRun() {
        let run = thread(
            assistantText: ["I ran the suite and all tests pass."],
            events: shell("swift test", exitCode: 0, stdout: "Executed 42 tests, with 0 failures")
        )
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .verified)
        XCTAssertTrue(report.reasons.contains { $0.rule == .backedSuccessClaim })
    }

    /// 2. Claimed "tests pass" but NO test command ever ran. -> UNVERIFIED (unbacked claim)
    func testClaimedPassWithNoTestToolCall() {
        let run = thread(
            assistantText: ["I made the change. All tests pass now."],
            events: [] // never actually ran a test
        )
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .unverified)
        XCTAssertEqual(report.reasons.first?.rule, .unbackedSuccessClaim)
    }

    /// 2b. Claim backed only by a NON-test command (e.g. `ls`) that happened to exit 0 is still
    /// unbacked — a green `ls` does not vouch for the tests. -> UNVERIFIED
    func testClaimBackedOnlyByNonTestCommandIsUnverified() {
        let run = thread(
            assistantText: ["Done — all tests pass."],
            events: shell("ls -la", exitCode: 0, stdout: "file.txt")
        )
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .unverified)
    }

    /// 3. A failing test that was never re-run. -> RED (standing failure)
    func testFailingTestNeverRerun() {
        let run = thread(
            assistantText: ["Pushed the fix."],
            events: shell("swift test", exitCode: 1, stdout: "Executed 42 tests, with 3 failures")
        )
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .red)
        XCTAssertEqual(report.reasons.first?.rule, .standingTestFailure)
    }

    /// 4. Failing then fixed and re-run green. -> VERIFIED (failureThenRerunGreen)
    func testFailingThenFixedAndRerunGreen() {
        var events = shell("swift test", exitCode: 1, stdout: "1 failed")
        events += shell("swift test", exitCode: 0, stdout: "Executed 42 tests, with 0 failures")
        let run = thread(assistantText: ["Fixed it; tests pass now."], events: events)
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .verified)
        XCTAssertTrue(report.reasons.contains { $0.rule == .backedSuccessClaim })
    }

    /// 5. A test that was started but silently skipped (no result event). -> UNVERIFIED (skippedTest)
    func testSilentlySkippedTest() {
        let run = thread(
            assistantText: ["Wrapping up."],
            events: danglingShell("pytest")
        )
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .unverified)
        XCTAssertEqual(report.reasons.first?.rule, .skippedTest)
    }

    /// 6. A nonzero exit that WAS re-run green (same command string). -> VERIFIED
    func testNonzeroExitThatWasRerunGreen() {
        var events = shell("make check", exitCode: 2, stderr: "boom")
        events += shell("make check", exitCode: 0, stdout: "OK")
        let run = thread(events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 7. PRECISION GUARD: text mentioning "pass" incidentally must NOT trip UNVERIFIED.
    func testIncidentalPassMentionDoesNotTripUnverified() {
        let run = thread(
            assistantText: [
                "I updated the function so it passes the auth token to the downstream service.",
                "The user can now pass a custom limit. This should pass review easily.",
            ],
            events: []
        )
        // No claim phrase, no failing test -> a benign VERIFIED, never a false yellow.
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 7b. PRECISION GUARD: a bare non-test shell failure (e.g. `grep` finding nothing) is normal
    /// control flow and must NOT redden the run.
    func testNonTestShellFailureIsNotRed() {
        let run = thread(
            assistantText: ["No matches found, moving on."],
            events: shell("grep -q MARKER src/", exitCode: 1)
        )
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 8. No tests, no claims — a pure read/refactor run. -> VERIFIED (nothing dishonest happened).
    func testBenignRunWithNoTestsAndNoClaims() {
        let run = thread(
            assistantText: ["Here's a summary of how the module is structured."],
            events: shell("cat README.md", exitCode: 0, stdout: "# Project")
        )
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 9. RED dominates a co-occurring success claim: a claim plus a standing test failure is still RED
    /// (the failure is the more serious, higher-precision signal).
    func testStandingFailureDominatesClaim() {
        // The model also claims success in the same run — but the failure stands, so it is RED.
        let run = thread(
            assistantText: ["All tests pass!"],
            events: shell("swift test", exitCode: 1, stdout: "2 failed")
        )
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .red)
    }

    /// 10. Cancellation payload ("Stopped by user") on a non-test command must not redden the run.
    func testUserStoppedNonTestCommandIsNotRed() {
        let call = ToolCall(name: RunIntegrityScanner.shellRunToolName, argumentsJSON: encodedArgs(cmd: "sleep 100"))
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? "{}"
        let run = thread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(kind: .toolFailed, summary: "failed", payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#)
        ])
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 11. TRUST HOLE GUARD: a failing suite followed by a DIFFERENT suite passing stays RED — an
    /// unrelated green run must NOT vouch for the failed one (only a same-scope re-run clears it).
    func testDifferentTestSuitePassingDoesNotClearFailure() {
        var events = shell("pytest tests/auth", exitCode: 1, stdout: "1 failed")
        events += shell("pytest tests/utils", exitCode: 0, stdout: "5 passed")
        let run = thread(events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .red)
    }

    /// 11b. The SAME suite re-run green DOES clear the standing failure (same scope key).
    func testSameTestSuiteRerunGreenClearsFailure() {
        var events = shell("pytest tests/auth", exitCode: 1, stdout: "1 failed")
        events += shell("pytest tests/auth -v", exitCode: 0, stdout: "5 passed")
        let run = thread(events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 12. Only the LAST failing test that stands matters: a green run followed by a later red is RED.
    func testGreenThenLaterRedIsRed() {
        var events = shell("swift test", exitCode: 0, stdout: "0 failures")
        events += shell("swift test", exitCode: 1, stdout: "1 failed")
        let run = thread(events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .red)
    }

    // MARK: - Fail-on-revert fixtures for the adversarial-review defects (#875)

    /// BLOCKER: a runner NAME buried in arguments (not command position) must not classify the command
    /// as a test. `grep -rn pytest .` exits 1 on no match on a genuinely-good run — must stay VERIFIED.
    func testRunnerNameInArgumentsIsNotATestCommand() {
        for cmd in ["grep -rn pytest .", "which pytest", "grep -q 'go test' Makefile", "echo swift test"] {
            let run = thread(events: shell(cmd, exitCode: 1))
            XCTAssertEqual(
                RunIntegrityScanner.scan(run).verdict, .verified,
                "‘\(cmd)’ (runner only in args) exiting nonzero must NOT be RED"
            )
            XCTAssertNil(TestCommandLexicon.classify(cmd), "‘\(cmd)’ must not classify as a test command")
        }
    }

    /// BLOCKER (positive side): the same runner in COMMAND position IS a test command.
    func testRunnerInCommandPositionIsATestCommand() {
        for cmd in [
            "pytest tests/", "cd foo && pytest -q", "FOO=1 sudo pytest", "npx jest --ci",
            "poetry run pytest",
            // A wrapper flag whose value slot is actually the real (short) program must not swallow it.
            "time -p go test", "nice -n 10 swift test", "env FOO=1 pytest",
        ] {
            XCTAssertNotNil(TestCommandLexicon.classify(cmd), "‘\(cmd)’ should classify as a test command")
        }
    }

    /// MAJOR: substring success-claim matches must not fire on incidental prose. "install green-tea-cli"
    /// contains "all green" as a raw substring but is NOT a claim -> stays VERIFIED.
    func testSubstringClaimInProseIsNotUnverified() {
        for prose in [
            "I ran install green-tea-cli to set up the toolchain.",
            "Added a small green badge to the header.",
            "The prechecks pass through to the validator now.",
            "This wall greenhouse layout renders fine.",
        ] {
            let run = thread(assistantText: [prose], events: [])
            XCTAssertEqual(
                RunIntegrityScanner.scan(run).verdict, .verified,
                "incidental prose ‘\(prose)’ must NOT read as a success claim"
            )
        }
    }

    /// MAJOR (recall): real test invocations that aren't the literal first token must be RECOGNIZED as
    /// backing a claim, so an honest run isn't flagged UNVERIFIED.
    func testUnusualButRealTestInvocationsBackAClaim() {
        let invocations = [
            "xcodebuild -scheme App test",
            "./scripts/test.sh",
            "bin/rails test",
            "make check",
            "npm run test:unit",
            "bundle exec rspec",
        ]
        for cmd in invocations {
            let run = thread(
                assistantText: ["Done — all tests pass."],
                events: shell(cmd, exitCode: 0, stdout: "ok")
            )
            XCTAssertEqual(
                RunIntegrityScanner.scan(run).verdict, .verified,
                "‘\(cmd)’ passing should back the claim (VERIFIED), not read as UNVERIFIED"
            )
        }
    }

    /// MINOR: a skipped test followed by a later UNRELATED completed command must stay UNVERIFIED — the
    /// unrelated command must not clear the pending skip.
    func testSkippedTestSurvivesLaterUnrelatedCommand() {
        var events = danglingShell("pytest tests/auth")
        events += shell("git status", exitCode: 0, stdout: "clean")
        events += shell("cat README.md", exitCode: 0, stdout: "# Project")
        let run = thread(events: events)
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .unverified)
        XCTAssertEqual(report.reasons.first?.rule, .skippedTest)
    }

    // MARK: - Fail-on-revert fixtures for the SECOND adversarial-review pass (#875)

    /// BLOCKER: a suite selected by an ATTACHED-VALUE flag must get a DISTINCT scope, so an unrelated
    /// green suite cannot clear a red one. Covers cargo `--test=`, jest `--testPathPattern=`, pytest
    /// `-k`, and separated forms.
    func testSelectorFlagSuitesGetDistinctScopes() {
        let cases: [(fail: String, pass: String)] = [
            ("cargo test --test=auth_it", "cargo test --test=utils_it"),
            ("cargo test --package=auth", "cargo test --package=utils"),
            ("jest --testPathPattern=auth", "jest --testPathPattern=utils"),
            ("jest --testNamePattern=auth", "jest --testNamePattern=utils"),
            ("vitest --testNamePattern=auth", "vitest --testNamePattern=utils"),
            ("pytest -kauth", "pytest -kutils"),
            ("pytest -k auth", "pytest -k utils"),
            ("pytest -k=auth", "pytest -k=utils"),
        ]
        for (fail, pass) in cases {
            var events = shell(fail, exitCode: 1, stdout: "1 failed")
            events += shell(pass, exitCode: 0, stdout: "5 passed")
            let run = thread(events: events)
            XCTAssertEqual(
                RunIntegrityScanner.scan(run).verdict, .red,
                "‘\(fail)’ failing then ‘\(pass)’ passing (different suites) must stay RED"
            )
        }
    }

    /// BLOCKER (positive side): the SAME selector-flagged suite re-run green DOES clear the failure.
    func testSameSelectorSuiteRerunGreenClears() {
        var events = shell("cargo test --test=auth_it", exitCode: 1, stdout: "1 failed")
        events += shell("cargo test --test=auth_it -- --nocapture", exitCode: 0, stdout: "ok")
        let run = thread(events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// MAJOR: `command -v pytest` (and `which`/`type`) is a PRESENCE PROBE — exit 1 means "not
    /// installed", never a test failure. Must stay VERIFIED and never classify as a test.
    func testPresenceProbeIsNotATest() {
        for cmd in ["command -v pytest", "command -V pytest", "which pytest", "type pytest", "hash pytest"] {
            let run = thread(events: shell(cmd, exitCode: 1))
            XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified, "‘\(cmd)’ exit-1 must stay VERIFIED")
            XCTAssertNil(TestCommandLexicon.classify(cmd), "‘\(cmd)’ must not classify as a test command")
        }
        // But actually RUNNING via `command pytest` IS a test.
        XCTAssertNotNil(TestCommandLexicon.classify("command pytest tests/"))
    }

    /// MAJOR (recall): `python -m pytest` / `python3 -m unittest` are standard test invocations where the
    /// runner is the module after `-m`, not argv[0]. A failing one must be RED.
    func testPythonModuleInvocationIsRecognized() {
        for cmd in ["python -m pytest", "python3 -m pytest tests/", "python -m unittest", "py -m pytest"] {
            XCTAssertNotNil(TestCommandLexicon.classify(cmd), "‘\(cmd)’ should classify as a test command")
        }
        let red = thread(events: shell("python -m pytest tests/auth", exitCode: 1, stdout: "1 failed"))
        XCTAssertEqual(RunIntegrityScanner.scan(red).verdict, .red)
        // `python -m http.server` (non-test module) must NOT classify.
        XCTAssertNil(TestCommandLexicon.classify("python -m http.server"))
        // python -m pytest suites are scope-distinct.
        var events = shell("python -m pytest tests/auth", exitCode: 1, stdout: "1 failed")
        events += shell("python -m pytest tests/utils", exitCode: 0, stdout: "ok")
        XCTAssertEqual(RunIntegrityScanner.scan(thread(events: events)).verdict, .red)
    }

    /// MAJOR: the segment splitter must be QUOTE-AWARE — an operator inside a quoted argument of a
    /// non-runner command must NOT be carved into a synthetic runner segment (which would false-RED).
    func testQuotedOperatorDoesNotInventATest() {
        for cmd in [
            #"echo "run && pytest tests""#,
            #"git commit -m "fix; pytest later""#,
            #"echo 'a | pytest b'"#,
            #"printf "swift test\n""#,
        ] {
            XCTAssertNil(TestCommandLexicon.classify(cmd), "‘\(cmd)’ (quoted runner) must NOT be a test command")
            let run = thread(events: shell(cmd, exitCode: 1))
            XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified, "‘\(cmd)’ exit-1 must stay VERIFIED")
        }
        // A REAL &&-chained test outside quotes still classifies.
        XCTAssertNotNil(TestCommandLexicon.classify("cd repo && pytest tests/"))
        // Unbalanced quotes: conservative — do not manufacture a test segment.
        XCTAssertNil(TestCommandLexicon.classify(#"echo "oops && pytest"#))
        // Backtick / command substitution containing an operator + runner must not split into a test.
        XCTAssertNil(TestCommandLexicon.classify("echo `pytest && true`"))
        XCTAssertNil(TestCommandLexicon.classify(#"echo "$(pytest || true)""#))
    }

    // MARK: - Robustness (must never crash, always deterministic)

    func testEmptyThreadIsVerified() {
        XCTAssertEqual(RunIntegrityScanner.scan(thread()).verdict, .verified)
    }

    func testMalformedPayloadsDoNotCrash() {
        let run = thread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: "not json {"),
            ThreadEvent(kind: .toolCompleted, summary: "completed", payloadJSON: nil),
            ThreadEvent(kind: .toolFailed, summary: "failed", payloadJSON: "]["),
            ThreadEvent(kind: .toolRunning, summary: "orphan running"),
            ThreadEvent(kind: .toolCompleted, summary: "orphan completed", payloadJSON: "{}")
        ])
        // Must not crash and must reach a decision.
        _ = RunIntegrityScanner.scan(run)
    }

    func testResultEventWithoutQueuedIsIgnored() {
        // A completed event with no preceding queued call (interleaved / truncated transcript) is simply
        // not treated as a command step.
        let run = thread(events: [
            ThreadEvent(kind: .toolCompleted, summary: "completed", payloadJSON: #"{"ok":true}"#)
        ])
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    func testHugeTranscriptStaysBounded() {
        // A pathological transcript of many steps + a giant message must still terminate quickly.
        var events: [ThreadEvent] = []
        for _ in 0..<200 { events += shell("echo hi", exitCode: 0) }
        let giant = String(repeating: "the code passes data around. ", count: 5_000)
        let run = thread(assistantText: [giant], events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    func testDeterministic() {
        let run = thread(
            assistantText: ["all tests pass"],
            events: shell("swift test", exitCode: 0, stdout: "0 failures")
        )
        let a = RunIntegrityScanner.scan(run)
        let b = RunIntegrityScanner.scan(run)
        XCTAssertEqual(a.verdict, b.verdict)
        XCTAssertEqual(a.reasons, b.reasons)
    }

    // MARK: - Persistence round-trip (verdict stable across a JSON reload)

    func testRecordAndReadBackVerdict() throws {
        var run = thread(
            assistantText: ["tests pass"],
            events: shell("swift test", exitCode: 0, stdout: "0 failures")
        )
        let recorded = RunIntegrityRecord.record(into: &run)
        XCTAssertEqual(recorded.verdict, .verified)

        // The verdict is now readable back off the thread's events...
        XCTAssertEqual(RunIntegrityRecord.latest(in: run)?.verdict, .verified)

        // ...and survives a full Codable round-trip of the thread (what JSONThreadStore does).
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(run)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(ChatThread.self, from: data)
        XCTAssertEqual(RunIntegrityRecord.latest(in: reloaded)?.verdict, .verified)
    }

    func testRecordCollapsesToASingleTrailingNotice() {
        var run = thread(events: shell("swift test", exitCode: 1, stdout: "1 failed"))
        RunIntegrityRecord.record(into: &run)
        RunIntegrityRecord.record(into: &run)
        let notices = run.events.filter { RunIntegrityRecord.isRecord($0) }
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(RunIntegrityRecord.latest(in: run)?.verdict, .red)
    }

    // MARK: - Lexicon precision

    func testTestCommandLexicon() {
        // Command-position runners / driver subcommands classify.
        for cmd in [
            "swift test", "cd foo && pytest -q tests/", "npm test", "cargo test --all",
            "go test ./...", "make check", "xcodebuild -scheme App test", "./scripts/test.sh",
            "bin/rails test", "npm run test:unit", "bundle exec rspec", "poetry run pytest",
        ] {
            XCTAssertTrue(TestCommandLexicon.looksLikeTestCommand(cmd), "‘\(cmd)’ should be a test command")
        }
        // NOT test commands: non-runners, runner only in args, non-test driver subcommands.
        for cmd in [
            "ls -la", "test -f foo", "run mypytesting_helper", "",
            "grep -rn pytest .", "which pytest", "grep -q 'go test' Makefile", "echo swift test",
            "go build ./...", "make build", "cargo build", "npm run lint",
            // test-looking token as a FILE arg, not the subcommand.
            "go run test.go", "make build test-data", "cargo run --bin test-harness",
        ] {
            XCTAssertFalse(TestCommandLexicon.looksLikeTestCommand(cmd), "‘\(cmd)’ should NOT be a test command")
        }
    }

    /// Scope keys distinguish suites (so a green util suite can't clear a red auth suite) but ignore
    /// flags (so a re-run with extra flags still matches).
    func testTestCommandScopeIdentity() {
        let auth = TestCommandLexicon.classify("pytest tests/auth")?.scope
        let authVerbose = TestCommandLexicon.classify("pytest tests/auth -v")?.scope
        let utils = TestCommandLexicon.classify("pytest tests/utils")?.scope
        XCTAssertEqual(auth, authVerbose)
        XCTAssertNotEqual(auth, utils)
    }

    func testSuccessClaimLexiconAnchoring() {
        XCTAssertNotNil(SuccessClaimLexicon.matchedClaim(in: "all tests pass"))
        XCTAssertNotNil(SuccessClaimLexicon.matchedClaim(in: "the suite is green — everything passes"))
        XCTAssertNotNil(SuccessClaimLexicon.matchedClaim(in: "all green now"))
        // Incidental verb "pass" must not match.
        XCTAssertNil(SuccessClaimLexicon.matchedClaim(in: "please pass the config to the builder"))
        XCTAssertNil(SuccessClaimLexicon.matchedClaim(in: ""))
        // Substring-inside-a-word must not match (word-boundary anchoring).
        XCTAssertNil(SuccessClaimLexicon.matchedClaim(in: "install green-tea-cli"))
        XCTAssertNil(SuccessClaimLexicon.matchedClaim(in: "a small green badge"))
        XCTAssertNil(SuccessClaimLexicon.matchedClaim(in: "prechecks pass through the validator"))
    }

    /// Guard: the Core-local shell tool name must match the real ToolDefinition (they live in different
    /// modules and are duplicated on purpose to keep Core dependency-free).
    func testShellToolNameParity() {
        XCTAssertEqual(RunIntegrityScanner.shellRunToolName, "host.shell.run")
    }
}
