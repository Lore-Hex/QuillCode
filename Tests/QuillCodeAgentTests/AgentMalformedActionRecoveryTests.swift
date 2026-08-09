import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// A scripted LLM client whose steps either throw or return an action, recording every call's
/// thread + userMessage so tests can assert exactly what each retry request contained.
private actor ThrowingSequenceLLMState {
    enum Step {
        case action(AgentAction)
        case failure(any Error)
    }

    private var steps: [Step]
    private(set) var calls: [(userMessage: String, messages: [ChatMessage])] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func next(thread: ChatThread, userMessage: String) throws -> AgentAction {
        calls.append((userMessage, thread.messages))
        guard !steps.isEmpty else {
            return .say("out of scripted steps")
        }
        switch steps.removeFirst() {
        case .action(let action):
            return action
        case .failure(let error):
            throw error
        }
    }

    func recordedCalls() -> [(userMessage: String, messages: [ChatMessage])] { calls }
}

private struct ThrowingSequenceLLMClient: LLMClient {
    let state: ThrowingSequenceLLMState

    init(steps: [ThrowingSequenceLLMState.Step]) {
        self.state = ThrowingSequenceLLMState(steps: steps)
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try await state.next(thread: thread, userMessage: userMessage)
    }
}

private struct ImmediateEmptyResponseRetrySleeper: RetrySleeper {
    func sleep(_ duration: Duration) async throws {}
}

private actor RecordingEmptyResponseRetrySleeper: RetrySleeper {
    private var durations: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        durations.append(duration)
    }

    func recordedDurations() -> [Duration] { durations }
}

