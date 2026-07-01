import XCTest

final class ParityWorkspacePlaywrightRealWorldSpecGateTests: QuillCodeParityTestCase {
    func testPlaywrightRealWorldActionFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let actionSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("real-world-actions.spec.ts"),
            encoding: .utf8
        )
        let actionEvidenceText = try String(
            contentsOf: testRoot.appendingPathComponent("real-world-action-evidence.ts"),
            encoding: .utf8
        )
        let actionContractText = "\(actionSpecText)\n\(actionEvidenceText)"
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let artifactSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("artifacts.spec.ts"),
            encoding: .utf8
        )
        let actionFlowNames = [
            "runs natural shell requests immediately with nonempty arguments",
            "lists workspace entries with the structured file list tool",
            "writes requested file content immediately without a confirmation loop",
            "reads requested file contents immediately with the structured file tool",
            "answers natural git read requests with structured git tools",
            "respects explicit negative action prompts without tool cards or side effects"
        ]
        let actionSpecSnippets = [
            "harnessURL()",
            "registerRealWorldActionEvidenceManifest",
            "host.file.list",
            "host.file.read",
            "host.git.status",
            "host.git.diff",
            "No shell command was specified"
        ]
        let actionContractSnippets = [
            "whoami?",
            "Run `ls`",
            "quillcode_now_smoke",
            "quillcode_polite_smoke",
            "Can you list the files here?",
            "Can you show me the current directory?",
            "What is in README.md?",
            "Please check git status.",
            "what changed?",
            "Do not run whoami.",
            "forbidden.txt",
            "downloads/forbidden.html",
            "confirmation loop"
        ]
        let actionEvidenceSnippets = [
            "evidenceScenarios",
            "file list uses host.file.list instead of shell ls fallback",
            "file read uses host.file.read instead of shell cat fallback",
            "git status uses host.git.status instead of shell fallback",
            "QUILLCODE_PLAYWRIGHT_REAL_WORLD_ARTIFACT_DIR",
            "playwright-real-world-actions-manifest.json",
            "regressionGuardCount"
        ]

        Self.assertSource(actionSpecText, containsAll: actionSpecSnippets)
        Self.assertSource(actionContractText, containsAll: actionContractSnippets)
        Self.assertSource(actionEvidenceText, containsAll: actionEvidenceSnippets)
        for flowName in actionFlowNames {
            XCTAssertTrue(actionSpecText.contains(flowName), "\(flowName) should live in real-world-actions.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
            XCTAssertFalse(artifactSpecText.contains(flowName), "\(flowName) should not drift back into artifacts.spec.ts.")
        }
    }

    func testDeterministicSmokeCollectsPlaywrightRealWorldActionEvidence() throws {
        let packageRoot = Self.packageRoot()
        let smokeScriptText = try String(
            contentsOf: packageRoot.appendingPathComponent("scripts/smoke.sh"),
            encoding: .utf8
        )
        let requiredSmokeSnippets = [
            "QUILLCODE_PLAYWRIGHT_REAL_WORLD_ARTIFACT_DIR",
            "$ARTIFACT_DIR/playwright-real-world",
            "assert_playwright_real_world_manifest",
            "validate-playwright-real-world-manifest.py",
            "playwright-real-world-actions-manifest.json",
            "\"realWorldActions\""
        ]
        let manifestCountSnippets = [
            "scenarioCount",
            "promptCount",
            "regressionGuardCount"
        ]

        Self.assertSource(smokeScriptText, containsAll: requiredSmokeSnippets)
        Self.assertSource(smokeScriptText, containsAll: manifestCountSnippets)
    }

}
