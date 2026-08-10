import XCTest
import Foundation
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentRunLoopStateTests: XCTestCase {
    private var root: URL { FileManager.default.temporaryDirectory }

    func testRepeatedCompletionMatchesOnlyTheLastExactCall() {
        var state = AgentRunLoopState()
        let call = shellCall("whoami")
        let completion = completed(call: call, stdout: "quill")

        state.baselineWorkspaceStateIfNeeded(workspaceRoot: root) { _ in "before" }
        _ = state.recordCompletedStep(completion, workspaceRoot: root) { _ in "after" }

        XCTAssertEqual(state.repeatedCompletion(for: call)?.result.stdout, "quill")
        XCTAssertNil(state.repeatedCompletion(for: shellCall("pwd")))
        XCTAssertEqual(state.toolResults.map(\.stdout), ["quill"])
        XCTAssertEqual(state.latestCompletion?.call, call)
    }

    func testNoProgressFlailEscalatesOnlyAfterAssessmentRecord() {
        var state = AgentRunLoopState()
        let call = fileReadCall("same.txt")
        state.baselineWorkspaceStateIfNeeded(workspaceRoot: root) { _ in "constant" }

        XCTAssertEqual(recordNoProgress(call, in: &state), .none)
        XCTAssertEqual(recordNoProgress(call, in: &state), .none)

        guard case .suspected(let suspectedReason) = recordNoProgress(call, in: &state) else {
            return XCTFail("expected suspected flail after three no-progress turns")
        }
        XCTAssertEqual(suspectedReason.kind, .repeatedActionNoProgress)

        XCTAssertTrue(state.recordFlailAssessmentIfNeeded())
        XCTAssertFalse(state.recordFlailAssessmentIfNeeded())

        guard case .confirmed(let confirmedReason) = recordNoProgress(call, in: &state) else {
            return XCTFail("expected confirmed flail after the assessment has been recorded")
        }
        XCTAssertEqual(confirmedReason.kind, .repeatedActionNoProgress)
    }

    func testDefaultWorkspaceSignatureShortCircuitsNonGitDirectories() throws {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(AgentRunner.defaultWorkspaceStateSignature(directory), "no-git")
    }

    func testWriteNeedsLaterSuccessfulReadAndRewriteRearmsVerification() {
        var state = AgentRunLoopState()
        let write = ToolCall(
            name: "host.file.write",
            argumentsJSON: ToolArguments.json(["path": "./outputs/report.md", "content": "draft"])
        )
        let read = fileReadCall("outputs/report.md")
        state.baselineWorkspaceStateIfNeeded(workspaceRoot: root) { _ in "before" }

        _ = state.recordCompletedStep(completed(call: write, stdout: "wrote"), workspaceRoot: root) { _ in "write" }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/report.md"])

        _ = state.recordCompletedStep(
            completed(call: read, stdout: "missing", ok: false),
            workspaceRoot: root
        ) { _ in "write" }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/report.md"])

        _ = state.recordCompletedStep(completed(call: read, stdout: "draft"), workspaceRoot: root) { _ in "write" }
        XCTAssertTrue(state.unverifiedWrittenWorkspacePaths.isEmpty)

        _ = state.recordCompletedStep(completed(call: write, stdout: "rewrote"), workspaceRoot: root) { _ in "rewrite" }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/report.md"])
    }

    func testBoundedFinalizationTargetsWrittenDeliverablePendingReadback() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Write outputs/report.md and verify the saved output by reading it back."
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n\nComplete.\n",
            ])
        )

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        XCTAssertNil(state.pendingBoundedRunFinalizationPath())
        XCTAssertEqual(state.boundedRunFinalizationTargetPath(), "outputs/report.md")
        XCTAssertEqual(
            state.boundedRunFinalizationPhase(at: "outputs/report.md"),
            .readback
        )
    }

    func testRequestedReadbackDoesNotIncludeHelperWrites() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Write outputs/report.md and verify the saved output by reading it back."
        )
        let deliverableWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n",
            ])
        )
        let helperWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": "assert True\n",
            ])
        )

        _ = state.recordCompletedStep(
            completed(call: deliverableWrite, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "deliverable" }
        _ = state.recordCompletedStep(
            completed(call: helperWrite, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "helper" }

        XCTAssertEqual(
            state.unverifiedWrittenWorkspacePaths,
            ["outputs/report.md", "scripts/validate_report.py"]
        )
        XCTAssertEqual(state.pendingArtifactReadbackWorkspacePaths, ["outputs/report.md"])
    }

    func testFailedContractAuditAllowsExactlyOneRepairReadUntilRewrite() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Write outputs/report.md and run a deterministic validator against it."
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n",
            ])
        )
        let validator = shellCall(
            "python3 -c \"assert False\" outputs/report.md # QuillCode validator"
        )
        let read = fileReadCall("outputs/report.md")

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }
        _ = state.recordCompletedStep(
            completed(call: validator, stdout: "failed", ok: false),
            workspaceRoot: root
        ) { _ in "failed-audit" }

        XCTAssertTrue(state.needsContractAuditRepairReadback(at: "./outputs/report.md"))

        _ = state.recordCompletedStep(
            completed(call: read, stdout: "# Report\n"),
            workspaceRoot: root
        ) { _ in "read" }
        XCTAssertFalse(state.needsContractAuditRepairReadback(at: "outputs/report.md"))

        _ = state.recordCompletedStep(
            completed(call: validator, stdout: "failed again", ok: false),
            workspaceRoot: root
        ) { _ in "failed-audit-again" }
        XCTAssertTrue(state.needsContractAuditRepairReadback(at: "outputs/report.md"))

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "rewrote"),
            workspaceRoot: root
        ) { _ in "rewrite" }
        XCTAssertFalse(state.needsContractAuditRepairReadback(at: "outputs/report.md"))
    }

    func testFailedContractAuditBlocksUnchangedReplayUntilValidatorHelperChanges() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Write outputs/report.md and run a deterministic validator against it."
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n",
            ])
        )
        let helper = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": "assert 'Report' in open('outputs/report.md').read()",
            ])
        )
        let repairedHelper = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "scripts/validate_report.py",
                "content": "assert '# Report' in open('outputs/report.md').read()\nprint('PASS')",
            ])
        )
        let validator = shellCall(
            "python3 scripts/validate_report.py outputs/report.md # QuillCode validator"
        )

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"), workspaceRoot: root
        ) { _ in "write" }
        _ = state.recordCompletedStep(
            completed(call: helper, stdout: "wrote"), workspaceRoot: root
        ) { _ in "helper" }
        _ = state.recordCompletedStep(
            completed(call: validator, stdout: "bad parser", ok: false), workspaceRoot: root
        ) { _ in "failed-audit" }

        XCTAssertTrue(state.isUnchangedFailedContractAuditReplay(validator, at: "outputs/report.md"))

        _ = state.recordCompletedStep(
            completed(call: helper, stdout: "wrote same helper"), workspaceRoot: root
        ) { _ in "same-helper" }
        XCTAssertTrue(state.isUnchangedFailedContractAuditReplay(validator, at: "outputs/report.md"))

        _ = state.recordCompletedStep(
            completed(call: repairedHelper, stdout: "wrote repaired helper"), workspaceRoot: root
        ) { _ in "repaired-helper" }
        XCTAssertFalse(state.isUnchangedFailedContractAuditReplay(validator, at: "outputs/report.md"))
    }

    func testRenderedChartNeedsLaterSuccessfulRead() {
        var state = AgentRunLoopState()
        let render = ToolCall(
            name: ToolDefinition.chartRender.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.png",
                "categories": ["Q1"],
                "series": ["East": "10"],
            ] as [String: Any])
        )
        let read = fileReadCall("outputs/revenue.png")
        state.baselineWorkspaceStateIfNeeded(workspaceRoot: root) { _ in "before" }

        _ = state.recordCompletedStep(completed(call: render, stdout: "rendered"), workspaceRoot: root) { _ in
            "render"
        }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/revenue.png"])

        _ = state.recordCompletedStep(completed(call: read, stdout: "PNG image"), workspaceRoot: root) { _ in
            "render"
        }
        XCTAssertTrue(state.unverifiedWrittenWorkspacePaths.isEmpty)
    }

    func testBatchReadVerifiesEveryWrittenPath() {
        var state = AgentRunLoopState()
        let firstWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/first.md", "content": "first"])
        )
        let secondWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/second.md", "content": "second"])
        )
        let batchRead = ToolCall(
            name: ToolDefinition.fileReadMany.name,
            argumentsJSON: ToolArguments.json(["paths": ["outputs/first.md", "outputs/second.md"]])
        )

        _ = state.recordCompletedStep(completed(call: firstWrite, stdout: "wrote"), workspaceRoot: root) { _ in
            "first"
        }
        _ = state.recordCompletedStep(completed(call: secondWrite, stdout: "wrote"), workspaceRoot: root) { _ in
            "second"
        }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/first.md", "outputs/second.md"])

        _ = state.recordCompletedStep(completed(call: batchRead, stdout: "first\nsecond"), workspaceRoot: root) { _ in
            "second"
        }

        XCTAssertTrue(state.unverifiedWrittenWorkspacePaths.isEmpty)
        XCTAssertEqual(state.successfullyReadWorkspacePaths, ["outputs/first.md", "outputs/second.md"])
    }

    func testResearchCheckpointArmsAfterSuccessfulWebWorkAndClearsOnNamedDraft() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )

        for index in 0..<AgentResearchCheckpointGate.minimumPreDraftResearchWeight {
            let search = ToolCall(
                name: ToolDefinition.webSearch.name,
                argumentsJSON: ToolArguments.json(["query": "competitor \(index)"])
            )
            _ = state.recordCompletedStep(
                completed(call: search, stdout: "result \(index)"),
                workspaceRoot: root
            ) { _ in "search-\(index)" }
        }

        XCTAssertEqual(
            state.pendingResearchCheckpointPath(
                minimumResearchWeight: AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            ),
            "outputs/revenue.html"
        )

        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Checkpoint</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        XCTAssertNil(state.pendingResearchCheckpointPath(minimumResearchWeight: 1))
        XCTAssertEqual(state.researchPressureWeightBeforeDraft, 0)
    }

    func testFailedWebWorkArmsResearchCheckpointBeforeContextIsExhausted() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(userMessage: "Research and write outputs/report.md.")
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.com"])
        )

        for _ in 0..<AgentResearchCheckpointGate.minimumPreDraftResearchWeight {
            _ = state.recordCompletedStep(
                completed(call: fetch, stdout: "failed", ok: false),
                workspaceRoot: root
            ) { _ in "constant" }
        }

        XCTAssertEqual(
            state.pendingResearchCheckpointPath(
                minimumResearchWeight: AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            ),
            "outputs/report.md"
        )
    }

    func testShellBrowsingConsumesResearchBudgetAndRetainsLatestEvidence() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(userMessage: "Research and write outputs/report.md.")

        for index in 0..<AgentResearchCheckpointGate.minimumPreDraftResearchWeight {
            let call = ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "curl -s https://example.gov/series/\(index)",
                ])
            )
            _ = state.recordCompletedStep(
                completed(call: call, stdout: "official row \(index): 333.952"),
                workspaceRoot: root
            ) { _ in "shell-research-\(index)" }
        }

        XCTAssertEqual(
            state.pendingResearchCheckpointPath(
                minimumResearchWeight: AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            ),
            "outputs/report.md"
        )
        XCTAssertTrue(state.latestResearchEvidenceReceipt?.contains("official row 7") == true)
        XCTAssertTrue(state.latestResearchEvidenceReceipt?.contains("host.shell.run") == true)
        XCTAssertTrue(state.didFetchSuccessfully)
    }

    func testDelegatedResearchContributesToPreDraftCheckpoint() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )

        for index in 0..<(AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            - AgentResearchCheckpointGate.delegatedResearchWeight) {
            let search = ToolCall(
                name: ToolDefinition.webSearch.name,
                argumentsJSON: ToolArguments.json(["query": "competitor \(index)"])
            )
            _ = state.recordCompletedStep(
                completed(call: search, stdout: "result \(index)"),
                workspaceRoot: root
            ) { _ in "search-\(index)" }
        }

        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "research competitors",
                "workers": [["name": "A", "role": "research A"]],
            ] as [String: Any])
        )
        _ = state.recordCompletedStep(
            completed(call: delegated, stdout: "verified evidence"),
            workspaceRoot: root
        ) { _ in "delegated" }

        XCTAssertEqual(
            state.pendingResearchCheckpointPath(
                minimumResearchWeight: AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            ),
            "outputs/revenue.html"
        )
    }

    func testLatestSuccessfulResearchEvidenceReceiptIsBoundedAndSurvivesWrites() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research official figures and write outputs/report.md."
        )
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        let evidence = "official figure: 333.952\n" + String(repeating: "x", count: 15_000)
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: evidence),
            workspaceRoot: root
        ) { _ in "fetch" }

        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n\nDraft.\n",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        let receipt = try? XCTUnwrap(state.latestResearchEvidenceReceipt)
        XCTAssertTrue(receipt?.contains("Successful host.web.fetch observation") == true)
        XCTAssertTrue(receipt?.contains("official figure: 333.952") == true)
        XCTAssertTrue(receipt?.contains("middle of evidence receipt omitted") == true)
        XCTAssertLessThanOrEqual(receipt?.count ?? .max, 12_100)
    }

    func testVisibleBrowserExtractionBecomesLatestResearchEvidenceReceipt() throws {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research official figures and write outputs/report.md."
        )
        let script = ToolCall(
            name: ToolDefinition.browserScript.name,
            argumentsJSON: ToolArguments.json(["source": "extractRows()"])
        )
        let table = "2025|317.671|319.082|-(X)|324.054\n2026|325.252|333.952"
        let output = try JSONHelpers.encodePretty(BrowserScriptToolOutput(
            title: "Official series",
            url: "https://example.gov/series",
            value: table
        ))

        _ = state.recordCompletedStep(
            completed(call: script, stdout: output),
            workspaceRoot: root
        ) { _ in "browser-script" }

        let receipt = try XCTUnwrap(state.latestResearchEvidenceReceipt)
        XCTAssertTrue(receipt.contains("Successful host.browser.script observation"))
        XCTAssertTrue(receipt.contains("https://example.gov/series"))
        XCTAssertTrue(receipt.contains(table))
        XCTAssertTrue(state.didFetchSuccessfully)
        XCTAssertEqual(state.researchPressureWeightBeforeDraft, 1)
    }

    func testEmptyVisibleBrowserExtractionDoesNotReplaceUsefulReceipt() throws {
        var state = AgentRunLoopState()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: "official figure: 333.952"),
            workspaceRoot: root
        ) { _ in "fetch" }

        let script = ToolCall(
            name: ToolDefinition.browserScript.name,
            argumentsJSON: ToolArguments.json(["source": "missingValue()"])
        )
        let output = try JSONHelpers.encodePretty(BrowserScriptToolOutput(
            title: "Official series",
            url: "https://example.gov/series",
            value: ""
        ))
        _ = state.recordCompletedStep(
            completed(call: script, stdout: output),
            workspaceRoot: root
        ) { _ in "empty-browser-script" }

        XCTAssertTrue(state.latestResearchEvidenceReceipt?.contains("333.952") == true)
    }

    func testForcedResearchCheckpointRequiresWebWorkAndFinalRewrite() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )
        state.expectResearchCheckpoint(at: "outputs/revenue.html")

        let checkpoint = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Checkpoint with evidence gaps</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: checkpoint, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "checkpoint" }

        XCTAssertEqual(state.pendingResearchContinuationPath(), "outputs/revenue.html")
        XCTAssertFalse(state.didResumeResearch(afterCheckpointAt: "outputs/revenue.html"))

        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.com/revenue"])
        )
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: "revenue evidence"),
            workspaceRoot: root
        ) { _ in "fetch" }

        XCTAssertTrue(state.didResumeResearch(afterCheckpointAt: "outputs/revenue.html"))
        XCTAssertEqual(state.pendingResearchContinuationPath(), "outputs/revenue.html")

        let finalWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Complete final comparison</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: finalWrite, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "final" }

        XCTAssertNil(state.pendingResearchContinuationPath())
        XCTAssertEqual(state.successfulResearchStepsAfterCheckpoint, 0)
    }

    func testDelegatedResearchAfterCheckpointRequiresImmediateSynthesis() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )
        state.expectResearchCheckpoint(at: "outputs/revenue.html")
        let checkpoint = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Checkpoint</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: checkpoint, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "checkpoint" }

        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "research competitors",
                "workers": [["name": "A", "role": "research A"]],
            ] as [String: Any])
        )
        _ = state.recordCompletedStep(
            completed(call: delegated, stdout: "verified evidence"),
            workspaceRoot: root
        ) { _ in "delegated" }
        XCTAssertEqual(
            state.successfulResearchStepsAfterCheckpoint,
            AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
        )

        XCTAssertEqual(
            state.pendingResearchFinalizationPath(
                minimumResearchSteps: AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
            ),
            "outputs/revenue.html"
        )
    }

    func testOrdinaryDraftDoesNotArmResearchContinuation() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(userMessage: "Write outputs/report.md.")
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "Complete report",
            ])
        )

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        XCTAssertNil(state.pendingResearchContinuationPath())
    }

    func testDelegatedResearchAfterWrittenArtifactRequiresImmediateResynthesis() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Initial comparison</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "research competitors",
                "workers": [["name": "A", "role": "research A"]],
            ] as [String: Any])
        )
        _ = state.recordCompletedStep(
            completed(call: delegated, stdout: "verified evidence"),
            workspaceRoot: root
        ) { _ in "delegated" }

        XCTAssertEqual(state.pendingResearchContinuationPath(), "outputs/revenue.html")
        XCTAssertTrue(state.didResumeResearch(afterCheckpointAt: "outputs/revenue.html"))
        XCTAssertEqual(state.researchStaleWorkspacePaths, ["outputs/revenue.html"])
        XCTAssertEqual(
            state.pendingResearchFinalizationPath(
                minimumResearchSteps: AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
            ),
            "outputs/revenue.html"
        )

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "rewrote"),
            workspaceRoot: root
        ) { _ in "rewrite" }
        XCTAssertNil(state.pendingResearchContinuationPath())
        XCTAssertTrue(state.researchStaleWorkspacePaths.isEmpty)
    }

    func testDirectResearchAfterOrdinaryDraftRequiresPeriodicSynthesis() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Initial comparison</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.com/revenue"])
        )
        for index in 0..<AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps {
            _ = state.recordCompletedStep(
                completed(call: fetch, stdout: "evidence \(index)"),
                workspaceRoot: root
            ) { _ in "fetch-\(index)" }
        }

        XCTAssertEqual(
            state.pendingResearchFinalizationPath(
                minimumResearchSteps: AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
            ),
            "outputs/revenue.html"
        )
        XCTAssertEqual(
            state.researchPressureAfterLatestDraftByPath["outputs/revenue.html"],
            AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
        )

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "rewrote"),
            workspaceRoot: root
        ) { _ in "rewrite" }
        XCTAssertNil(state.pendingResearchFinalizationPath(minimumResearchSteps: 1))
        XCTAssertEqual(state.researchPressureAfterLatestDraftByPath["outputs/revenue.html"], 0)
        XCTAssertEqual(
            state.totalResearchPressureAfterFirstDraftByPath["outputs/revenue.html"],
            AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
        )
    }

    func testFailedPostDraftResearchConsumesCumulativeBudget() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(userMessage: "Research and write outputs/report.md.")
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "Initial report",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.com/missing"])
        )

        for index in 0..<AgentResearchCheckpointGate.maximumPostDraftResearchWeight {
            _ = state.recordCompletedStep(
                completed(call: fetch, stdout: "failed", ok: false),
                workspaceRoot: root
            ) { _ in "failed-\(index)" }
        }

        XCTAssertEqual(
            state.exhaustedResearchBudgetPath(
                maximumResearchWeight: AgentResearchCheckpointGate.maximumPostDraftResearchWeight
            ),
            "outputs/report.md"
        )
    }

    func testSuccessfulDelegationIsCountedAndWrittenDeliverableCanBeMarkedStale() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )
        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "research competitors",
                "workers": [["name": "A", "role": "research A"]],
            ] as [String: Any])
        )
        _ = state.recordCompletedStep(
            completed(call: delegated, stdout: "verified evidence"),
            workspaceRoot: root
        ) { _ in "delegated" }
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Comparison</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        XCTAssertEqual(state.successfulDelegatedResearchBatchCount, 1)
        XCTAssertEqual(state.writtenNamedTextDeliverablePath(), "outputs/revenue.html")
        state.requireResearchRefresh(at: "./outputs/revenue.html")
        XCTAssertEqual(state.researchStaleWorkspacePaths, ["outputs/revenue.html"])
    }

    private func recordNoProgress(
        _ call: ToolCall,
        in state: inout AgentRunLoopState
    ) -> FlailVerdict {
        state.recordCompletedStep(
            completed(call: call, stdout: "same"),
            workspaceRoot: root
        ) { _ in "constant" }
    }

    private func shellCall(_ command: String) -> ToolCall {
        ToolCall(
            name: "host.shell.run",
            argumentsJSON: ToolArguments.json(["cmd": command])
        )
    }

    private func fileReadCall(_ path: String) -> ToolCall {
        ToolCall(
            name: "host.file.read",
            argumentsJSON: ToolArguments.json(["path": path])
        )
    }

    private func completed(call: ToolCall, stdout: String, ok: Bool = true) -> AgentToolStepCompletion {
        let result = ToolResult(ok: ok, stdout: stdout)
        return AgentToolStepCompletion(
            call: call,
            result: result,
            followUpReviewResult: nil,
            toolResults: [result]
        )
    }
}
