import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentPreActionReasoningBudgetTests: XCTestCase {
    func testDeltaReasoningOverBudgetThrowsBeforeAction() async {
        let stream = eventStream([
            .reasoning("1234"),
            .reasoning("5678"),
            .text(#"{"type":"say","text":"too late"}"#),
        ])
        let guarded = AgentPreActionReasoningBudget.enforcing(maximumCharacters: 6, on: stream)

        do {
            for try await _ in guarded {}
            XCTFail("expected the reasoning budget to fire")
        } catch let error as AgentPreActionReasoningBudgetExceededError {
            XCTAssertEqual(error.maximumCharacters, 6)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testGrowingReasoningSnapshotsAreNotDoubleCounted() async throws {
        let events: [AgentTextStreamEvent] = [
            .reasoning("plan"),
            .reasoning("planning"),
            .reasoning("planning"),
            .text(#"{"type":"say","text":"done"}"#),
        ]
        let guarded = AgentPreActionReasoningBudget.enforcing(maximumCharacters: 8, on: eventStream(events))

        var collected: [AgentTextStreamEvent] = []
        for try await event in guarded { collected.append(event) }
        XCTAssertEqual(collected, events)
    }

    func testReasoningAfterActionStartsDoesNotTripBudget() async throws {
        let events: [AgentTextStreamEvent] = [
            .reasoning("1234"),
            .text(#"{"type":"say","#),
            .reasoning("this provider-specific fragment is ignored by the pre-action guard"),
            .text(#""text":"done"}"#),
        ]
        let guarded = AgentPreActionReasoningBudget.enforcing(maximumCharacters: 4, on: eventStream(events))

        var collected: [AgentTextStreamEvent] = []
        for try await event in guarded { collected.append(event) }
        XCTAssertEqual(collected, events)
    }

    func testBudgetOverrunUsesBoundedCorrectivePath() async throws {
        let state = ScriptedState([
            .failure(AgentPreActionReasoningBudgetExceededError(maximumCharacters: 12_000)),
            .success(.say("recovered")),
        ])
        let result = try await AgentRunner(llm: ScriptedClient(state: state)).send(
            "Create an interview guide for our ICP.",
            in: ChatThread(title: "t"),
            workspaceRoot: FileManager.default.temporaryDirectory
        )

        XCTAssertTrue(result.thread.messages.contains { $0.content == "recovered" })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("pre-action reasoning budget")
        })
        let calls = await state.recorded()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].contains {
            $0.role == .user && $0.content.contains("write the best current evidence checkpoint")
        })
    }

    func testBudgetOverrunPreservesInjectedForcedWriteAndExactPath() async throws {
        let state = ScriptedState([
            .failure(AgentPreActionReasoningBudgetExceededError(maximumCharacters: 6_000)),
            .success(.tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: #"{"path":"outputs/final.html","content":"complete"}"#
            ))),
        ])
        let runner = AgentRunner(llm: ScriptedClient(state: state))
        let forcedWrite = """
        The post-checkpoint synthesis gate is authoritative. Respond with host.file.write for exactly \
        ./outputs/final.html now. Do not resume research or return a final answer first.
        """
        var thread = ChatThread(title: "forced synthesis")

        let action = try await runner.nextAction(
            thread: &thread,
            userMessage: "Create the requested deliverable.",
            tools: [ToolDefinition.fileWrite],
            workspaceRoot: FileManager.default.temporaryDirectory,
            onProgress: nil,
            injectedCorrection: forcedWrite,
            reasoningBudgetPhase: .checkpoint
        )

        guard case .tool(let call) = action else {
            XCTFail("expected the forced file-write action")
            return
        }
        XCTAssertEqual(call.name, ToolDefinition.fileWrite.name)
        XCTAssertTrue(call.argumentsJSON.contains("outputs/final.html"))
        let calls = await state.recorded()
        XCTAssertEqual(calls.count, 2)
        let retryContext = calls[1].filter { $0.role == .user }.map(\.content).joined(separator: "\n")
        XCTAssertTrue(retryContext.contains("./outputs/final.html"))
        XCTAssertTrue(retryContext.contains("immediately preceding corrective instruction remains authoritative"))
        XCTAssertTrue(retryContext.contains("next action MUST use that tool and exact path"))
    }

    func testRepeatedReasoningOverrunSwitchesToFallbackAndKeepsItForRun() async throws {
        let root = try makeTempDirectory()
        try Data("grounded evidence".utf8).write(to: root.appendingPathComponent("input.txt"))
        let overrun = AgentPreActionReasoningBudgetExceededError(maximumCharacters: 6_000)
        let primary = ScriptedState([
            .failure(overrun),
            .failure(overrun),
            .failure(overrun),
        ])
        let fallback = ScriptedState([
            .success(.tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: #"{"path":"input.txt"}"#
            ))),
            .success(.say("Fallback synthesized the grounded evidence.")),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            maxToolSteps: 3,
            fallbackLLM: ScriptedClient(state: fallback)
        )

        let result = try await runner.send(
            "Read input.txt and summarize it.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Fallback synthesized the grounded evidence.")
        XCTAssertTrue(result.thread.events.contains {
            $0.summary == AgentRunner.reasoningFallbackSwitchNotice
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("promoting that route")
        })
        let primaryCalls = await primary.recorded().count
        let fallbackCalls = await fallback.recorded().count
        XCTAssertEqual(primaryCalls, 3)
        XCTAssertEqual(fallbackCalls, 2)
    }

    func testReasoningFallbackGetsFreshMalformedActionCorrectionBudget() async throws {
        let overrun = AgentPreActionReasoningBudgetExceededError(maximumCharacters: 6_000)
        let primary = ScriptedState([
            .failure(overrun),
            .failure(overrun),
            .failure(overrun),
        ])
        let fallback = ScriptedState([
            .failure(TrustedRouterAgentError.invalidActionJSON("I will write the artifact now.")),
            .success(.tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: #"{"path":"outputs/report.md","content":"complete"}"#
            ))),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            fallbackLLM: ScriptedClient(state: fallback)
        )
        var thread = ChatThread(title: "bounded fallback")

        let action = try await runner.nextAction(
            thread: &thread,
            userMessage: "Write the requested artifact.",
            tools: [ToolDefinition.fileWrite],
            workspaceRoot: FileManager.default.temporaryDirectory,
            onProgress: nil
        )

        guard case .tool(let call) = action else {
            XCTFail("expected the fallback's corrected file-write action")
            return
        }
        XCTAssertEqual(call.name, ToolDefinition.fileWrite.name)
        XCTAssertTrue(thread.events.contains {
            $0.summary.contains("returned a malformed action")
        })

        let primaryCalls = await primary.recorded().count
        let fallbackCalls = await fallback.recorded().count
        XCTAssertEqual(primaryCalls, 3)
        XCTAssertEqual(fallbackCalls, 2)
    }

    func testLongReasoningAfterFirstToolActionIsAllowed() async throws {
        let root = try makeTempDirectory()
        let inputs = root.appendingPathComponent("inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        try Data("LedgerLoop context".utf8).write(to: inputs.appendingPathComponent("context.md"))

        let state = UsageStreamSequenceState([
            [
                .text(#"{"type":"tool","name":"host.file.read","arguments":{"path":"inputs/context.md"}}"#),
            ],
            [
                .reasoning(String(repeating: "synthesis ", count: 1_400)),
                .text(#"{"type":"say","text":"Synthesis complete."}"#),
            ],
        ])
        let result = try await AgentRunner(
            llm: UsageStreamSequenceClient(state: state),
            preActionReasoningCharacterLimit: 12_000
        ).send(
            "Read inputs/context.md and synthesize it.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(result.thread.messages.last?.content, "Synthesis complete.")
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testReasoningBudgetRetightensAfterSuccessfulWrite() async throws {
        let root = try makeTempDirectory()
        let state = UsageStreamSequenceState([
            [
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"output.txt","content":"done"}}"#),
            ],
            [
                .reasoning(String(repeating: "verify ", count: 2_000)),
                .text(#"{"type":"say","text":"too late"}"#),
            ],
            [
                .reasoning(String(repeating: "still planning ", count: 900)),
                .text(#"{"type":"say","text":"still too late"}"#),
            ],
            [
                .text(#"{"type":"say","text":"Verified output.txt."}"#),
            ],
        ])
        let result = try await AgentRunner(
            llm: UsageStreamSequenceClient(state: state),
            preActionReasoningCharacterLimit: 12_000
        ).send(
            "Create output.txt.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Verified output.txt.")
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("pre-action reasoning budget")
        })
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 4)
    }

    func testDeepSeekSynthesisAfterPostDraftResearchCanRewriteAndVerify() async throws {
        let root = try makeTempDirectory()
        let state = UsageStreamSequenceState([
            [
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"outputs/report.md","content":"Draft pending source evidence."}}"#),
            ],
            [
                .text(#"{"type":"tool","name":"host.web.fetch","arguments":{"url":"https://example.com/revenue"}}"#),
            ],
            [
                .reasoning(String(repeating: "grounded synthesis ", count: 450)),
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"outputs/report.md","content":"Revenue was $214,500,000. Source: https://example.com/revenue"}}"#),
            ],
            [
                .text(#"{"type":"tool","name":"host.file.read","arguments":{"path":"outputs/report.md"}}"#),
            ],
            [
                .text(#"{"type":"say","text":"Completed and verified outputs/report.md."}"#),
            ],
        ])
        let runner = AgentRunner(
            llm: UsageStreamSequenceClient(state: state),
            additionalToolDefinitions: [.webFetch],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.webFetch.name else { return nil }
                return ToolResult(
                    ok: true,
                    stdout: "Fetched https://example.com/revenue (HTTP 200). Revenue: $214,500,000."
                )
            }
        )

        let result = try await runner.send(
            "Research https://example.com/revenue, create outputs/report.md, and verify it by reading it back.",
            in: ChatThread(
                title: "grounded synthesis",
                model: TrustedRouterChatParameters.deepSeekV4Flash0731Model
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Completed and verified outputs/report.md.")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            "Revenue was $214,500,000. Source: https://example.com/revenue"
        )
        XCTAssertFalse(result.thread.events.contains {
            $0.summary.contains("pre-action reasoning budget")
        })
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 5)
    }

    func testNonDeepSeekCorrectiveAttemptAllowsGroundedReasoningBeforeAction() async throws {
        let state = UsageStreamSequenceState([[
            .reasoning(String(repeating: "grounded analysis ", count: 450)),
            .text(#"{"type":"say","text":"Correction complete."}"#),
        ]])
        let runner = AgentRunner(llm: UsageStreamSequenceClient(state: state))
        var thread = ChatThread(
            title: "fallback correction",
            model: TrustedRouterDefaults.safetyPrimaryCatalogModel
        )

        let action = try await runner.nextAction(
            thread: &thread,
            userMessage: "Complete the researched deliverable.",
            tools: [ToolDefinition.fileWrite],
            workspaceRoot: FileManager.default.temporaryDirectory,
            onProgress: nil,
            injectedCorrection: "Use the retained evidence and emit the next action."
        )

        XCTAssertEqual(action, .say("Correction complete."))
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testBoundedFinalizationCapsDeepSeekReasoningAndRecoversFileWrite() async throws {
        let state = UsageStreamSequenceState([
            [
                .reasoning(String(repeating: "grounded synthesis ", count: 800)),
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"outputs/report.md","content":"ignored"}}"#),
            ],
            [
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"outputs/report.md","content":"complete"}}"#),
            ],
        ])
        let runner = AgentRunner(
            llm: UsageStreamSequenceClient(state: state),
            turnDeadlineSeconds: AgentRunner.boundedRunFinalizationTurnDeadlineSeconds
        )
        var thread = ChatThread(
            title: "bounded finalization",
            model: TrustedRouterChatParameters.deepSeekV4Flash0731Model
        )

        let action = try await runner.nextAction(
            thread: &thread,
            userMessage: "Complete the researched deliverable.",
            tools: [ToolDefinition.fileWrite],
            workspaceRoot: FileManager.default.temporaryDirectory,
            onProgress: nil,
            injectedCorrection: "Write outputs/report.md from the retained evidence now.",
            reasoningBudgetPhase: .boundedFinalization
        )

        guard case .tool(let call) = action else {
            XCTFail("expected the finalization file-write action")
            return
        }
        XCTAssertEqual(call.name, ToolDefinition.fileWrite.name)
        let argumentsData = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(
            JSONSerialization.jsonObject(with: argumentsData) as? [String: String]
        )
        XCTAssertEqual(arguments["path"], "outputs/report.md")
        XCTAssertTrue(thread.events.contains {
            $0.summary.contains("pre-action reasoning budget")
        })
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testBoundedRunAutomaticallyUsesDeadlineBoundFinalizationReasoning() async throws {
        let root = try makeTempDirectory()
        let state = UsageStreamSequenceState([
            [
                .reasoning(String(repeating: "grounded synthesis ", count: 800)),
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"outputs/report.md","content":"ignored"}}"#),
            ],
            [
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"outputs/report.md","content":"Verified evidence synthesized."}}"#),
            ],
            [
                .text(#"{"type":"tool","name":"host.file.read","arguments":{"path":"outputs/report.md"}}"#),
            ],
            [
                .text(#"{"type":"say","text":"Completed and verified outputs/report.md."}"#),
            ],
        ])
        let runner = AgentRunner(
            llm: UsageStreamSequenceClient(state: state),
            maxToolSteps: 6,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            "Write outputs/report.md from the retained evidence and read it back.",
            in: ChatThread(
                title: "bounded finalization",
                mode: .auto,
                model: TrustedRouterChatParameters.deepSeekV4Flash0731Model
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "Verified evidence synthesized."
        )
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Completed and verified outputs/report.md."
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("reserved finalization window")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("pre-action reasoning budget")
        })
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 4)
    }

    func testSuccessfulResearchEntersBoundedFinalizationAfterRepeatedReasoningOverrun() async throws {
        let root = try makeTempDirectory()
        let overrun = AgentPreActionReasoningBudgetExceededError(maximumCharacters: 12_000)
        let state = ScriptedState([
            .success(.tool(.init(
                name: ToolDefinition.webFetch.name,
                argumentsJSON: #"{"url":"https://example.com/evidence"}"#
            ))),
            .failure(overrun),
            .failure(overrun),
            .failure(overrun),
            .success(.tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: #"{"path":"outputs/report.md","content":"Grounded evidence retained."}"#
            ))),
            .success(.tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: #"{"path":"outputs/report.md"}"#
            ))),
            .success(.say("Completed and verified outputs/report.md.")),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: state),
            additionalToolDefinitions: [.webFetch],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.webFetch.name else { return nil }
                return ToolResult(
                    ok: true,
                    stdout: "Fetched official evidence from https://example.com/evidence."
                )
            },
            maxToolSteps: 8,
            boundedRunFinalizationAfterSeconds: 3_600
        )

        let result = try await runner.send(
            "Research https://example.com/evidence, write outputs/report.md, and read it back.",
            in: ChatThread(
                title: "early bounded finalization",
                mode: .auto,
                model: TrustedRouterChatParameters.deepSeekV4Flash0731Model
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "Grounded evidence retained."
        )
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Completed and verified outputs/report.md."
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("moved early into bounded finalization")
                && $0.summary.contains("outputs/report.md")
        })
        let calls = await state.recorded()
        XCTAssertEqual(calls.count, 7)
        let finalizationContext = calls[4]
            .filter { $0.role == .user }
            .map(\.content)
            .joined(separator: "\n")
        XCTAssertTrue(finalizationContext.contains("outputs/report.md"))
        XCTAssertTrue(finalizationContext.contains("Host-retained authoritative evidence"))
        XCTAssertTrue(finalizationContext.contains("https://example.com/evidence"))
    }

    func testCorrectiveExhaustionForcesOnePendingArtifactReadback() async throws {
        let root = try makeTempDirectory()
        let overrun = AgentPreActionReasoningBudgetExceededError(maximumCharacters: 12_000)
        let state = ScriptedState([
            .success(.tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: #"{"path":"outputs/report.md","content":"Grounded final artifact."}"#
            ))),
            .failure(overrun),
            .failure(overrun),
            .failure(overrun),
            .failure(overrun),
            .success(.say("Completed and verified outputs/report.md.")),
            .success(.say("Completed and verified outputs/report.md.")),
            .success(.say("Completed and verified outputs/report.md.")),
            .success(.say("Completed and verified outputs/report.md.")),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: state),
            maxToolSteps: 10,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            "Write outputs/report.md and verify it by reading it back.",
            in: ChatThread(
                title: "forced readback",
                mode: .auto,
                model: TrustedRouterChatParameters.deepSeekV4Flash0731Model
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(result.toolResults.count, 2)
        XCTAssertTrue(result.toolResults.last?.stdout.contains("Grounded final artifact.") == true)
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Completed and verified outputs/report.md."
        )
        XCTAssertEqual(result.thread.events.filter {
            $0.summary.contains(
                "advanced the exact required readback of ./outputs/report.md"
            )
        }.count, 1)
        let requestCount = await state.recorded().count
        XCTAssertLessThanOrEqual(requestCount, 9)
    }

    func testBoundedAuditUsesCorrectiveReasoningFuseAndPreservesValidatorInstruction() async throws {
        let root = try makeTempDirectory()
        let state = UsageStreamSequenceState([
            [
                .reasoning(String(repeating: "grounded synthesis ", count: 800)),
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"outputs/report.md","content":"ignored"}}"#),
            ],
            [
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"outputs/report.md","content":"Verified evidence synthesized."}}"#),
            ],
            [
                .reasoning(String(repeating: "audit planning ", count: 1_000)),
                .text(#"{"type":"say","text":"still planning"}"#),
            ],
            [
                .text(#"{"type":"tool","name":"host.shell.run","arguments":{"cmd":"python3 -c 'assert open(\"outputs/report.md\").read()' outputs/report.md"}}"#),
            ],
            [
                .text(#"{"type":"tool","name":"host.file.read","arguments":{"path":"outputs/report.md"}}"#),
            ],
            [
                .text(#"{"type":"say","text":"Completed and verified outputs/report.md."}"#),
            ],
        ])
        let runner = AgentRunner(
            llm: UsageStreamSequenceClient(state: state),
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                return ToolResult(ok: true, stdout: "PASS")
            },
            maxToolSteps: 8,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            "Write outputs/report.md, validate it deterministically, and read it back.",
            in: ChatThread(
                title: "bounded finalization",
                mode: .auto,
                model: TrustedRouterChatParameters.deepSeekV4Flash0731Model
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("pre-action reasoning budget")
        })
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 6)
    }

    func testRunnerDefaultsToReasoningBudgetAndCanDisableIt() {
        XCTAssertEqual(
            AgentRunner().preActionReasoningCharacterLimit,
            AgentRunner.defaultPreActionReasoningCharacterLimit
        )
        XCTAssertEqual(
            AgentRunner().interActionReasoningCharacterLimit,
            AgentRunner.defaultInterActionReasoningCharacterLimit
        )
        XCTAssertNil(AgentRunner(preActionReasoningCharacterLimit: nil).preActionReasoningCharacterLimit)
        XCTAssertNil(AgentRunner(interActionReasoningCharacterLimit: nil).interActionReasoningCharacterLimit)
        XCTAssertEqual(AgentRunner.correctiveActionReasoningCharacterLimit, 12_000)
    }

    func testDeepSeekV4FlashUsesProviderSafeReasoningLimit() {
        XCTAssertEqual(
            AgentPreActionReasoningBudget.effectiveMaximumCharacters(
                configured: AgentRunner.defaultInterActionReasoningCharacterLimit,
                modelID: TrustedRouterChatParameters.deepSeekV4Flash0731Model,
                phase: .startup
            ),
            AgentPreActionReasoningBudget.deepSeekV4Flash0731CharacterLimit
        )
        XCTAssertEqual(
            AgentPreActionReasoningBudget.effectiveMaximumCharacters(
                configured: 1_500,
                modelID: TrustedRouterChatParameters.deepSeekV4Flash0731Model,
                phase: .startup
            ),
            1_500,
            "a caller's tighter limit must remain authoritative"
        )
        XCTAssertEqual(
            AgentPreActionReasoningBudget.effectiveMaximumCharacters(
                configured: 16_000,
                modelID: "openai/gpt-5",
                phase: .synthesis
            ),
            16_000
        )
        XCTAssertEqual(
            AgentPreActionReasoningBudget.effectiveMaximumCharacters(
                configured: AgentRunner.defaultInterActionReasoningCharacterLimit,
                modelID: TrustedRouterChatParameters.deepSeekV4Flash0731Model,
                phase: .synthesis
            ),
            AgentPreActionReasoningBudget.deepSeekV4Flash0731SynthesisCharacterLimit
        )
        XCTAssertEqual(
            AgentPreActionReasoningBudget.effectiveMaximumCharacters(
                configured: AgentRunner.defaultPreActionReasoningCharacterLimit,
                modelID: TrustedRouterChatParameters.deepSeekV4Flash0731Model,
                phase: .correction
            ),
            AgentPreActionReasoningBudget.deepSeekV4Flash0731SynthesisCharacterLimit
        )
        XCTAssertEqual(
            AgentPreActionReasoningBudget.effectiveMaximumCharacters(
                configured: AgentRunner.defaultInterActionReasoningCharacterLimit,
                modelID: TrustedRouterChatParameters.deepSeekV4Flash0731Model,
                phase: .boundedFinalization
            ),
            AgentPreActionReasoningBudget.deepSeekV4Flash0731SynthesisCharacterLimit
        )
    }

    func testCorrectiveContextKeepsOriginalRequestAndRecentEvidence() {
        let original = ChatMessage(role: .user, content: "Build the final revenue table.")
        let stale = (0..<12).map { index in
            ChatMessage(role: .tool, content: String(repeating: "stale-\(index) ", count: 1_000))
        }
        let currentArtifact = ChatMessage(role: .tool, content: "CURRENT ARTIFACT WITH TBD")
        let gitLab = ChatMessage(role: .tool, content: "GitLab: 192210000 196000000 211400000 214500000")
        let asana = ChatMessage(role: .tool, content: "Asana: 187300000 196900000 201000000 205600000")
        let correction = ChatMessage(role: .user, content: "Write outputs/final.html now.")
        let thread = ChatThread(
            title: "recovery",
            messages: [original] + stale + [currentArtifact, gitLab, asana, correction]
        )

        let projected = AgentCorrectiveContext.projected(thread)

        XCTAssertEqual(projected.messages.first?.id, original.id)
        XCTAssertTrue(projected.messages.contains(where: { $0.id == currentArtifact.id }))
        XCTAssertTrue(projected.messages.contains(where: { $0.id == gitLab.id }))
        XCTAssertTrue(projected.messages.contains(where: { $0.id == asana.id }))
        XCTAssertEqual(projected.messages.last?.id, correction.id)
        XCTAssertLessThan(projected.messages.count, thread.messages.count)
    }

    func testCorrectiveContextPinsSuccessfulResearchOutsideRecentWindow() throws {
        func toolMessage(name: String, ok: Bool, stdout: String, url: String? = nil) throws
            -> ChatMessage {
            var arguments: [String: Any] = [:]
            if let url { arguments["url"] = url }
            let argumentsData = try JSONSerialization.data(withJSONObject: arguments)
            let argumentsJSON = try XCTUnwrap(String(data: argumentsData, encoding: .utf8))
            let payload: [String: Any] = [
                "toolCall": [
                    "name": name,
                    "argumentsJSON": argumentsJSON,
                ],
                "result": [
                    "ok": ok,
                    "stdout": stdout,
                    "stderr": "",
                    "artifacts": [],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return ChatMessage(
                role: .tool,
                content: try XCTUnwrap(String(data: data, encoding: .utf8))
            )
        }

        let original = ChatMessage(role: .user, content: "Build the final revenue table.")
        let delegated = try toolMessage(
            name: ToolDefinition.subagentsRun.name,
            ok: true,
            stdout: "GitLab Q2 236000000 Q3 244400000 Q4 260400000 Q1 264200000"
        )
        let fetched = try toolMessage(
            name: ToolDefinition.webFetch.name,
            ok: true,
            stdout: "monday.com Q1 revenue 351300000",
            url: "https://ir.monday.com/q1-results"
        )
        let failedFetch = try toolMessage(
            name: ToolDefinition.webFetch.name,
            ok: false,
            stdout: "untrusted partial value 999999999",
            url: "https://example.com/failed"
        )
        let stale = (0..<12).map { index in
            ChatMessage(role: .tool, content: String(repeating: "stale-\(index) ", count: 1_000))
        }
        let recent = (0..<4).map { index in
            ChatMessage(role: .tool, content: String(repeating: "recent-\(index) ", count: 1_000))
        }
        let thread = ChatThread(
            title: "recovery",
            messages: [original, delegated, fetched, failedFetch] + stale + recent
        )

        let projected = AgentCorrectiveContext.projected(thread)
        let projectedText = projected.messages.map(\.content).joined(separator: "\n")

        XCTAssertEqual(projected.messages.first?.id, original.id)
        XCTAssertTrue(projectedText.contains("Host-retained successful research evidence"))
        XCTAssertTrue(projectedText.contains("GitLab Q2 236000000"))
        XCTAssertTrue(projectedText.contains("monday.com Q1 revenue 351300000"))
        XCTAssertTrue(projectedText.contains("https://ir.monday.com/q1-results"))
        XCTAssertTrue(projectedText.contains("authoritative over delegated summaries"))
        XCTAssertFalse(projectedText.contains("untrusted partial value"))
        XCTAssertEqual(projected.messages.last?.id, recent.last?.id)

        let directRange = try XCTUnwrap(projectedText.range(of: "monday.com Q1 revenue"))
        let delegatedRange = try XCTUnwrap(projectedText.range(of: "GitLab Q2"))
        XCTAssertLessThan(directRange.lowerBound, delegatedRange.lowerBound)
    }

    func testCorrectiveContextPinsRequiredLocalInputOutsideRecentWindow() throws {
        let argumentsJSON = ToolArguments.json([
            "paths": ["inputs/evaluation-context.md", "inputs/records.csv"],
        ])
        let payload: [String: Any] = [
            "toolCall": [
                "name": ToolDefinition.fileReadMany.name,
                "argumentsJSON": argumentsJSON,
            ],
            "result": [
                "ok": true,
                "stdout": """
                ## File 1: inputs/evaluation-context.md
                Use exact local records.
                ## File 2: inputs/records.csv
                fiscal_year,nominal_revenue_usd
                2023,4200000
                2024,5100000
                2025,6000000
                """,
                "stderr": "",
                "artifacts": [],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let read = ChatMessage(
            role: .tool,
            content: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
        let original = ChatMessage(role: .user, content: """
        Read every applicable source directly before acting.
        For this task the required inputs are: `inputs/evaluation-context.md`, \
        `inputs/records.csv`.
        Write outputs/report.md.
        """)
        let stale = (0..<12).map { index in
            ChatMessage(role: .tool, content: String(repeating: "stale-\(index) ", count: 1_000))
        }
        let recent = (0..<4).map { index in
            ChatMessage(role: .tool, content: String(repeating: "recent-\(index) ", count: 1_000))
        }

        let projected = AgentCorrectiveContext.projected(
            ChatThread(messages: [original, read] + stale + recent)
        )
        let text = projected.messages.map(\.content).joined(separator: "\n")

        XCTAssertTrue(text.contains("Host-retained required local input evidence"))
        XCTAssertTrue(text.contains("2023,4200000"))
        XCTAssertTrue(text.contains("2025,6000000"))
        XCTAssertTrue(text.contains("authoritative over model recollection"))
    }

    func testCorrectiveContextKeepsStrongestFetchPerURLAndDropsSemanticFailures() throws {
        func toolMessage(stdout: String, url: String) throws -> ChatMessage {
            let argumentsData = try JSONSerialization.data(withJSONObject: ["url": url])
            let argumentsJSON = try XCTUnwrap(String(data: argumentsData, encoding: .utf8))
            let payload: [String: Any] = [
                "toolCall": [
                    "name": ToolDefinition.webFetch.name,
                    "argumentsJSON": argumentsJSON,
                ],
                "result": ["ok": true, "stdout": stdout, "stderr": "", "artifacts": []],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return ChatMessage(
                role: .tool,
                content: try XCTUnwrap(String(data: data, encoding: .utf8))
            )
        }

        let source = "https://example.gov/series"
        let complete = try toolMessage(
            stdout: "Year | Jan | Feb | Jun\n2026 | 325.252 | 326.785 | 333.952",
            url: source
        )
        let truncated = try toolMessage(stdout: "2026 | 325.252", url: source)
        let apiFailure = try toolMessage(
            stdout: #"Fetched API\n\n{"status":"REQUEST_NOT_PROCESSED","message":"threshold"}"#,
            url: "https://api.example.gov/data"
        )
        let original = ChatMessage(role: .user, content: "Build the CPI report.")
        let stale = (0..<12).map { index in
            ChatMessage(role: .tool, content: String(repeating: "stale-\(index) ", count: 1_000))
        }
        let recent = (0..<4).map { index in
            ChatMessage(role: .tool, content: String(repeating: "recent-\(index) ", count: 1_000))
        }

        let projected = AgentCorrectiveContext.projected(
            ChatThread(messages: [original, complete, truncated, apiFailure] + stale + recent)
        )
        let text = projected.messages.map(\.content).joined(separator: "\n")

        XCTAssertTrue(text.contains("333.952"))
        XCTAssertFalse(text.contains("REQUEST_NOT_PROCESSED"))
        XCTAssertEqual(text.components(separatedBy: "[host.web.fetch (\(source))]").count, 2)
    }

    func testCorrectiveContextPinsCompletedWorkerBeforeLongFailedWorkerOutput() throws {
        let failedNoise = String(repeating: "failed-worker-noise ", count: 1_200)
        let delegatedOutput = """
        {
          "summary": "Delegation deadline reached; synthesize completed results.",
          "workers": [
            {"name":"Failed first","status":"failed","summary":"\(failedNoise)"},
            {"name":"CPI 2025","status":"completed","summary":"VERIFIED_CPI_2025 annual average 320.229 from https://data.bls.gov/timeseries/CUUR0000SA0"},
            {"name":"CPI 2026","status":"cancelled","summary":"Recovered June 2026 evidence."}
          ]
        }
        """
        let toolPayload: [String: Any] = [
            "toolCall": [
                "name": ToolDefinition.subagentsRun.name,
                "argumentsJSON": "{}",
            ],
            "result": [
                "ok": true,
                "stdout": delegatedOutput,
                "stderr": "",
                "artifacts": [],
            ],
        ]
        let toolData = try JSONSerialization.data(withJSONObject: toolPayload)
        let delegated = ChatMessage(
            role: .tool,
            content: try XCTUnwrap(String(data: toolData, encoding: .utf8))
        )
        let original = ChatMessage(role: .user, content: "Build the CPI report.")
        let stale = (0..<12).map { index in
            ChatMessage(role: .tool, content: String(repeating: "stale-\(index) ", count: 1_000))
        }
        let recent = (0..<4).map { index in
            ChatMessage(role: .tool, content: String(repeating: "recent-\(index) ", count: 1_000))
        }

        let projected = AgentCorrectiveContext.projected(
            ChatThread(messages: [original, delegated] + stale + recent)
        )
        let projectedText = projected.messages.map(\.content).joined(separator: "\n")
        let completedRange = try XCTUnwrap(projectedText.range(of: "VERIFIED_CPI_2025"))
        let failedRange = try XCTUnwrap(projectedText.range(of: "failed-worker-noise"))

        XCTAssertLessThan(completedRange.lowerBound, failedRange.lowerBound)
        XCTAssertTrue(projectedText.contains("[completed worker: CPI 2025]"))
        XCTAssertTrue(projectedText.contains("https://data.bls.gov/timeseries/CUUR0000SA0"))
    }

    private func eventStream(
        _ events: [AgentTextStreamEvent]
    ) -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    private actor ScriptedState {
        var steps: [Result<AgentAction, Error>]
        private(set) var calls: [[ChatMessage]] = []

        init(_ steps: [Result<AgentAction, Error>]) {
            self.steps = steps
        }

        func next(thread: ChatThread) throws -> AgentAction {
            calls.append(thread.messages)
            guard !steps.isEmpty else { return .say("out of steps") }
            return try steps.removeFirst().get()
        }

        func recorded() -> [[ChatMessage]] { calls }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState

        func nextAction(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AgentAction {
            try await state.next(thread: thread)
        }
    }

    private actor UsageStreamSequenceState {
        private var streams: [[AgentTextStreamEvent]]
        private var requests = 0

        init(_ streams: [[AgentTextStreamEvent]]) {
            self.streams = streams
        }

        func next() -> [AgentTextStreamEvent] {
            requests += 1
            guard !streams.isEmpty else { return [] }
            return streams.removeFirst()
        }

        func requestCount() -> Int { requests }
    }

    private struct UsageStreamSequenceClient: UsageStreamingLLMClient {
        let state: UsageStreamSequenceState

        func nextAction(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AgentAction {
            throw AgentError.emptyStreamingResponse
        }

        func actionTextStream(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AsyncThrowingStream<String, Error> {
            throw AgentError.emptyStreamingResponse
        }

        func actionEventStream(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
            let events = await state.next()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }
}
