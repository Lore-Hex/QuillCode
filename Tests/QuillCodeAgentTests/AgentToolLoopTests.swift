import XCTest
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentToolLoopTests: XCTestCase {
    func testBoundedFinalizationPromptMakesRetainedEvidenceAuthoritative() {
        let evidence = "Successful host.web.fetch observation:\n2026 June CPI: 333.952"
        let synthesis = AgentBoundedRunFinalizationGate.correctionPrompt(
            path: "outputs/report.md",
            userMessage: "Write outputs/report.md with the official figures.",
            evidenceReceipt: evidence
        )
        let audit = AgentBoundedRunFinalizationGate.correctionPrompt(
            path: "outputs/report.md",
            userMessage: "Write outputs/report.md with the official figures.",
            phase: .audit,
            evidenceReceipt: evidence
        )

        for prompt in [synthesis, audit] {
            XCTAssertTrue(prompt.contains("2026 June CPI: 333.952"))
            XCTAssertTrue(prompt.contains(
                "exact output from successful required-file reads and research tool calls"
            ))
            XCTAssertTrue(prompt.contains("authoritative over delegated summaries"))
            XCTAssertTrue(prompt.contains("claim is contradicted by the receipt"))
            XCTAssertTrue(prompt.contains("align every value with its exact source header"))
            XCTAssertTrue(prompt.contains("Never relabel a half-period"))
            XCTAssertTrue(prompt.contains("underlying observations independently"))
            XCTAssertTrue(prompt.contains("locate intended table fields by their headers"))
        }
    }

    func testRequiredStructuredInputBindingAlsoAppliesToInlineValidators() {
        let ungrounded = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert len(open('outputs/report.md').read()) > 0\" "
                    + "outputs/report.md # inputs/data.csv QuillCode validator",
            ])
        )
        let grounded = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"import csv; source=list(csv.DictReader("
                    + "open('inputs/data.csv'))); assert source; "
                    + "assert open('outputs/report.md').read()\" outputs/report.md "
                    + "# QuillCode validator",
            ])
        )

        XCTAssertEqual(
            AgentBoundedRunFinalizationGate.missingRequiredStructuredInputBindings(
                in: ungrounded,
                deliverablePath: "outputs/report.md",
                requiredInputPaths: ["inputs/data.csv"]
            ),
            ["inputs/data.csv"]
        )
        XCTAssertEqual(
            AgentBoundedRunFinalizationGate.missingRequiredStructuredInputBindings(
                in: grounded,
                deliverablePath: "outputs/report.md",
                requiredInputPaths: ["inputs/data.csv"]
            ),
            []
        )
    }

    func testValidatorBindingCorrectionIncludesRejectedProposalAndAcceptedReaderShape() {
        let proposed = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/validate-report.py",
                "content": "assert '4200000' in open('outputs/report.md').read()",
            ])
        )

        let prompt = AgentBoundedRunFinalizationGate.validatorInputBindingCorrectionPrompt(
            path: "outputs/report.md",
            missingInputPaths: ["inputs/records.csv"],
            evidenceReceipt: nil,
            proposedCall: proposed
        )

        XCTAssertTrue(prompt.contains("rejected actions are not part of the durable tool transcript"))
        XCTAssertTrue(prompt.contains("outputs/validate-report.py"))
        XCTAssertTrue(prompt.contains("assert '4200000'"))
        XCTAssertTrue(prompt.contains("open(\"inputs/records.csv\""))
        XCTAssertTrue(prompt.contains("csv.DictReader"))
        XCTAssertTrue(prompt.contains("never use /tmp"))
    }

    func testAgentUsesPlanUpdateToolWhenAvailable() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            additionalToolDefinitions: [ToolDefinition.planUpdate],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.planUpdate.name else { return nil }
                return ToolResult(ok: true, stdout: call.argumentsJSON)
            }
        )

        let result = try await runner.send(
            "plan the work",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertEqual(result.thread.messages.last?.content, "Updated the task plan.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.planUpdate.name) completed"
        })
        let update = try JSONHelpers.decode(AgentPlanUpdate.self, from: result.toolResults[0].stdout)
        XCTAssertEqual(update.plan.map(\.status), [.completed, .inProgress, .pending])
    }

    func testAgentUsesHandoffUpdateToolWhenAvailable() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            additionalToolDefinitions: [ToolDefinition.handoffUpdate],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.handoffUpdate.name else { return nil }
                return ToolResult(ok: true, stdout: call.argumentsJSON)
            }
        )

        let result = try await runner.send(
            "write a handoff summary",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertEqual(result.thread.messages.last?.content, "Updated the handoff summary.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.handoffUpdate.name) completed"
        })
        let update = try JSONHelpers.decode(AgentHandoffUpdate.self, from: result.toolResults[0].stdout)
        XCTAssertEqual(update.summary, "Current task state is ready for continuation.")
        XCTAssertEqual(update.nextSteps, ["Review the latest tool output", "Continue from the Activity pane"])
    }

    func testAgentRunsRequestedSubagentsAndSummarizesTheirResult() async throws {
        let root = try makeTempDirectory()
        let capture = ToolCallCapture()
        let runner = AgentRunner(
            additionalToolDefinitions: [ToolDefinition.subagentsRun],
            threadToolExecutionOverride: { call, _, thread, _ in
                guard call.name == ToolDefinition.subagentsRun.name else { return nil }
                await capture.record(call)
                return AgentThreadToolExecution(
                    thread: thread,
                    result: ToolResult(ok: true, stdout: """
                    {
                      "runID": "D34DB33F-0000-4000-8000-000000000001",
                      "summary": "Subagents completed 2 workers for: Coordinate parallel review of the current task.",
                      "workers": [],
                      "awaitingApproval": false
                    }
                    """)
                )
            }
        )

        let result = try await runner.send(
            "Use two subagents for parallel validation.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Subagents completed 2 workers for: Coordinate parallel review of the current task."
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.subagentsRun.name) completed"
        })
        let recordedCall = await capture.call
        let capturedCall = try XCTUnwrap(recordedCall)
        let request = try JSONHelpers.decode(
            SubagentRunToolRequest.self,
            from: capturedCall.argumentsJSON
        )
        XCTAssertEqual(request.workers.map { $0.name }, ["Explorer", "Verifier"])
    }

    func testAgentRedirectsSecondDelegatedBatchIntoNamedDeliverableRewrite() async throws {
        let root = try makeTempDirectory()
        let capture = ToolCallCapture()
        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "research competitors",
                "workers": [["name": "Researcher", "role": "collect evidence"]],
            ] as [String: Any])
        )
        let initialWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Draft\n\nInitial delegated evidence.\n",
            ])
        )
        let read = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
        )
        let finalWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Final report\n\nAll available evidence synthesized.\n",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(delegated), .tool(initialWrite), .tool(read), .tool(delegated),
                .tool(finalWrite), .tool(read), .say("Completed the final report."),
            ]),
            additionalToolDefinitions: [ToolDefinition.subagentsRun],
            threadToolExecutionOverride: { call, _, thread, _ in
                guard call.name == ToolDefinition.subagentsRun.name else { return nil }
                await capture.record(call)
                return AgentThreadToolExecution(
                    thread: thread,
                    result: ToolResult(ok: true, stdout: "Delegated evidence returned.")
                )
            }
        )

        let result = try await runner.send(
            "Research competitors, write outputs/report.md, and read it back.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let delegatedCallCount = await capture.count
        XCTAssertEqual(delegatedCallCount, 1)
        XCTAssertTrue(result.thread.messages.last?.content.contains("# Final report") == true)
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("redirected repeated delegated research")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "# Final report\n\nAll available evidence synthesized.\n"
        )
    }

    func testBoundedRunFinalizationRejectsHelperWriteUntilNamedDeliverableExists() async throws {
        let root = try makeTempDirectory()
        let helperWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/helper.csv",
                "content": "intermediate,data\n",
            ])
        )
        let deliverableWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Final report\n\nVerified evidence synthesized.\n",
            ])
        )
        let read = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(helperWrite), .tool(deliverableWrite), .tool(read),
                .say("Completed the final report."),
            ]),
            maxToolSteps: 8,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            "Write outputs/report.md and read it back.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("outputs/helper.csv").path
        ))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "# Final report\n\nVerified evidence synthesized.\n"
        )
        XCTAssertEqual(result.thread.messages.last?.content, "Completed the final report.")
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("reserved finalization window")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("rejected a non-finalization action")
        })
    }

    func testBoundedRunFinalizationStopsResearchAfterDeliverableWrite() async throws {
        let root = try makeTempDirectory()
        let capture = ToolCallCapture()
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Final report\n\nVerified evidence synthesized.\n",
            ])
        )
        let research = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.test/more-research"])
        )
        let read = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(write), .tool(research), .tool(read), .say("Completed and verified the report."),
            ]),
            toolExecutionOverride: { call, _ in
                if call.name == ToolDefinition.fileWrite.name {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    return nil
                }
                if call.name == ToolDefinition.webFetch.name {
                    await capture.record(call)
                    return ToolResult(ok: true, stdout: "late research")
                }
                return nil
            },
            maxToolSteps: 8,
            boundedRunFinalizationAfterSeconds: 0.1
        )

        let result = try await runner.send(
            "Write outputs/report.md and verify the saved output by reading it back.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let researchCallCount = await capture.count
        XCTAssertEqual(researchCallCount, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "Completed and verified the report.")
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("reserved finalization window")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("rejected a non-finalization action")
        })
    }

    func testBoundedRunFinalizationPermitsAuditHelperValidatorAndReadback() async throws {
        let root = try makeTempDirectory()
        let researchCapture = ToolCallCapture()
        let validatorCapture = ToolCallCapture()
        let deliverableWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "name,value\nalpha,1\nbeta,2\n",
            ])
        )
        let research = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.test/late-research"])
        )
        let validatorWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": """
                import pathlib, sys
                rows = pathlib.Path(sys.argv[1]).read_text().splitlines()
                assert len(rows) == 3, "report.md must contain one header and exactly two rows"
                print("PASS: report.md has exactly two rows")
                """,
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(deliverableWrite), .tool(research), .tool(validatorWrite),
            ]),
            toolExecutionOverride: { call, _ in
                if call.name == ToolDefinition.webFetch.name {
                    await researchCapture.record(call)
                    return ToolResult(ok: true, stdout: "late research")
                }
                if call.name == ToolDefinition.shellRun.name {
                    await validatorCapture.record(call)
                    return ToolResult(ok: true, stdout: "PASS: report.md has exactly two rows")
                }
                return nil
            },
            maxToolSteps: 10,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            "Create outputs/report.md with exactly two data rows. After writing, read the saved "
                + "output back and verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let researchCallCount = await researchCapture.count
        let validatorCallCount = await validatorCapture.count
        let validatorCall = await validatorCapture.call
        XCTAssertEqual(researchCallCount, 0)
        let eventSummary = result.thread.events.map(\.summary).joined(separator: "\n")
        XCTAssertEqual(validatorCallCount, 1, eventSummary)
        XCTAssertEqual(
            (try? ToolArguments(validatorCall?.argumentsJSON ?? "{}").string("cmd")),
            "python3 'scripts/validate_report.py' 'outputs/report.md' # QuillCode validator"
        )
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Completed and verified `outputs/report.md`.",
            eventSummary
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("authored validator helper")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("audit passed")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("artifact readback succeeded")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("rejected a non-finalization action")
        })
    }

    func testBoundedRunStartsRequiredAuditImmediatelyAfterDeliverableWrite() async throws {
        let root = try makeTempDirectory()
        let researchCapture = ToolCallCapture()
        let validatorCapture = ToolCallCapture()
        let deliverableWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "name,value\nalpha,1\nbeta,2\n",
            ])
        )
        let research = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.test/late-research"])
        )
        let validatorWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/validate_report.py",
                "content": """
                import pathlib, sys
                target = pathlib.Path(sys.argv[1])
                assert target.name == "report.md"
                rows = target.read_text().splitlines()
                assert len(rows) == 3
                print("PASS: exactly two data rows")
                """,
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(deliverableWrite), .tool(research), .tool(validatorWrite),
            ]),
            toolExecutionOverride: { call, _ in
                if call.name == ToolDefinition.webFetch.name {
                    await researchCapture.record(call)
                    return ToolResult(ok: true, stdout: "late research")
                }
                if call.name == ToolDefinition.shellRun.name {
                    await validatorCapture.record(call)
                    return ToolResult(ok: true, stdout: "PASS: exactly two data rows")
                }
                return nil
            },
            maxToolSteps: 10,
            boundedRunFinalizationAfterSeconds: 3_600
        )

        let result = try await runner.send(
            "Create outputs/report.md with exactly two data rows, run a deterministic post-write "
                + "validator against it, and read the saved output back before finishing.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let eventSummary = result.thread.events.map(\.summary).joined(separator: "\n")
        let researchCallCount = await researchCapture.count
        let validatorCallCount = await validatorCapture.count
        XCTAssertEqual(researchCallCount, 0, eventSummary)
        XCTAssertEqual(validatorCallCount, 1, eventSummary)
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Completed and verified `outputs/report.md`.",
            eventSummary
        )
        XCTAssertTrue(eventSummary.contains(
            "entered deterministic contract audit immediately after writing ./outputs/report.md"
        ))
    }

    func testBoundedFinalizationRejectsValidatorUntilSourceContradictionIsRewritten() async throws {
        let root = try makeTempDirectory()
        let validatorCapture = ToolCallCapture()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/series"])
        )
        let incorrectWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "The latest monthly benchmark is June 2026, index 326.785.",
            ])
        )
        let prematureValidator = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/validate_report.py",
                "content": "assert '326.785' in open('outputs/report.md').read()",
            ])
        )
        let correctedWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "The latest monthly benchmark is June 2026, index 333.952.",
            ])
        )
        let acceptedValidator = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/validate_report.py",
                "content": "assert '333.952' in open('outputs/report.md').read()\nprint('PASS')",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(fetch), .tool(incorrectWrite), .tool(prematureValidator),
                .tool(correctedWrite), .tool(acceptedValidator),
            ]),
            toolExecutionOverride: { call, _ in
                if call.name == ToolDefinition.webFetch.name {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    return ToolResult(ok: true, stdout: """
                    | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | HALF1 |
                    | --- | --- | --- | --- | --- | --- | --- | --- | --- |
                    | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | | 330.724 |
                    """)
                }
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                await validatorCapture.record(call)
                return ToolResult(ok: true, stdout: "PASS")
            },
            maxToolSteps: 12,
            boundedRunFinalizationAfterSeconds: 0.05
        )

        let result = try await runner.send(
            "Research the official table, write outputs/report.md, run a deterministic validator "
                + "against every row, read the saved output back, and report completion.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let diagnostics = result.thread.events.map(\.summary).joined(separator: "\n")
        let validatorCount = await validatorCapture.count
        XCTAssertEqual(validatorCount, 1, diagnostics)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "The latest monthly benchmark is June 2026, index 333.952.",
            diagnostics
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("rejected validation of source-contradictory artifact")
        }, diagnostics)
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("rejected source-contradictory artifact immediately after writing")
        }, diagnostics)
        XCTAssertEqual(result.stopReason, .finished, diagnostics)
    }

    func testBoundedRunFinalizationRejectsValidatorThatOnlyCommentsRequiredCSV() async throws {
        let root = try makeTempDirectory()
        let inputs = root.appendingPathComponent("inputs")
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        try "name,value\nalpha,1\nbeta,2\n".write(
            to: inputs.appendingPathComponent("data.csv"),
            atomically: true,
            encoding: .utf8
        )
        let validatorCapture = ToolCallCapture()
        let deliverableWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "name,value\nalpha,1\nbeta,2\n",
            ])
        )
        let ungroundedValidatorWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": """
                import pathlib, sys
                # Expected values came from inputs/data.csv.
                target = "outputs/report.md"
                assert sys.argv[1].endswith(target)
                rows = pathlib.Path(sys.argv[1]).read_text().splitlines()
                assert rows == ["name,value", "alpha,1", "beta,2"]
                print("PASS")
                """,
            ])
        )
        let groundedValidator = """
        import csv, pathlib, sys
        target = "outputs/report.md"
        assert sys.argv[1].endswith(target)
        source = list(csv.DictReader(open('inputs/data.csv', newline='')))
        report = pathlib.Path(sys.argv[1]).read_text().splitlines()
        assert len(source) == 2
        assert len(report) == 3
        print("PASS")
        """
        let groundedValidatorWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": groundedValidator,
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(deliverableWrite), .tool(deliverableWrite),
                .tool(ungroundedValidatorWrite), .tool(groundedValidatorWrite),
            ]),
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                await validatorCapture.record(call)
                return ToolResult(ok: true, stdout: "PASS")
            },
            maxToolSteps: 12,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            """
            Read every applicable source directly before acting.
            For this task the required inputs are: `inputs/data.csv`.
            Create `outputs/report.md` with exactly two data rows. After writing, read the saved \
            output back and verify it.
            """,
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let validatorCallCount = await validatorCapture.count
        let eventSummary = result.thread.events.map(\.summary).joined(separator: "\n")
        XCTAssertEqual(validatorCallCount, 1, eventSummary)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("scripts/validate_report.py")),
            groundedValidator,
            eventSummary
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("did not parse required structured input inputs/data.csv")
        }, eventSummary)
        XCTAssertEqual(result.stopReason, .finished, eventSummary)
    }

    func testBoundedRunFinalizationReturnsFailedValidatorToModelForRepair() async throws {
        let root = try makeTempDirectory()
        let validatorCapture = ToolCallCapture()
        let readCapture = ToolCallCapture()
        let initialWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "name,value\nalpha,1\n",
            ])
        )
        let repairedWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "name,value\nalpha,1\nbeta,2\n",
            ])
        )
        let repairRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
        )
        let initialValidatorWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": "assert len(open('outputs/report.md').read().splitlines()) == 3",
            ])
        )
        let repairedValidatorWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": "assert len(open('outputs/report.md').read().splitlines()) == 3\nprint('PASS')",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(initialWrite), .tool(initialValidatorWrite),
                .tool(repairRead), .tool(repairedWrite), .tool(repairedValidatorWrite),
            ]),
            toolExecutionOverride: { call, _ in
                if call.name == ToolDefinition.fileRead.name {
                    await readCapture.record(call)
                    return nil
                }
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                await validatorCapture.record(call)
                let attempt = await validatorCapture.count
                if attempt == 1 {
                    return ToolResult(ok: false, stderr: "expected exactly two data rows")
                }
                return ToolResult(ok: true, stdout: "PASS")
            },
            maxToolSteps: 10,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            "Create outputs/report.md with exactly two data rows. After writing, read the saved "
                + "output back and verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let validatorCallCount = await validatorCapture.count
        let readCallCount = await readCapture.count
        XCTAssertEqual(validatorCallCount, 2)
        XCTAssertEqual(readCallCount, 2, "one repair read plus the automatic final readback")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "name,value\nalpha,1\nbeta,2\n"
        )
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Completed and verified `outputs/report.md`."
        )
        XCTAssertEqual(result.stopReason, .finished)
    }

    func testFailedShellAuthoredArtifactIsReadBeforeModelRepair() async throws {
        let root = try makeTempDirectory()
        let validatorCapture = ToolCallCapture()
        let readCapture = ToolCallCapture()
        let initialValidator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert False\" outputs/report.md # QuillCode validator",
            ])
        )
        let repairedWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "name,value\nalpha,1\nbeta,2\n",
            ])
        )
        let repairedValidator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert len(open('outputs/report.md').read().splitlines()) "
                    + "== 3\" outputs/report.md # QuillCode validator",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(initialValidator), .tool(repairedWrite), .tool(repairedValidator),
                .say("Completed outputs/report.md."),
            ]),
            toolExecutionOverride: { call, workspaceRoot in
                if call.name == ToolDefinition.fileRead.name {
                    await readCapture.record(call)
                    return nil
                }
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                await validatorCapture.record(call)
                if await validatorCapture.count == 1 {
                    let output = workspaceRoot.appendingPathComponent("outputs/report.md")
                    try? FileManager.default.createDirectory(
                        at: output.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? "name,value\nalpha,1\n".write(
                        to: output,
                        atomically: true,
                        encoding: .utf8
                    )
                    return ToolResult(ok: false, stderr: "expected exactly two data rows")
                }
                return ToolResult(ok: true, stdout: "PASS")
            },
            maxToolSteps: 10
        )

        let result = try await runner.send(
            "Create outputs/report.md with exactly two data rows. After writing, read the saved "
                + "output back and verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let validatorCallCount = await validatorCapture.count
        let readCallCount = await readCapture.count
        XCTAssertEqual(validatorCallCount, 2)
        XCTAssertEqual(readCallCount, 2, "one repair read plus final readback")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "name,value\nalpha,1\nbeta,2\n"
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("advanced one exact repair read")
        })
        XCTAssertEqual(result.stopReason, .finished)
    }

    func testBoundedRunFinalizationRejectsCosmeticallyChangedFailedValidatorReplay() async throws {
        let root = try makeTempDirectory()
        let validatorCapture = ToolCallCapture()
        let initialWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "name,value\nalpha,1\nbeta,2\n",
            ])
        )
        let repairRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
        )
        let initialValidatorWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": "assert len(open('outputs/report.md').read().splitlines()) == 4",
            ])
        )
        let repairedValidatorWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": "assert len(open('outputs/report.md').read().splitlines()) == 3\nprint('PASS')",
            ])
        )
        let cosmeticReplay = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 'scripts/validate_report.py' 'outputs/report.md'",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(initialWrite), .tool(initialValidatorWrite), .tool(repairRead),
                .tool(cosmeticReplay), .tool(repairedValidatorWrite),
            ]),
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                await validatorCapture.record(call)
                return await validatorCapture.count == 1
                    ? ToolResult(ok: false, stderr: "validator expected four rows")
                    : ToolResult(ok: true, stdout: "PASS")
            },
            maxToolSteps: 12,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            "Create outputs/report.md with exactly two data rows. After writing, read the saved "
                + "output back and verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let validatorCallCount = await validatorCapture.count
        XCTAssertEqual(validatorCallCount, 2)
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("rejected an unchanged failed validator")
        })
        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Completed and verified `outputs/report.md`."
        )
    }

    func testAgentRedirectsFourthSerialResearchCallIntoEarlyDelegation() async throws {
        let root = try makeTempDirectory()
        let directCapture = ToolCallCapture()
        let delegatedCapture = ToolCallCapture()
        let fetches = (1...4).map { index in
            ToolCall(
                name: ToolDefinition.webFetch.name,
                argumentsJSON: ToolArguments.json(["url": "https://example.test/company-\(index)"])
            )
        }
        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "research independent company evidence in parallel",
                "workers": [
                    ["name": "Company A", "role": "collect sourced facts"],
                    ["name": "Company B", "role": "collect sourced facts"],
                ],
            ] as [String: Any])
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Final report\n\nDelegated company evidence reconciled.\n",
            ])
        )
        let read = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(fetches[0]), .tool(fetches[1]), .tool(fetches[2]), .tool(fetches[3]),
                .tool(delegated), .tool(write), .tool(read), .say("Completed the report."),
            ]),
            additionalToolDefinitions: [ToolDefinition.subagentsRun],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.webFetch.name else { return nil }
                await directCapture.record(call)
                return ToolResult(ok: false, error: "Test source unavailable")
            },
            threadToolExecutionOverride: { call, _, thread, _ in
                guard call.name == ToolDefinition.subagentsRun.name else { return nil }
                await delegatedCapture.record(call)
                return AgentThreadToolExecution(
                    thread: thread,
                    result: ToolResult(ok: true, stdout: "Independent evidence returned.")
                )
            },
            maxToolSteps: 12
        )

        let result = try await runner.send(
            "Research separate company workstreams, write outputs/report.md, and read it back.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let directCallCount = await directCapture.count
        let delegatedCallCount = await delegatedCapture.count
        XCTAssertEqual(directCallCount, 3)
        XCTAssertEqual(delegatedCallCount, 1)
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("early parallel delegation")
        })
        XCTAssertEqual(result.thread.messages.last?.content, "Completed the report.")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "# Final report\n\nDelegated company evidence reconciled.\n"
        )
    }

    func testThreadOwningToolMergesStateBeforeTheAgentContinues() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.handoffUpdate.name,
            argumentsJSON: ToolArguments.json(["summary": "Delegated state"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(call),
                .say("Continued with the durable state.")
            ]),
            additionalToolDefinitions: [ToolDefinition.handoffUpdate],
            toolExecutionOverride: { _, _ in
                ToolResult(ok: false, error: "Stateless override should not run.")
            },
            threadToolExecutionOverride: { receivedCall, _, thread, _ in
                guard receivedCall.id == call.id else { return nil }
                var updatedThread = thread
                updatedThread.title = "Thread-owned state"
                return AgentThreadToolExecution(
                    thread: updatedThread,
                    result: ToolResult(ok: true, stdout: "durable result")
                )
            }
        )

        let result = try await runner.send(
            "Run a thread-owning workflow.",
            in: ChatThread(title: "Original"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.title, "Thread-owned state")
        XCTAssertEqual(result.toolResults.first?.stdout, "durable result")
        XCTAssertEqual(result.thread.messages.last?.content, "Continued with the durable state.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.handoffUpdate.name) completed"
        })
    }

    func testAgentContinuesAcrossMultipleToolCallsInOneTurn() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "hello.txt",
                    "content": "hello world\n"
                ])
            )),
            .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "cat hello.txt"])
            )),
            .say("Created `hello.txt` and verified its contents.")
        ]))

        let result = try await runner.send(
            "write hello world to a file and verify it",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 2)
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8),
            "hello world\n"
        )
        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .tool, .tool, .assistant])
        XCTAssertEqual(result.thread.messages.last?.content, "Created `hello.txt` and verified its contents.")
        XCTAssertEqual(result.thread.events.map(\.kind), [
            .message,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .message
        ])
    }

    func testAgentLoadsSkillFromInjectedPluginResolver() async throws {
        let root = try makeTempDirectory()
        let skillDirectory = root.appendingPathComponent("plugin-skills/review")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: review
        description: Review code for correctness defects.
        ---

        # Review
        Find correctness defects first.
        """.write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let resolver = SkillResolver(roots: [
            SkillRoot(kind: .user, url: root.appendingPathComponent("plugin-skills"))
        ])
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(.init(
                    name: ToolDefinition.skillLoad.name,
                    argumentsJSON: ToolArguments.json(["name": "review"])
                )),
                .say("Loaded the review workflow.")
            ]),
            skillResolver: resolver
        )

        let result = try await runner.send(
            "Use the review skill",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertTrue(result.toolResults[0].stdout.contains("Find correctness defects first."))
        XCTAssertEqual(result.thread.messages.last?.content, "Loaded the review workflow.")
    }

    func testScreenshotAttachmentReachesNextModelStepAsHiddenToolFeedback() async throws {
        let root = try makeTempDirectory()
        let store = ImageAttachmentStore(directory: root.appendingPathComponent("attachments"))
        let screenshot = store.directory
            .appendingPathComponent("computer-use", isDirectory: true)
            .appendingPathComponent("screenshot.png")
        try FileManager.default.createDirectory(
            at: screenshot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try onePixelPNG.write(to: screenshot)
        let state = ScreenshotAwareLLMState()
        let runner = AgentRunner(
            llm: ScreenshotAwareLLMClient(state: state),
            additionalToolDefinitions: [.computerScreenshot],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.computerScreenshot.name else { return nil }
                return ToolResult(ok: true, stdout: #"{"width":1,"height":1}"#, artifacts: [screenshot.path])
            },
            toolFeedbackAttachmentProvider: { call, result in
                guard call.name == ToolDefinition.computerScreenshot.name,
                      let path = result.artifacts.first,
                      let attachment = try? store.attachmentForManagedImage(
                          at: URL(fileURLWithPath: path)
                      )
                else { return [] }
                return [attachment]
            }
        )

        let result = try await runner.send(
            "Inspect the screen and tell me what you see",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .tool, .assistant])
        let feedback = try XCTUnwrap(result.thread.messages.first { $0.role == .tool })
        XCTAssertEqual(feedback.attachments.count, 1)
        XCTAssertEqual(feedback.attachments.first?.localURL, screenshot.standardizedFileURL)
        XCTAssertEqual(result.thread.messages.last?.content, "I inspected the screenshot.")
        let sawScreenshotAttachment = await state.sawScreenshotAttachment
        XCTAssertTrue(sawScreenshotAttachment)
    }

    func testExplicitUserCommandedFileWriteCanOverwriteExistingFileInOneTurn() async throws {
        let root = try makeTempDirectory()
        try "old\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        var runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("The provider should not be needed for this explicit preflight write.")
        ]))
        runner.enablesImmediateActionPreflight = true

        let result = try await runner.send(
            "write a file at notes.txt that says new",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("notes.txt"), encoding: .utf8), "new\n")
    }

    func testModelAuthoredFileWriteToUnreadExistingFileIsBlocked() async throws {
        let root = try makeTempDirectory()
        try "old\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(.init(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "notes.txt",
                        "content": "new\n"
                    ])
                )),
                .say("The write was refused because I need to read the file first.")
            ]),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "change notes",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertFalse(result.toolResults[0].ok)
        XCTAssertTrue(result.toolResults[0].error?.contains("not read in this session") == true)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("notes.txt"), encoding: .utf8), "old\n")
    }

    func testAgentRecoversBacktickedPromisedWorkAnswerBeforeFinalizing() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I'll run `whoami` on the device."),
            .say("Done after running whoami.")
        ]))

        let result = try await runner.send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll run")
        })
        XCTAssertFalse(result.toolResults[0].stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(result.thread.messages.last?.content, "Done after running whoami.")
    }

    func testAgentRecoversNonBacktickedPromisedWorkAnswerBeforeFinalizing() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I'll run whoami on the device."),
            .say("Done after running whoami.")
        ]))

        let result = try await runner.send(
            "whoami?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll run")
        })
        XCTAssertFalse(result.toolResults[0].stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(result.thread.messages.last?.content, "Done after running whoami.")
    }

    func testAgentExecutesStandaloneFileWriteJSONWrappedAsSay() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say(##"{"type":"file.write","parameters":{"path":"result.md","content":"# Result\n\nComplete.\n"}}"##),
            .say("Created the result."),
        ]))

        let result = try await runner.send(
            "complete the current analysis",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("result.md"), encoding: .utf8),
            "# Result\n\nComplete.\n"
        )
        XCTAssertEqual(result.thread.messages.last?.content, "Created the result.")
    }

    func testAgentRecoversComplexBacktickedPromisedShellAnswerBeforeFinalizing() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .say("I'll execute `command -v definitely_missing_quillcode_binary || echo not found`."),
                .say("Done after checking the command.")
            ]),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "Do you have definitely_missing_quillcode_binary?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        guard let toolResult = result.toolResults.first else {
            return XCTFail("Expected a recovered shell result; transcript: \(result.thread.messages)")
        }
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(toolResult.ok, toolResult.error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll execute")
        })
        XCTAssertEqual(toolResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "not found")
        XCTAssertEqual(result.thread.messages.last?.content, "Done after checking the command.")
    }

    func testAgentRecoversGenericPromisedDiskCheckFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I'll check your disk usage now."),
            .say("Done after checking disk usage.")
        ]))

        let result = try await runner.send(
            "How much hd is used?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll check")
        })
        let queuedEvent = try XCTUnwrap(result.thread.events.last {
            $0.kind == .toolQueued && $0.payloadJSON != nil
        })
        let call = try JSONHelpers.decode(
            ToolCall.self,
            from: try XCTUnwrap(queuedEvent.payloadJSON)
        )
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(try arguments.requiredString("cmd"), "df -h / /Quill 2>/dev/null || df -h /")
        XCTAssertEqual(result.thread.messages.last?.content, "Done after checking disk usage.")
    }

    func testAgentRecoversGenericPromisedFileWriteFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .say("I'll create the file now."),
                .say("Created the file.")
            ]),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "Create a file named notes/hello.txt that says hello world",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll create")
        })
        let written = try String(
            contentsOf: root.appendingPathComponent("notes/hello.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "hello world\n")
        XCTAssertEqual(result.thread.messages.last?.content, "Created the file.")
    }

    func testAgentDoesNotFinalizeRepeatedPromisedWorkAnswers() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I'll check the disk usage now."),
            .say("I'll check the disk usage now."),
            .say("I'll check the disk usage now.")
        ]))

        do {
            _ = try await runner.send(
                "Please handle the setup issue.",
                in: ChatThread(mode: .auto),
                workspaceRoot: root
            )
            XCTFail("Expected repeated promised work to throw.")
        } catch AgentError.promisedWorkWithoutToolAction {
            // Expected: do not leak another fake final answer into the transcript.
        } catch {
            XCTFail("Expected promisedWorkWithoutToolAction, got \(error).")
        }
    }

    func testAgentDoesNotRetryInformationalAnswerThatMentionsCapabilities() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I can run commands, edit files, and review diffs when you ask.")
        ]))

        let result = try await runner.send(
            "what can you do?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "I can run commands, edit files, and review diffs when you ask."
        )
    }

    func testRepeatedToolCallFallsBackToSynthesizedFinalAnswer() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let runner = AgentRunner(llm: FixedToolLLMClient(call: call))

        let result = try await runner.send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        // Two-tier repeat handling (Cline learning #2): the tool runs once; the first repeat is
        // NUDGED with the result already in hand; only the next repeat synthesizes the final
        // answer. The nudge notice also names the tool, hence four matching events, not three.
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertEqual(result.thread.events.filter { $0.summary.contains("host.shell.run") }.count, 4)
        XCTAssertTrue(result.thread.events.contains { $0.summary.contains("repeated the same") })
        XCTAssertFalse(
            result.thread.messages.contains { $0.content.contains("Do not repeat that call") },
            "the nudge must not become a durable user turn"
        )
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
    }

    func testAgentRecoversProviderEmptyShellArgumentsFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: EmptyArgumentsThenSayLLMClient(
            finalMessage: "Done after checking disk usage."
        ))

        let result = try await runner.send(
            "How much hd is used?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(try queuedShellCommand(in: result), expectedDiskUsageCommand)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
        XCTAssertEqual(result.thread.messages.last?.content, "Done after checking disk usage.")
    }

    func testAgentRecoversProviderEmptyOpenClawArgumentsFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: EmptyArgumentsThenSayLLMClient(
            finalMessage: "Done after checking OpenClaw."
        ))

        let result = try await runner.send(
            "Do you have openclaw?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(try queuedShellCommand(in: result), expectedOpenClawDiscoveryCommand)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
        XCTAssertEqual(result.thread.messages.last?.content, "Done after checking OpenClaw.")
    }

    func testAgentRecoversProviderEmptyFileWriteArgumentsFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            llm: EmptyArgumentsThenSayLLMClient(finalMessage: "Created it."),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "Create a file named notes/hello.txt that says hello world",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        let written = try String(
            contentsOf: root.appendingPathComponent("notes/hello.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "hello world\n")
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
        XCTAssertEqual(result.thread.messages.last?.content, "Created it.")
    }

    func testAgentRedactsEnvironmentValuesInQueuedToolEventButExecutesRawValues() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"printf '%s' \"$QUILL_AGENT_SECRET\"","environment":{"QUILL_AGENT_SECRET":"agent-secret-value"}}"#
        )
        let runner = AgentRunner(
            llm: FixedToolLLMClient(call: call),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "run the environment command",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.first?.stdout, "agent-secret-value")
        let queued = try XCTUnwrap(result.thread.events.first { $0.kind == .toolQueued })
        let payload = try XCTUnwrap(queued.payloadJSON)
        XCTAssertTrue(payload.contains("QUILL_AGENT_SECRET"))
        XCTAssertTrue(payload.contains(ToolCall.redactedEnvironmentValue))
        XCTAssertFalse(payload.contains("agent-secret-value"))
    }

    func testBlockedRunReturnsRawHeldCallAndApprovedContinuationUsesNormalToolPath() async throws {
        let root = try makeTempDirectory()
        let rawCall = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"printf '%s' \"$QUILL_AGENT_SECRET\"","environment":{"QUILL_AGENT_SECRET":"held-secret-value"}}"#
        )
        let runner = AgentRunner(
            llm: FixedToolLLMClient(call: rawCall),
            safety: AlwaysAskingSafetyReviewer()
        )

        let blocked = try await runner.send(
            "run the environment command",
            in: ChatThread(mode: .review),
            workspaceRoot: root
        )

        let heldCall = try XCTUnwrap(blocked.pendingApprovalToolCall)
        XCTAssertTrue(heldCall.argumentsJSON.contains("held-secret-value"))
        let approvalPayload = try XCTUnwrap(
            blocked.thread.events.last(where: { $0.kind == .approvalRequested })?.payloadJSON
        )
        XCTAssertFalse(approvalPayload.contains("held-secret-value"))
        XCTAssertTrue(approvalPayload.contains(ToolCall.redactedEnvironmentValue))

        let resumed = try await runner.executeApprovedToolCall(
            heldCall,
            in: blocked.thread,
            workspaceRoot: root
        )

        XCTAssertEqual(resumed.toolResults.first?.stdout, "held-secret-value")
        XCTAssertEqual(resumed.thread.events.filter { $0.kind == .toolQueued }.count, 1)
        XCTAssertEqual(resumed.thread.events.filter { $0.kind == .toolRunning }.count, 1)
        XCTAssertEqual(resumed.thread.events.filter { $0.kind == .toolCompleted }.count, 1)
        XCTAssertEqual(resumed.thread.messages.last?.role, .tool)
    }

    func testApplyPatchRefreshesReviewDiffInSameTurn() async throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        try "old\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git add hello.txt && git commit -m initial", cwd: root)).ok)
        // The agent's tool loop refuses to patch an existing file the THREAD's session never
        // read — record the fixture file as read in this thread's edit session.
        let thread = ChatThread(mode: .auto)
        FileEditSessionGuard.session(for: thread.id).markRead(root.appendingPathComponent("hello.txt"))
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let call = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": patch])
        )
        let runner = AgentRunner(llm: FixedToolLLMClient(call: call))

        let result = try await runner.send(
            "apply this patch",
            in: thread,
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 2)
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(result.thread.events.map(\.kind), [
            .message,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            // The scripted client repeats its last call; the first repeat is nudged
            // (Cline learning #2) instead of finalizing immediately.
            .notice,
            .message
        ])
        XCTAssertEqual(result.thread.events.filter { $0.summary.contains("host.git.diff") }.count, 3)
        XCTAssertTrue(result.toolResults[1].stdout.contains("+new"), result.toolResults[1].stdout)
        XCTAssertEqual(result.thread.messages.last?.content, "Patch applied. Review the resulting diff below.")
    }
}

