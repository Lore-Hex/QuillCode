import XCTest

final class ParityWorkspacePlaywrightRealWorldSpecGateTests: QuillCodeParityTestCase {
    func testPlaywrightRealWorldActionFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let actionSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("real-world-actions.spec.ts"),
            encoding: .utf8
        )
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

        XCTAssertTrue(actionSpecText.contains("harnessURL()"), "Focused real-world action flows should reuse the shared harness URL helper.")
        XCTAssertTrue(actionSpecText.contains("whoami?"), "Focused real-world action flows should cover natural command punctuation.")
        XCTAssertTrue(actionSpecText.contains("Run `ls`"), "Focused real-world action flows should cover backticked command extraction.")
        XCTAssertTrue(actionSpecText.contains("quillcode_now_smoke"), "Focused real-world action flows should cover do-it-now command follow-through.")
        XCTAssertTrue(actionSpecText.contains("quillcode_polite_smoke"), "Focused real-world action flows should cover polite bare command follow-through.")
        XCTAssertTrue(actionSpecText.contains("Can you list the files here?"), "Focused real-world action flows should cover natural workspace listing.")
        XCTAssertTrue(actionSpecText.contains("host.file.list"), "Focused real-world action flows should use the structured file-list tool.")
        XCTAssertTrue(actionSpecText.contains("file list uses host.file.list instead of shell ls fallback"), "Focused real-world action evidence should guard against shell fallback for file listings.")
        XCTAssertTrue(actionSpecText.contains("Can you show me the current directory?"), "Focused real-world action flows should cover natural current-directory diagnostics.")
        XCTAssertTrue(actionSpecText.contains("What is in README.md?"), "Focused real-world action flows should cover natural file-read requests.")
        XCTAssertTrue(actionSpecText.contains("host.file.read"), "Focused real-world action flows should use the structured file-read tool.")
        XCTAssertTrue(actionSpecText.contains("file read uses host.file.read instead of shell cat fallback"), "Focused real-world action evidence should guard against shell fallback for file reads.")
        XCTAssertTrue(actionSpecText.contains("Please check git status."), "Focused real-world action flows should cover natural git status requests.")
        XCTAssertTrue(actionSpecText.contains("what changed?"), "Focused real-world action flows should cover natural git diff requests.")
        XCTAssertTrue(actionSpecText.contains("host.git.status"), "Focused real-world action flows should use the structured git status tool.")
        XCTAssertTrue(actionSpecText.contains("host.git.diff"), "Focused real-world action flows should use the structured git diff tool.")
        XCTAssertTrue(actionSpecText.contains("git status uses host.git.status instead of shell fallback"), "Focused real-world action evidence should guard against shell fallback for git status.")
        XCTAssertTrue(actionSpecText.contains("Do not run whoami."), "Focused real-world action flows should cover explicit negative shell intent.")
        XCTAssertTrue(actionSpecText.contains("forbidden.txt"), "Focused real-world action flows should prove explicit negative write intent has no artifact side effect.")
        XCTAssertTrue(actionSpecText.contains("downloads/forbidden.html"), "Focused real-world action flows should prove explicit negative download intent has no artifact side effect.")
        XCTAssertTrue(actionSpecText.contains("No shell command was specified"), "Focused real-world action flows should guard against empty shell argument regressions.")
        XCTAssertTrue(actionSpecText.contains("confirmation loop"), "Focused real-world action flows should guard against extra acknowledgement turns.")
        XCTAssertTrue(actionSpecText.contains("QUILLCODE_PLAYWRIGHT_REAL_WORLD_ARTIFACT_DIR"), "Focused real-world action flows should publish a release-smoke evidence manifest.")
        XCTAssertTrue(actionSpecText.contains("playwright-real-world-actions-manifest.json"), "Focused real-world action evidence should have a stable manifest name.")
        XCTAssertTrue(actionSpecText.contains("regressionGuardCount"), "Focused real-world action evidence should summarize regression guard coverage.")
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

        XCTAssertTrue(
            smokeScriptText.contains("QUILLCODE_PLAYWRIGHT_REAL_WORLD_ARTIFACT_DIR"),
            "Deterministic smoke should pass an artifact directory to Playwright real-world action tests."
        )
        XCTAssertTrue(
            smokeScriptText.contains("$ARTIFACT_DIR/playwright-real-world"),
            "Deterministic smoke should collect real-world Playwright artifacts beside other release evidence."
        )
        XCTAssertTrue(
            smokeScriptText.contains("assert_playwright_real_world_manifest"),
            "Deterministic smoke should validate the Playwright real-world action manifest after the browser suite runs."
        )
        XCTAssertTrue(
            smokeScriptText.contains("validate-playwright-real-world-manifest.py"),
            "Deterministic smoke should delegate Playwright real-world manifest validation to the shared validator script."
        )
        XCTAssertTrue(
            smokeScriptText.contains("playwright-real-world-actions-manifest.json"),
            "Deterministic smoke should require the stable Playwright real-world action manifest name."
        )
        XCTAssertTrue(
            smokeScriptText.contains("\"realWorldActions\""),
            "Deterministic smoke should promote Playwright real-world evidence into the top-level smoke manifest."
        )
        XCTAssertTrue(
            smokeScriptText.contains("scenarioCount") && smokeScriptText.contains("promptCount") && smokeScriptText.contains("regressionGuardCount"),
            "Deterministic smoke should preserve reviewable counts for real-world action scenarios, prompts, and guards."
        )
    }

}