final class AgentMalformedActionRecoveryTests: XCTestCase {
    private static let garbage = "，������但我��随时？？ mojibake .UseFont���/or"
    // Not parseable by AgentImmediateActionPlanner, so the LLM path is always exercised.
    private static let prompt = "summarize the current state of the repository"

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("malformed-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testOneMalformedResponseIsRepromptedAndRunSucceeds() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.invalidActionJSON(Self.garbage)),
            .action(.say("Recovered fine.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered fine.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("Self-healing: the model returned a malformed action")
        }, "durable thread must carry the self-healing notice")

        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        // The corrective request carries the garbage + correction ONLY on the transient retry thread.
        let retryMessages = calls[1].messages
        XCTAssertTrue(retryMessages.contains { $0.role == .assistant && $0.content.contains("mojibake") })
        XCTAssertTrue(calls[1].userMessage.contains("was not a valid QuillCode action JSON object"))
        // The durable transcript never contains the garbage or the correction prompt.
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("mojibake") })
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("was not a valid QuillCode action JSON object")
        })
    }

    func testTruncatedFileWriteUsesCompactConciseCorrectionAndRecovers() async throws {
        let uniqueTail = "UNIQUE_TRUNCATED_TAIL_MUST_NOT_BE_ECHOED"
        let malformed = "{\"type\":\"file.write\",\"path\":\"outputs/report.md\",\"content\":\"# Report\\n\\n"
            + String(repeating: "detailed analysis ", count: 300)
            + uniqueTail
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.invalidActionJSON(malformed)),
            .action(.say("Recovered without executing partial content.")),
        ])
        let runner = AgentRunner(llm: client)
        let root = try makeTempDirectory()

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered without executing partial content.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("truncated a file write")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].userMessage.contains("truncated inside its content string"))
        XCTAssertTrue(calls[1].userMessage.contains("no more than 6000 characters"))
        XCTAssertTrue(calls[1].messages.contains {
            $0.role == .assistant && $0.content.contains("Truncated host.file.write action omitted")
        })
        XCTAssertFalse(calls[1].messages.contains { $0.content.contains(uniqueTail) })
        XCTAssertFalse(calls[1].userMessage.contains(uniqueTail))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("outputs/report.md").path
        ))
    }

    func testPersistentMalformedOutputFailsAfterExactlyTwoCorrections() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.invalidActionJSON("bad1")),
            .failure(TrustedRouterAgentError.invalidActionJSON("bad2")),
            .failure(TrustedRouterAgentError.invalidActionJSON("bad3")),
        ])
        let runner = AgentRunner(llm: client)

        do {
            _ = try await runner.send(
                Self.prompt,
                in: ChatThread(mode: .auto),
                workspaceRoot: try makeTempDirectory()
            )
            XCTFail("expected invalidActionJSON after correction limit")
        } catch TrustedRouterAgentError.invalidActionJSON(let text) {
            XCTAssertEqual(text, "bad3", "the LAST malformed payload should surface")
        }

        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3, "1 original + exactly 2 corrective re-prompts")
    }

    func testEmptyToolArgumentsAreRepromptedAndRunSucceeds() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.emptyToolArguments(ToolDefinition.fileRead.name)),
            .action(.say("Recovered with complete arguments.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered with complete arguments.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("omitted arguments for host.file.read")
        }, result.thread.events.map(\.summary).joined(separator: " | "))
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].userMessage.contains("omitted its required arguments"))
        XCTAssertTrue(calls[1].messages.contains {
            $0.role == .assistant && $0.content.contains("\"arguments\":{}")
        })
    }

    func testPersistentEmptyToolArgumentsFailAfterExactlyTwoCorrections() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.emptyToolArguments(ToolDefinition.fileRead.name)),
            .failure(TrustedRouterAgentError.emptyToolArguments(ToolDefinition.fileRead.name)),
            .failure(TrustedRouterAgentError.emptyToolArguments(ToolDefinition.fileRead.name)),
        ])
        let runner = AgentRunner(llm: client)

        do {
            _ = try await runner.send(
                Self.prompt,
                in: ChatThread(mode: .auto),
                workspaceRoot: try makeTempDirectory()
            )
            XCTFail("expected emptyToolArguments after correction limit")
        } catch TrustedRouterAgentError.emptyToolArguments(let toolName) {
            XCTAssertEqual(toolName, ToolDefinition.fileRead.name)
        }

        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3, "1 original + exactly 2 corrective re-prompts")
    }

    func testStreamInterruptionIsRetriedAndRunSucceeds() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(AgentStreamInterruptedError(underlying: URLError(.cancelled))),
            .action(.say("Survived the reset.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Survived the reset.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("Self-healing: the model stream was interrupted")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        // A stream interruption is a pure resample — no corrective context is injected.
        XCTAssertFalse(calls[1].messages.contains {
            $0.content.contains("was not a valid QuillCode action JSON object")
        })
    }

    func testExhaustedStreamInterruptionsSurfaceTheUnderlyingError() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(AgentStreamInterruptedError(underlying: URLError(.networkConnectionLost))),
            .failure(AgentStreamInterruptedError(underlying: URLError(.networkConnectionLost))),
            .failure(AgentStreamInterruptedError(underlying: URLError(.cancelled))),
        ])
        let runner = AgentRunner(llm: client)

        do {
            _ = try await runner.send(
                Self.prompt,
                in: ChatThread(mode: .auto),
                workspaceRoot: try makeTempDirectory()
            )
            XCTFail("expected the underlying URLError after the retry limit")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled, "the marker must unwrap to the underlying error")
        }

        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3)
    }

    func testMixedMalformedThenInterruptedRecoversWithinSharedBudget() async throws {
        // The two recovery kinds share one bounded budget — a flapping model can't get 2 + 2.
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.invalidActionJSON("bad")),
            .failure(AgentStreamInterruptedError(underlying: URLError(.networkConnectionLost))),
            .action(.say("Third time lucky.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Third time lucky.")
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3)
    }

    func testEmptyStreamingResponseIsRetriedAndRunSucceeds() async throws {
        // A clean-but-empty stream (gateway teardown before the first token, empty 200, immediate
        // [DONE]) is the streaming twin of TrustedRouterAgentError.emptyResponse and gets a resample.
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(AgentError.emptyStreamingResponse),
            .action(.say("Filled in on retry.")),
        ])
        let sleeper = RecordingEmptyResponseRetrySleeper()
        let runner = AgentRunner(llm: client, emptyResponseRetrySleeper: sleeper)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Filled in on retry.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("Self-healing: the model returned an empty response")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        let durations = await sleeper.recordedDurations()
        XCTAssertEqual(durations, [.seconds(2)])
    }

    func testEmptyStreamingResponsesDoNotConsumeMalformedActionBudget() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.invalidActionJSON("bad action")),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .action(.say("Recovered after independent budgets.")),
        ])
        let runner = AgentRunner(
            llm: client,
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered after independent budgets.")
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 6)
    }

    func testExhaustedEmptyStreamingResponsesStayFatal() async throws {
        let attemptsPerResolver = AgentRunner.emptyResponseRetryLimit + 1
        let resolverRuns = AgentRunner.startupActionContinuationLimit + 1
        let client = ThrowingSequenceLLMClient(steps: (0..<(attemptsPerResolver * resolverRuns)).map { _ in
            .failure(AgentError.emptyStreamingResponse)
        })
        let sleeper = RecordingEmptyResponseRetrySleeper()
        let runner = AgentRunner(llm: client, emptyResponseRetrySleeper: sleeper)

        do {
            _ = try await runner.send(
                Self.prompt,
                in: ChatThread(mode: .auto),
                workspaceRoot: try makeTempDirectory()
            )
            XCTFail("expected emptyStreamingResponse after the retry limit")
        } catch AgentError.emptyStreamingResponse {
            // Correct terminal error.
        }
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, attemptsPerResolver * resolverRuns)
        XCTAssertTrue(calls[attemptsPerResolver].userMessage.contains("startup recovery 1 of 3"))
        XCTAssertTrue(calls[attemptsPerResolver * 2].userMessage.contains("startup recovery 2 of 3"))
        XCTAssertTrue(calls[attemptsPerResolver * 3].userMessage.contains("startup recovery 3 of 3"))
        let durations = await sleeper.recordedDurations()
        XCTAssertEqual(
            durations,
            Array(
                repeating: [.seconds(2), .seconds(4), .seconds(8), .seconds(12), .seconds(12), .seconds(12)],
                count: resolverRuns
            ).flatMap { $0 }
        )
    }

    func testExhaustedStartupResponsesRecoverThroughActionOnlyContinuation() async throws {
        let attemptsPerResolver = AgentRunner.emptyResponseRetryLimit + 1
        let client = ThrowingSequenceLLMClient(steps:
            (0..<attemptsPerResolver).map { _ in
                .failure(AgentError.emptyStreamingResponse)
            } + [
                .action(.say("Recovered after startup correction.")),
            ]
        )
        let runner = AgentRunner(
            llm: client,
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered after startup correction.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("no actionable startup response")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, attemptsPerResolver + 1)
        XCTAssertTrue(calls.last?.userMessage.contains("startup recovery 1 of 3") == true)
        XCTAssertTrue(calls.last?.userMessage.contains("Emit exactly one QuillCode JSON object") == true)
    }

    func testExhaustedEmptyFinalResponseAfterSuccessfulWriteFinishesFromToolResult() async throws {
        let write = ToolCall(
            name: "host.file.write",
            argumentsJSON: ToolArguments.json([
                "path": "report.md",
                "content": "# Result\n\nThe completed analysis.\n",
            ])
        )
        let client = ThrowingSequenceLLMClient(steps: [
            .action(.tool(write)),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
        ])
        let sleeper = RecordingEmptyResponseRetrySleeper()
        let runner = AgentRunner(
            llm: client,
            emptyResponseRetrySleeper: sleeper
        )
        let root = try makeTempDirectory()

        let result = try await runner.send(
            "Analyze the repository and write report.md with the result.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("report.md").path))
        XCTAssertFalse(result.thread.messages.last?.content.isEmpty ?? true)
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("no final action after completing workspace work")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3, "post-tool recovery should not consume the normal retry budget")
        let durations = await sleeper.recordedDurations()
        XCTAssertEqual(durations, [], "the single post-tool resample should be immediate")
    }

    func testExhaustedEmptyResponseAfterSuccessfulReadGetsThreeRunLevelContinuations() async throws {
        let root = try makeTempDirectory()
        try "source facts\n".write(
            to: root.appendingPathComponent("source.txt"),
            atomically: true,
            encoding: .utf8
        )
        let readSource = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "source.txt"])
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "report.md",
                "content": "# Report\n\nSource facts summarized.\n",
            ])
        )
        let client = ThrowingSequenceLLMClient(steps: [
            .action(.tool(readSource)),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .action(.tool(write)),
            .action(.say("Created and verified report.md.")),
        ])
        let runner = AgentRunner(
            llm: client,
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            "Read source.txt, write report.md, then read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 3, "source read, write, and forced readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("no action after successful source work")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 9)
        XCTAssertTrue(calls[3].userMessage.contains("QuillCode continuation"))
        XCTAssertTrue(calls[3].userMessage.contains("continuation 1 of 3"))
        XCTAssertTrue(calls[5].userMessage.contains("continuation 2 of 3"))
        XCTAssertTrue(calls[7].userMessage.contains("continuation 3 of 3"))
        XCTAssertTrue(calls[3].userMessage.contains("host.file.read"))
    }

    func testExhaustedContinuationBudgetResetsAfterNextExecutedTool() async throws {
        let root = try makeTempDirectory()
        try "source facts\n".write(
            to: root.appendingPathComponent("source.txt"),
            atomically: true,
            encoding: .utf8
        )
        let readSource = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "source.txt"])
        )
        let listWorkspace = ToolCall(
            name: ToolDefinition.fileList.name,
            argumentsJSON: ToolArguments.json(["path": "."])
        )
        let client = ThrowingSequenceLLMClient(steps: [
            .action(.tool(readSource)),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .action(.tool(listWorkspace)),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .action(.say("Read the source and inspected the workspace.")),
        ])
        let runner = AgentRunner(
            llm: client,
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.map(\.ok), [true, true])
        let continuationNotices = result.thread.events.filter {
            $0.kind == .notice && $0.summary.contains("no action after successful source work")
        }
        XCTAssertEqual(continuationNotices.count, 4)
        XCTAssertEqual(
            continuationNotices.filter { $0.summary.contains("attempt 1 of 3") }.count,
            2,
            "the continuation budget should restart after the second tool executes"
        )
        XCTAssertEqual(
            continuationNotices.filter { $0.summary.contains("attempt 2 of 3") }.count,
            2
        )
    }

    func testExhaustedEmptyResponseAdvancesUnreadExplicitSourceBeforeModelContinuation() async throws {
        let root = try makeTempDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("inputs"),
            withIntermediateDirectories: true
        )
        try "founder context\n".write(
            to: root.appendingPathComponent("inputs/context.md"),
            atomically: true,
            encoding: .utf8
        )
        try "metric,value\nleads,12\n".write(
            to: root.appendingPathComponent("inputs/data.csv"),
            atomically: true,
            encoding: .utf8
        )
        let readContext = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "inputs/context.md"])
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n\nFounder context with 12 leads.\n",
            ])
        )
        let client = ThrowingSequenceLLMClient(steps: [
            .action(.tool(readContext)),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .action(.tool(write)),
            .action(.say("Created and verified outputs/report.md.")),
            .action(.say("Created and verified outputs/report.md.")),
        ])
        let runner = AgentRunner(
            llm: client,
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            """
            Use the file read tool separately on `inputs/context.md` and `inputs/data.csv`.
            Write the deliverable to `outputs/report.md`, then read the saved file back to verify it.
            """,
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 4, "two source reads, write, and forced readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("advanced an explicit requested source read")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 6, "local source recovery must not consume another model call")
        XCTAssertFalse(calls.contains { $0.userMessage.contains("QuillCode continuation") })
    }

    func testMalformedTerminalOutputAfterWriteStillEnforcesReadback() async throws {
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "report.md",
                "content": "# Report\n\nCompleted analysis.\n",
            ])
        )
        let client = ThrowingSequenceLLMClient(steps: [
            .action(.tool(write)),
            .failure(TrustedRouterAgentError.invalidActionJSON("bad1")),
            .failure(TrustedRouterAgentError.invalidActionJSON("bad2")),
            .failure(TrustedRouterAgentError.invalidActionJSON("bad3")),
            .action(.say("Created and verified report.md.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            "Write report.md, then read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.toolResults.map(\.ok), [true, true], "write plus forced readback")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("malformed terminal output")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 5)
    }

    func testExhaustedEmptyReadArgumentsAfterWriteStillEnforceReadback() async throws {
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "report.md",
                "content": "# Report\n\nCompleted analysis.\n",
            ])
        )
        let client = ThrowingSequenceLLMClient(steps: [
            .action(.tool(write)),
            .failure(TrustedRouterAgentError.emptyToolArguments(ToolDefinition.fileRead.name)),
            .failure(TrustedRouterAgentError.emptyToolArguments(ToolDefinition.fileRead.name)),
            .failure(TrustedRouterAgentError.emptyToolArguments(ToolDefinition.fileRead.name)),
            .action(.say("Created and verified report.md.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            "Write report.md, then read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.toolResults.map(\.ok), [true, true], "write plus forced readback")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("required artifact readback")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 5)
    }

    func testUserStopAtBudgetExhaustionSurfacesAsCancellationNotFailure() async throws {
        // Both recovery attempts burned, then the user stops during the third call whose garbage
        // arrives after the cancel: the resolver must honor the stop (CancellationError), never
        // report a malformed-model failure for a run the user deliberately stopped.
        let started = expectation(description: "third LLM call started")
        let client = BlockingThenThrowingLLMClient(blockOnCall: 3, onBlockedCall: { started.fulfill() })
        let runner = AgentRunner(llm: client)
        let root = try makeTempDirectory()

        let prompt = Self.prompt
        let task = Task { [runner] in
            try await runner.send(prompt, in: ChatThread(mode: .auto), workspaceRoot: root)
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await client.releaseBlockedCall()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // Correct: the stop wins over the exhausted-budget malformed error.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 3)
    }

    func testCorrectiveAttemptUsageIsHarvestedOntoDurableThread() async throws {
        // Corrective re-prompts must never be invisible to spend accounting: the scratch corrective
        // run's token-usage event is harvested onto the durable thread.
        let client = ScriptedUsageStreamingLLMClient(scripts: [
            .init(text: "totally not json ���", usage: .init(promptTokens: 10, completionTokens: 5, totalTokens: 15)),
            .init(text: #"{"type":"say","text":"Recovered with usage."}"#, usage: .init(promptTokens: 20, completionTokens: 7, totalTokens: 27)),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered with usage.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("malformed action")
        })
        XCTAssertTrue(
            result.thread.events.contains { $0.summary == "Model token usage" },
            "the corrective attempt's usage event must land on the durable thread"
        )
        // The corrective context itself never persists.
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("totally not json") })
    }

    func testReasoningOnlyCompletionUsesActionCorrectionAndPreservesUsage() async throws {
        let client = ScriptedUsageStreamingLLMClient(scripts: [
            .init(
                text: "",
                reasoning: "I should keep planning instead of choosing a tool.",
                usage: .init(promptTokens: 100, completionTokens: 40, totalTokens: 140)
            ),
            .init(
                text: #"{"type":"say","text":"Recovered after reasoning."}"#,
                usage: .init(promptTokens: 120, completionTokens: 8, totalTokens: 128)
            ),
        ])

        let result = try await AgentRunner(llm: client).send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered after reasoning.")
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("finished reasoning without an action")
        })
        let usages = result.thread.events.compactMap(ModelTokenUsageEvent.usage(from:))
        XCTAssertEqual(usages, [
            .init(promptTokens: 100, completionTokens: 40, totalTokens: 140),
            .init(promptTokens: 120, completionTokens: 8, totalTokens: 128),
        ])
        let userMessages = await client.recordedUserMessages()
        XCTAssertEqual(userMessages.count, 2)
        XCTAssertTrue(userMessages[1].contains("Respond now with exactly one JSON action object"))
    }

    func testCancelledRunDoesNotReprompt() async throws {
        let started = expectation(description: "first LLM call started")
        let client = BlockingThenThrowingLLMClient(blockOnCall: 1, onBlockedCall: { started.fulfill() })
        let runner = AgentRunner(llm: client)
        let root = try makeTempDirectory()

        let prompt = Self.prompt
        let task = Task { [runner] in
            try await runner.send(prompt, in: ChatThread(mode: .auto), workspaceRoot: root)
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await client.releaseBlockedCall()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            // Reaching here without a second LLM call is the assertion that matters.
        }
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 1, "a cancelled run must not receive a corrective re-prompt")
    }
}

