import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
import XCTest

final class CLIReviewCommandTests: XCTestCase {
    func testMockUncommittedReviewRunsCompleteReadSequenceWithoutPersistence() async throws {
        let repository = try gitRepository()
        let home = try temporaryDirectory(prefix: "uncommitted-home")
        try "changed\n".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "new\n".write(
            to: repository.appendingPathComponent("New.swift"),
            atomically: true,
            encoding: .utf8
        )
        let output = BufferedCLIOutput()

        let status = await commandRunner(llm: MockLLMClient()).run(
            arguments: [
                "--home", home.path,
                "review", "--mock", "--uncommitted", "--cwd", repository.path
            ],
            input: BufferedCLIInput(text: "ignored pipe", isTerminal: false),
            output: output
        )
        let snapshot = await output.snapshot()

        XCTAssertEqual(status, 0)
        XCTAssertEqual(occurrences(of: "✓ host.git.status", in: snapshot.standardError), 1)
        XCTAssertEqual(occurrences(of: "✓ host.git.diff", in: snapshot.standardError), 2)
        XCTAssertEqual(occurrences(of: "✓ host.review.submit", in: snapshot.standardError), 1)
        XCTAssertFalse(snapshot.standardError.contains("✗"), snapshot.standardError)
        XCTAssertTrue(snapshot.standardOutput.hasPrefix("## Code review\n"))
        XCTAssertTrue(snapshot.standardOutput.contains("No actionable findings."))
        XCTAssertEqual(try savedThreads(in: home), [])
    }

    func testMockBaseAndCommitReviewsUseScopedGitDiffs() async throws {
        let repository = try gitRepository()
        try requireGitSuccess(["switch", "--quiet", "-c", "feature"], in: repository)
        try "feature\n".write(
            to: repository.appendingPathComponent("Feature.swift"),
            atomically: true,
            encoding: .utf8
        )
        try requireGitSuccess(["add", "Feature.swift"], in: repository)
        try requireGitSuccess(["commit", "--quiet", "-m", "Add feature"], in: repository)

        for arguments in [
            ["--base", "main"],
            ["--commit", "HEAD", "--title", "Add feature"]
        ] {
            let home = try temporaryDirectory(prefix: "scoped-home")
            let output = BufferedCLIOutput()
            let status = await commandRunner(llm: MockLLMClient()).run(
                arguments: ["--home", home.path, "review", "--mock"]
                    + arguments
                    + ["--cwd", repository.path],
                input: BufferedCLIInput(isTerminal: true),
                output: output
            )
            let snapshot = await output.snapshot()

            XCTAssertEqual(status, 0, snapshot.standardError)
            XCTAssertEqual(occurrences(of: "✓ host.git.diff", in: snapshot.standardError), 1)
            XCTAssertFalse(snapshot.standardError.contains("✗"), snapshot.standardError)
            XCTAssertEqual(try savedThreads(in: home), [])
            if arguments.first == "--commit" {
                XCTAssertTrue(snapshot.standardOutput.hasPrefix("## Code review: Add feature\n"))
            }
        }
    }

