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
        let repairedWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n\nRepaired content.\n",
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
            completed(call: repairedWrite, stdout: "rewrote"),
            workspaceRoot: root
        ) { _ in "rewrite" }
        XCTAssertFalse(state.needsContractAuditRepairReadback(at: "outputs/report.md"))
    }

    func testFailedShellAuditDiscoversCreatedDeliverableBeforeReturning() throws {
        let workspace = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let deliverable = workspace.appendingPathComponent("outputs/report.md")
        try FileManager.default.createDirectory(
            at: deliverable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "name,value\nalpha,1\n".write(to: deliverable, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: workspace) }

        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Create outputs/report.md with exactly two data rows. After writing, "
                + "read the saved output back and verify it."
        )
        let validator = shellCall(
            "python3 -c \"assert False\" outputs/report.md # QuillCode validator"
        )

        _ = state.recordCompletedStep(
            completed(call: validator, stdout: "expected two data rows", ok: false),
            workspaceRoot: workspace
        ) { _ in "failed-shell-audit" }

        XCTAssertTrue(state.writtenWorkspacePaths.contains("outputs/report.md"))
        XCTAssertTrue(state.unverifiedWrittenWorkspacePaths.contains("outputs/report.md"))
        XCTAssertEqual(state.pendingArtifactContractAuditPath(), "outputs/report.md")
        XCTAssertTrue(state.needsContractAuditRepairReadback(at: "outputs/report.md"))
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

    func testFailedContractAuditBlocksCosmeticallyChangedReplayUntilRepair() {
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
        let failedValidator = shellCall(
            "python3 'outputs/validate.py' 'outputs/report.md' # QuillCode validator"
        )
        let cosmeticReplay = shellCall(
            "python3 'outputs/validate.py' 'outputs/report.md'"
        )

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"), workspaceRoot: root
        ) { _ in "write" }
        _ = state.recordCompletedStep(
            completed(call: failedValidator, stdout: "wrong aggregate", ok: false),
            workspaceRoot: root
        ) { _ in "failed-audit" }
        _ = state.recordCompletedStep(
            completed(call: fileReadCall("outputs/report.md"), stdout: "# Report\n"),
            workspaceRoot: root
        ) { _ in "repair-read" }

        XCTAssertTrue(state.isUnchangedFailedContractAuditReplay(
            cosmeticReplay,
            at: "outputs/report.md"
        ))
    }

    func testFailedContractAuditReceiptSurvivesReadbackAndTypographyOnlyRewriteUntilPass() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Write outputs/report.md and run a deterministic validator against it."
        )
        let initialWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n\nReal revenue: **$6,220,578** - 35.1% x baseline.\n",
            ])
        )
        let typographyOnlyRewrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Report\n\nReal revenue: $6,220,578 \u{2014} 35.1% \u{00D7} baseline.\n",
            ])
        )
        let validator = shellCall(
            "python3 scripts/validate_report.py outputs/report.md # QuillCode validator"
        )

        _ = state.recordCompletedStep(
            completed(call: initialWrite, stdout: "wrote"), workspaceRoot: root
        ) { _ in "write" }
        _ = state.recordCompletedStep(
            completed(
                call: validator,
                stdout: "VALIDATION FAILED\n - 2025: real $6,223,810 not found",
                ok: false
            ),
            workspaceRoot: root
        ) { _ in "failed-audit" }

        XCTAssertTrue(state.failedContractAuditReceipt(at: "./outputs/report.md")?.contains(
            "2025: real $6,223,810 not found"
        ) == true)

        _ = state.recordCompletedStep(
            completed(call: fileReadCall("outputs/report.md"), stdout: "saved artifact"),
            workspaceRoot: root
        ) { _ in "read" }
        _ = state.recordCompletedStep(
            completed(call: typographyOnlyRewrite, stdout: "rewrote"), workspaceRoot: root
        ) { _ in "typography-only-rewrite" }

        XCTAssertTrue(state.isUnchangedFailedContractAuditReplay(
            validator,
            at: "outputs/report.md"
        ))
        XCTAssertNotNil(state.failedContractAuditReceipt(at: "outputs/report.md"))

        _ = state.recordCompletedStep(
            completed(call: validator, stdout: "PASS"), workspaceRoot: root
        ) { _ in "passed-audit" }
        XCTAssertNil(state.failedContractAuditReceipt(at: "outputs/report.md"))
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

    func testStructuredDirectFetchSuppressesForcedDelegationSignal() {
        var state = AgentRunLoopState()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/series"])
        )
        let table = """
        | Year | Jan | Feb | Mar |
        | --- | --- | --- | --- |
        | 2023 | 299.170 | 300.840 | 301.836 |
        | 2024 | 308.417 | 310.326 | 312.332 |
        | 2025 | 317.671 | 319.082 | 319.799 |
        """

        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: table),
            workspaceRoot: root
        ) { _ in "fetch" }

        XCTAssertTrue(state.hasSubstantialStructuredDirectResearchEvidence)
    }

    func testThinDirectFetchDoesNotSuppressForcedDelegationSignal() {
        var state = AgentRunLoopState()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/series"])
        )

        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: "Official figure: 333.952"),
            workspaceRoot: root
        ) { _ in "fetch" }

        XCTAssertFalse(state.hasSubstantialStructuredDirectResearchEvidence)
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

    func testMixedSourceRunRetainsRequiredLocalRowsBesideLiveResearch() throws {
        var state = AgentRunLoopState()
        let prompt = """
        Read every applicable source directly before acting.
        For this task the required inputs are: `inputs/context.md`, `inputs/records.csv`.
        Research CPI and write outputs/report.md with a deterministic validator.
        """
        state.seedArtifactVerification(userMessage: prompt)
        state.seedSourceGrounding(userMessage: prompt)

        let read = ToolCall(
            name: ToolDefinition.fileReadMany.name,
            argumentsJSON: ToolArguments.json([
                "paths": ["inputs/context.md", "inputs/records.csv"],
            ])
        )
        _ = state.recordCompletedStep(
            completed(
                call: read,
                stdout: """
                ## File 1: inputs/context.md
                Use the records as authoritative.

                ## File 2: inputs/records.csv
                fiscal_year,nominal_revenue_usd
                2023,4200000
                2024,5100000
                2025,6000000
                """
            ),
            workspaceRoot: root
        ) { _ in "required-read" }

        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/cpi"])
        )
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: "2026 June CPI: 333.952"),
            workspaceRoot: root
        ) { _ in "fetch" }

        let localReceipt = try XCTUnwrap(state.latestRequiredInputEvidenceReceipt)
        let combined = try XCTUnwrap(state.latestAuthoritativeEvidenceReceipt)
        XCTAssertTrue(localReceipt.contains("2023,4200000"))
        XCTAssertTrue(localReceipt.contains("exact successful file-read results"))
        XCTAssertTrue(combined.contains("2025,6000000"))
        XCTAssertTrue(combined.contains("2026 June CPI: 333.952"))
        XCTAssertEqual(
            state.requiredStructuredInputWorkspacePaths,
            Set(["inputs/records.csv"])
        )
    }

    func testResearchEvidenceLedgerPreservesExactFetchAcrossLaterWorkerOutput() throws {
        var state = AgentRunLoopState()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: "2025 monthly values: 317.671, 319.082, 324.054"),
            workspaceRoot: root
        ) { _ in "fetch" }

        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "verify official data",
                "workers": [["name": "Verifier", "role": "verify the source"]],
            ] as [String: Any])
        )
        _ = state.recordCompletedStep(
            completed(call: delegated, stdout: "Worker stopped at its step limit."),
            workspaceRoot: root
        ) { _ in "delegated" }

        let receipt = try XCTUnwrap(state.latestResearchEvidenceReceipt)
        XCTAssertTrue(receipt.contains("317.671, 319.082, 324.054"))
        XCTAssertTrue(receipt.contains("Worker stopped at its step limit."))
        XCTAssertTrue(receipt.contains("next successful research observation"))
    }

    func testResearchEvidenceLedgerEvictsWeakestObservationAtBound() throws {
        var state = AgentRunLoopState()
        let observations = [
            "official observation 1 " + String(repeating: "verified ", count: 80),
            "official observation 2",
            "official observation 3 " + String(repeating: "detail ", count: 20),
            "official observation 4 " + String(repeating: "detail ", count: 30),
        ]
        for (offset, observation) in observations.enumerated() {
            let fetch = ToolCall(
                name: ToolDefinition.webFetch.name,
                argumentsJSON: ToolArguments.json([
                    "url": "https://example.gov/data/\(offset + 1)",
                ])
            )
            _ = state.recordCompletedStep(
                completed(call: fetch, stdout: observation),
                workspaceRoot: root
            ) { _ in "fetch-\(offset + 1)" }
        }

        let receipt = try XCTUnwrap(state.latestResearchEvidenceReceipt)
        XCTAssertTrue(receipt.contains("official observation 1"))
        XCTAssertFalse(receipt.contains("official observation 2"))
        XCTAssertTrue(receipt.contains("official observation 3"))
        XCTAssertTrue(receipt.contains("official observation 4"))
    }

    func testShellHTTPErrorDoesNotDisplaceSuccessfulFetchedEvidence() throws {
        var state = AgentRunLoopState()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        _ = state.recordCompletedStep(
            completed(
                call: fetch,
                stdout: "Year | Jan | Feb\n2026 | 325.252 | 333.952"
            ),
            workspaceRoot: root
        ) { _ in "fetch" }

        for version in 1...4 {
            let shell = ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "curl -s https://api.example.gov/v\(version)/data",
                ])
            )
            _ = state.recordCompletedStep(
                completed(
                    call: shell,
                    stdout: "<title>HTTP Status 404 - Not Found</title>"
                ),
                workspaceRoot: root
            ) { _ in "shell-\(version)" }
        }

        let receipt = try XCTUnwrap(state.latestResearchEvidenceReceipt)
        XCTAssertTrue(receipt.contains("333.952"))
        XCTAssertFalse(receipt.contains("HTTP Status 404"))
    }

    func testPassingValidatorDoesNotAuditArtifactThatContradictsResearchEvidence() throws {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(userMessage: """
        Calculate every row, run a deterministic validator, and save outputs/report.md.
        """)
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        _ = state.recordCompletedStep(
            completed(
                call: fetch,
                stdout: """
                Year | Jan | Feb | Mar
                2025 | 317.671 | 319.082 | 324.054
                2026 | 325.252 | 326.785 | 333.952
                """
            ),
            workspaceRoot: root
        ) { _ in "fetch" }

        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": """
                # Report

                The numeric values were truncated, so I cannot compute the requested result.
                """,
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        let audit = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 validate.py outputs/report.md # validator assertions",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: audit, stdout: "PASS: no unsupported values"),
            workspaceRoot: root
        ) { _ in "audit" }

        XCTAssertEqual(state.pendingArtifactContractAuditPath(), "outputs/report.md")
        XCTAssertTrue(state.needsContractAuditRepairReadback(at: "outputs/report.md"))
        XCTAssertTrue(
            state.failedContractAuditReceipt(at: "outputs/report.md")?
                .contains("VALIDATION REJECTED") == true
        )
    }

    func testResearchEvidenceLedgerKeepsStrongestObservationForRepeatedURL() throws {
        var state = AgentRunLoopState()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        _ = state.recordCompletedStep(
            completed(
                call: fetch,
                stdout: "Year | Jan | Feb | Mar\n2026 | 325.252 | 326.785 | 333.952"
            ),
            workspaceRoot: root
        ) { _ in "complete-fetch" }
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: "2026 | 325.252"),
            workspaceRoot: root
        ) { _ in "short-fetch" }

        let receipt = try XCTUnwrap(state.latestResearchEvidenceReceipt)
        XCTAssertTrue(receipt.contains("333.952"))
        XCTAssertEqual(receipt.components(separatedBy: "Successful host.web.fetch observation").count, 2)
    }

    func testSemanticAPIFailureDoesNotBecomeSuccessfulResearchEvidence() {
        var state = AgentRunLoopState()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://api.example.gov/data"])
        )
        _ = state.recordCompletedStep(
            completed(
                call: fetch,
                stdout: #"Fetched https://api.example.gov/data (HTTP 200).\n\n{"status":"REQUEST_NOT_PROCESSED","message":"threshold"}"#
            ),
            workspaceRoot: root
        ) { _ in "semantic-failure" }

        XCTAssertNil(state.latestResearchEvidenceReceipt)
        XCTAssertFalse(state.didFetchSuccessfully)
    }

    func testSearchSnippetsDoNotDisplaceFetchedResearchEvidence() throws {
        var state = AgentRunLoopState()
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: "official fetched value: 333.952"),
            workspaceRoot: root
        ) { _ in "fetch" }

        let search = ToolCall(
            name: ToolDefinition.webSearch.name,
            argumentsJSON: ToolArguments.json(["query": "example CPI"])
        )
        _ = state.recordCompletedStep(
            completed(call: search, stdout: "unverified snippet says 999.999"),
            workspaceRoot: root
        ) { _ in "search" }

        let receipt = try XCTUnwrap(state.latestResearchEvidenceReceipt)
        XCTAssertTrue(receipt.contains("official fetched value: 333.952"))
        XCTAssertFalse(receipt.contains("unverified snippet"))
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

    func testRunLoopRejectsValidationWhenDraftContradictsRetainedPeriodTable() throws {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research and write outputs/report.md with a deterministic validator."
        )
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        let table = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | HALF1 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | | 330.724 |
        """
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: table),
            workspaceRoot: root
        ) { _ in "fetch" }

        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "The latest monthly benchmark is June 2026, index 326.785.",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        let issue = try XCTUnwrap(
            state.authoritativeEvidenceContradiction(at: "./outputs/report.md")
        )
        XCTAssertTrue(issue.contains("Jun 2026"))
        XCTAssertTrue(issue.contains("333.952"))
    }

    func testSuccessfulPatchRefreshesAuthoritativeArtifactText() throws {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research and write outputs/report.md with a deterministic validator."
        )
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.gov/data"])
        )
        let table = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | HALF1 |
        | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | 330.724 |
        """
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: table),
            workspaceRoot: root
        ) { _ in "fetch" }

        let outputs = root.appendingPathComponent("outputs")
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
        let report = outputs.appendingPathComponent("report.md")
        let incorrect = "The latest monthly benchmark is June 2026, index 326.785.\n"
        try incorrect.write(to: report, atomically: true, encoding: .utf8)
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": incorrect,
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }
        XCTAssertNotNil(state.authoritativeEvidenceContradiction(at: "outputs/report.md"))

        try "The latest monthly benchmark is June 2026, index 333.952.\n".write(
            to: report,
            atomically: true,
            encoding: .utf8
        )
        let patch = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": """
            diff --git a/outputs/report.md b/outputs/report.md
            --- a/outputs/report.md
            +++ b/outputs/report.md
            @@ -1 +1 @@
            -The latest monthly benchmark is June 2026, index 326.785.
            +The latest monthly benchmark is June 2026, index 333.952.
            """])
        )
        _ = state.recordCompletedStep(
            completed(call: patch, stdout: "Patch applied."),
            workspaceRoot: root
        ) { _ in "patch" }

        XCTAssertNil(state.authoritativeEvidenceContradiction(at: "outputs/report.md"))
        XCTAssertEqual(state.pendingArtifactContractAuditPath(), "outputs/report.md")
    }

    func testNarrowPatchDoesNotPromoteCheckpointArtifactToFinal() throws {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research CPI, write outputs/report.md, and run a deterministic validator."
        )
        let outputs = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputs) }

        // Use this unique directory as the workspace while retaining the task-named relative path.
        let deliverableDirectory = outputs.appendingPathComponent("outputs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: deliverableDirectory,
            withIntermediateDirectories: true
        )
        let report = deliverableDirectory.appendingPathComponent("report.md")
        let checkpoint = """
        # CPI Revenue Restatement - Checkpoint Draft

        **Status:** Work in progress.

        2025 CPI basis: 322.115
        """
        try checkpoint.write(to: report, atomically: true, encoding: .utf8)
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": checkpoint,
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: outputs
        ) { _ in "checkpoint" }

        XCTAssertEqual(state.provisionalWrittenTextPaths, ["outputs/report.md"])
        XCTAssertEqual(state.pendingBoundedRunFinalizationPath(), "outputs/report.md")
        XCTAssertEqual(
            state.boundedRunFinalizationPhase(at: "outputs/report.md"),
            .synthesize
        )

        let patched = checkpoint.replacingOccurrences(of: "322.115", with: "321.943")
        try patched.write(to: report, atomically: true, encoding: .utf8)
        let patch = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": """
            diff --git a/outputs/report.md b/outputs/report.md
            --- a/outputs/report.md
            +++ b/outputs/report.md
            @@ -5 +5 @@
            -2025 CPI basis: 322.115
            +2025 CPI basis: 321.943
            """])
        )
        _ = state.recordCompletedStep(
            completed(call: patch, stdout: "Patch applied."),
            workspaceRoot: outputs
        ) { _ in "patch" }

        XCTAssertEqual(state.provisionalWrittenTextPaths, ["outputs/report.md"])
        XCTAssertEqual(
            state.boundedRunFinalizationPhase(at: "outputs/report.md"),
            .synthesize
        )

        let final = "# CPI Revenue Restatement\n\n2025 CPI basis: 321.943. Analysis complete.\n"
        let finalWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": final,
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: finalWrite, stdout: "rewrote"),
            workspaceRoot: outputs
        ) { _ in "final" }

        XCTAssertTrue(state.provisionalWrittenTextPaths.isEmpty)
        XCTAssertNil(state.pendingBoundedRunFinalizationPath())
        XCTAssertEqual(state.pendingArtifactContractAuditPath(), "outputs/report.md")
    }

    func testExplicitDraftRequestAllowsDraftHeadingToAdvance() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Create an initial draft report at outputs/report.md."
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Draft Report\n\nInitial recommendation.\n",
            ])
        )

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        XCTAssertTrue(state.provisionalWrittenTextPaths.isEmpty)
        XCTAssertNil(state.pendingBoundedRunFinalizationPath())
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