/// Throws invalidActionJSON on every call; call number `blockOnCall` first signals, then blocks until
/// released — so tests can cancel the owning task mid-call at a precise attempt and prove the
/// resolver honors the stop (instead of re-prompting, or reporting a malformed failure at exhaustion).
private actor BlockingThenThrowingLLMClientState {
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func enter() -> Int {
        calls += 1
        return calls
    }

    func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private struct BlockingThenThrowingLLMClient: LLMClient {
    let state = BlockingThenThrowingLLMClientState()
    let blockOnCall: Int
    let onBlockedCall: @Sendable () -> Void

    init(blockOnCall: Int, onBlockedCall: @escaping @Sendable () -> Void) {
        self.blockOnCall = blockOnCall
        self.onBlockedCall = onBlockedCall
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        let count = await state.enter()
        if count == blockOnCall {
            onBlockedCall()
            await state.waitForRelease()
        }
        throw TrustedRouterAgentError.invalidActionJSON("garbage-attempt-\(count)")
    }

    func releaseBlockedCall() async {
        await state.release()
    }

    func callCount() async -> Int {
        await state.calls
    }
}

/// A scripted UsageStreamingLLMClient: each call streams its script's text then a usage event, so the
/// production usage-accounting path (collectStreamingAction) runs for both original and corrective
/// attempts.
private struct ScriptedUsageStreamingLLMClient: UsageStreamingLLMClient {
    struct Script: Sendable {
        var text: String
        var reasoning: String? = nil
        var usage: ModelTokenUsage
    }

    private actor Progress {
        private(set) var index = 0
        private(set) var userMessages: [String] = []
        func next(userMessage: String) -> Int {
            userMessages.append(userMessage)
            defer { index += 1 }
            return index
        }
        func count() -> Int { index }
        func recordedUserMessages() -> [String] { userMessages }
    }

    private let scripts: [Script]
    private let progress = Progress()

    init(scripts: [Script]) {
        self.scripts = scripts
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        // Force the streaming path in tests: the resolver should never take the plain branch for a
        // UsageStreamingLLMClient.
        throw TrustedRouterAgentError.emptyResponse
    }

    func actionTextStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<String, Error> {
        throw TrustedRouterAgentError.emptyResponse
    }

    func actionEventStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        let index = await progress.next(userMessage: userMessage)
        let script = scripts[min(index, scripts.count - 1)]
        return AsyncThrowingStream { continuation in
            if let reasoning = script.reasoning {
                continuation.yield(.reasoning(reasoning))
            }
            if !script.text.isEmpty {
                continuation.yield(.text(script.text))
            }
            continuation.yield(.usage(script.usage))
            continuation.finish()
        }
    }

    func recordedUserMessages() async -> [String] {
        await progress.recordedUserMessages()
    }
}