    func testReviewFailsClosedWhenModelDoesNotSubmitStructuredReport() async throws {
        let repository = try gitRepository()
        let home = try temporaryDirectory(prefix: "missing-report-home")
        let output = BufferedCLIOutput()

        let status = await commandRunner(llm: ReviewScriptedLLM(actions: [
            .say("I reviewed the change.")
        ])).run(
            arguments: [
                "--home", home.path,
                "review", "--mock", "--uncommitted", "--cwd", repository.path
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )
        let snapshot = await output.snapshot()

        XCTAssertEqual(status, 1)
        XCTAssertEqual(snapshot.standardOutput, "")
        XCTAssertTrue(snapshot.standardError.contains("required structured report"))
        XCTAssertEqual(try savedThreads(in: home), [])
    }

    func testReviewRejectsNonRepositoryBeforeInvokingModel() async throws {
        let workspace = try temporaryDirectory(prefix: "not-git")
        let home = try temporaryDirectory(prefix: "not-git-home")
        let llm = CountingReviewLLM()
        let output = BufferedCLIOutput()

        let status = await commandRunner(llm: llm).run(
            arguments: [
                "--home", home.path,
                "review", "--mock", "--uncommitted", "--cwd", workspace.path
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )
        let snapshot = await output.snapshot()
        let invocationCount = await llm.invocationCount

        XCTAssertEqual(status, 1)
        XCTAssertTrue(snapshot.standardError.contains("not inside a Git repository"))
        XCTAssertEqual(invocationCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path + "/threads"))
    }

    func testInterruptCancelsReviewWithoutReportOrPersistence() async throws {
        let repository = try gitRepository()
        let home = try temporaryDirectory(prefix: "interrupt-home")
        let llm = BlockingReviewLLM()
        let interrupt = ManualReviewInterruptSource()
        let output = BufferedCLIOutput()
        let runner = commandRunner(llm: llm, interruptSource: interrupt)

        let task = Task {
            await runner.run(
                arguments: [
                    "--home", home.path,
                    "review", "--mock", "--uncommitted", "--cwd", repository.path
                ],
                input: BufferedCLIInput(isTerminal: true),
                output: output
            )
        }
        await llm.waitUntilStarted()
        interrupt.interrupt()
        let status = await task.value
        let snapshot = await output.snapshot()

        XCTAssertEqual(status, 1)
        XCTAssertEqual(snapshot.standardOutput, "")
        XCTAssertTrue(snapshot.standardError.contains("Run interrupted."))
        XCTAssertEqual(try savedThreads(in: home), [])
    }

    private func commandRunner(
        llm: any LLMClient,
        interruptSource: any CLIInterruptSource = InactiveCLIInterruptSource()
    ) -> QuillCodeCommandRunner {
        QuillCodeCommandRunner(
            parser: CLIArgumentParser(),
            runnerFactory: { configuration in
                AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: true
                )
            },
            interruptSource: interruptSource
        )
    }

    private func gitRepository() throws -> URL {
        let repository = try temporaryDirectory(prefix: "repository")
        try requireGitSuccess(["init", "--quiet", "--initial-branch=main"], in: repository)
        try requireGitSuccess(
            ["config", "user.email", "quillcode-tests@example.invalid"],
            in: repository
        )
        try requireGitSuccess(["config", "user.name", "QuillCode Tests"], in: repository)
        try "initial\n".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try requireGitSuccess(["add", "README.md"], in: repository)
        try requireGitSuccess(["commit", "--quiet", "-m", "Initial"], in: repository)
        return repository
    }

    private func requireGitSuccess(_ arguments: [String], in repository: URL) throws {
        let result = GitProcessRunner().runGit(arguments, cwd: repository, timeoutSeconds: 10)
        guard result.ok else {
            throw CLIReviewCommandTestError.gitFixture(result.error ?? result.stderr)
        }
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-review-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func savedThreads(in home: URL) throws -> [ChatThread] {
        try JSONThreadStore(directory: home.appendingPathComponent("threads")).list()
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum CLIReviewCommandTestError: Error {
    case gitFixture(String)
}

private actor ReviewScriptedLLM: LLMClient {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        actions.isEmpty ? .say("No action remains.") : actions.removeFirst()
    }
}

private actor CountingReviewLLM: LLMClient {
    private(set) var invocationCount = 0

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        invocationCount += 1
        return .say("Unexpected invocation.")
    }
}

private actor BlockingReviewLLM: LLMClient {
    private var didStart = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        didStart = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        try await Task.sleep(for: .seconds(30))
        return .say("Unexpected completion.")
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class ManualReviewInterruptSource: CLIInterruptSource, @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func makeInterruptStream() -> AsyncStream<Void> {
        stream
    }

    func interrupt() {
        continuation.yield()
        continuation.finish()
    }
}