private struct SubagentRunToolRequest: Decodable {
    struct Worker: Decodable {
        var name: String
    }

    var workers: [Worker]
}

private actor ToolCallCapture {
    private var calls: [ToolCall] = []

    var call: ToolCall? { calls.last }
    var count: Int { calls.count }

    func record(_ call: ToolCall) {
        calls.append(call)
    }
}

private actor ScreenshotAwareLLMState {
    private var callCount = 0
    private(set) var sawScreenshotAttachment = false

    func next(thread: ChatThread) -> AgentAction {
        callCount += 1
        if callCount == 1 {
            return .tool(ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}"))
        }
        sawScreenshotAttachment = thread.messages.contains { message in
            message.role == .tool && !message.attachments.isEmpty
        }
        return .say(sawScreenshotAttachment ? "I inspected the screenshot." : "I could not see the screenshot.")
    }
}

private struct ScreenshotAwareLLMClient: LLMClient {
    let state: ScreenshotAwareLLMState

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        await state.next(thread: thread)
    }
}

private let onePixelPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)!

private struct EmptyArgumentsThenSayLLMClient: LLMClient {
    private let state: EmptyArgumentsThenSayState

    init(finalMessage: String) {
        self.state = EmptyArgumentsThenSayState(finalMessage: finalMessage)
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try await state.next()
    }
}

private actor EmptyArgumentsThenSayState {
    private var shouldThrow = true
    private let finalMessage: String

    init(finalMessage: String) {
        self.finalMessage = finalMessage
    }

    func next() throws -> AgentAction {
        if shouldThrow {
            shouldThrow = false
            throw TrustedRouterAgentError.emptyToolArguments(ToolDefinition.shellRun.name)
        }
        return .say(finalMessage)
    }
}
