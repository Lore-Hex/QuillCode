import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

final class SafetyDownloadPolicyTests: SafetyPolicyTestCase {
    private let linkedinRequest = "Can you download LinkedIn.com?"

    func testAutoApprovesExplicitFileDownloadShellRun() async {
        await assertApproves(
            command: "mkdir -p downloads && " +
                "curl -L --fail --silent --show-error " +
                "--output 'downloads/linkedin.com.html' 'https://www.linkedin.com' && " +
                "ls -lh 'downloads/linkedin.com.html'"
        )
    }

    func testAutoApprovesExplicitLocalFileURLDownloadShellRun() async {
        let request = "Download file:///tmp/quillcode-smoke/source.html into `downloads/example.html` in this workspace."
        await assertApproves(
            command: "mkdir -p 'downloads' && " +
                "curl -L --fail --silent --show-error " +
                "--output 'downloads/example.html' 'file:///tmp/quillcode-smoke/source.html' && " +
                "ls -lh 'downloads/example.html'",
            userMessage: request
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithChainedDestructiveCommand() async {
        await assertDoesNotApprove(
            command: "mkdir -p downloads && " +
                "curl -L --fail --output 'downloads/linkedin.com.html' 'https://www.linkedin.com' && " +
                "rm -rf ~/old",
            because: "a destructive command chained onto a download must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithSemicolonChainedCommand() async {
        await assertDoesNotApprove(
            command: "curl -L --fail --output 'downloads/linkedin.com.html' 'https://www.linkedin.com' ; " +
                "git reset --hard HEAD~5",
            because: "a `;`-chained command must not auto-approve on a download intent"
        )
    }

    func testAutoDoesNotAutoApproveDownloadThatChangesDirectoryFirst() async {
        await assertDoesNotApprove(
            command: "cd /tmp && curl -L --fail --output 'evil.html' 'https://www.linkedin.com'",
            because: "a `cd` before the download relocates the output and must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithRedirectOnCurlSegment() async {
        await assertDoesNotApprove(
            command: "curl -L --fail --output 'downloads/linkedin.com.html' " +
                "'https://www.linkedin.com' >> ~/.bashrc",
            because: "a redirect on the curl segment must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithSecondAbsoluteOutput() async {
        await assertDoesNotApprove(
            command: "curl -L --fail --output 'downloads/linkedin.com.html' " +
                "--output '/etc/cron.d/evil' " +
                "'https://www.linkedin.com' 'https://www.linkedin.com/jobs'",
            because: "a second absolute --output must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithConfigFileFlag() async {
        await assertDoesNotApprove(
            command: "curl -K /tmp/evil.cfg --fail --output 'downloads/linkedin.com.html' " +
                "'https://www.linkedin.com'",
            because: "curl -K config-file injection must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithDoubleQuotedCommandSubstitution() async {
        await assertDoesNotApprove(
            command: #"curl -L --fail --output 'downloads/linkedin.com.html' "https://www.linkedin.com/$(rm -rf ~)""#,
            because: "a double-quoted command substitution must not auto-approve"
        )
    }

    func testAutoApprovesDownloadWithBundledShortFlags() async {
        await assertApproves(
            command: "mkdir -p downloads && " +
                "curl -fsSL --output 'downloads/linkedin.com.html' 'https://www.linkedin.com' && " +
                "ls -lh 'downloads/linkedin.com.html'"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithFileWritingCurlFlags() async {
        let commands = [
            "curl -L --fail --output 'downloads/x.html' " +
                "--dump-header /etc/cron.d/evil 'https://www.linkedin.com'",
            "curl -L --fail --output 'downloads/x.html' " +
                "-c '/root/.ssh/authorized_keys' 'https://www.linkedin.com'",
            "curl -L --fail --output-dir /etc --output 'x' 'https://www.linkedin.com'",
            "curl -L --fail --output 'downloads/x.html' " +
                "--trace-ascii /etc/cron.d/evil 'https://www.linkedin.com'",
            "curl -L --fail -O 'https://www.linkedin.com'",
            "curl -L --fail --silent --proto-default file " +
                "-e 'https://www.linkedin.com' --output 'downloads/out.txt' '/etc/passwd'"
        ]

        for command in commands {
            await assertDoesNotApprove(
                command: command,
                because: "file-writing curl flag must not auto-approve: \(command)"
            )
        }
    }

    func testAutoDoesNotAutoApproveFileURLReadViaRefererHostGate() async {
        await assertDoesNotApprove(
            command: "curl -L --fail --silent -e 'https://www.linkedin.com' " +
                "--output 'downloads/out.txt' 'file:///etc/passwd'",
            because: "a file:// the user did not name must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithGlobOutput() async {
        await assertDoesNotApprove(
            command: "curl -L --fail -o downloads/* 'https://www.linkedin.com'",
            because: "a glob output target must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadSSRFToUnrequestedHostViaReferer() async {
        await assertDoesNotApprove(
            command: "curl -L --fail --silent -e 'https://www.linkedin.com' " +
                "--output 'downloads/x.json' " +
                "'http://169.254.169.254/latest/meta-data/iam/security-credentials/'",
            because: "an SSRF to an unrequested host must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWhenRequestedHostNormalizesEmpty() async {
        await assertDoesNotApprove(
            command: "curl -fsSL --output 'downloads/x.json' " +
                "'https://169.254.169.254./latest/meta-data/iam/security-credentials/'",
            userMessage: "please download from www. into downloads",
            because: "an empty-normalizing requested host must not wildcard a trailing-dot SSRF target"
        )
    }

    func testAutoDoesNotAutoApproveDownloadWithUserinfoHostConfusion() async {
        await assertDoesNotApprove(
            command: "curl -fsSL --output 'downloads/x.json' " +
                "'https://www.linkedin.com@169.254.169.254/latest/meta-data/'",
            because: "userinfo host confusion must not auto-approve"
        )
    }

    func testAutoDoesNotAutoApproveDownloadToLookalikeHost() async {
        await assertDoesNotApprove(
            command: "curl -L --fail --output 'downloads/x.html' 'https://linkedin.com.evil.test/'",
            because: "a look-alike host must not auto-approve"
        )
    }

    func testAutoApprovesDownloadFromSubdomainOfRequestedHost() async {
        await assertApproves(
            command: "mkdir -p downloads && " +
                "curl -fsSL --output 'downloads/x.html' 'https://docs.linkedin.com/page' && " +
                "ls -lh 'downloads/x.html'",
            userMessage: "Can you download from linkedin.com?"
        )
    }

    func testAutoDoesNotUseDownloadIntentForUnrelatedShellRun() async {
        await assertVerdict(
            .clarify,
            command: "rm -rf build"
        )
    }

    func testAutoDoesNotApproveDownloadForDifferentDomain() async {
        await assertVerdict(
            .clarify,
            command: "curl -L --output 'downloads/evil.example.html' 'https://evil.example'"
        )
    }

    func testAutoDoesNotApproveDownloadForDifferentLocalFileURL() async {
        let request = "Download file:///tmp/quillcode-smoke/source.html into `downloads/source.html`."
        await assertVerdict(
            .clarify,
            command: "curl -L --output 'downloads/source.html' 'file:///tmp/other/source.html'",
            userMessage: request
        )
    }

    func testAutoDoesNotApproveDownloadOutsideWorkspace() async {
        await assertVerdict(
            .clarify,
            command: "curl -L --output '/tmp/linkedin.html' 'https://www.linkedin.com'"
        )
    }
}

private extension SafetyDownloadPolicyTests {
    func assertApproves(
        command: String,
        userMessage: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let review = await review(command: command, userMessage: userMessage)
        XCTAssertEqual(review.verdict, .approve, review.rationale, file: file, line: line)
    }

    func assertDoesNotApprove(
        command: String,
        userMessage: String? = nil,
        because reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let review = await review(command: command, userMessage: userMessage)
        XCTAssertNotEqual(review.verdict, .approve, reason, file: file, line: line)
    }

    func assertVerdict(
        _ verdict: ApprovalVerdict,
        command: String,
        userMessage: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let review = await review(command: command, userMessage: userMessage)
        XCTAssertEqual(review.verdict, verdict, review.rationale, file: file, line: line)
    }

    func review(command: String, userMessage: String?) async -> SafetyReview {
        let message = userMessage ?? linkedinRequest
        return await StaticSafetyReviewer().review(.init(
            mode: .auto,
            userMessage: message,
            toolCall: ToolCall(name: shellRun.name, argumentsJSON: shellArgumentsJSON(command)),
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: message)]
        ))
    }

    func shellArgumentsJSON(_ command: String) -> String {
        struct ShellArguments: Encodable {
            var cmd: String
        }

        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(ShellArguments(cmd: command)),
            let string = String(data: data, encoding: .utf8)
        else {
            XCTFail("Failed to encode shell command arguments.")
            return #"{"cmd":""}"#
        }
        return string
    }
}
