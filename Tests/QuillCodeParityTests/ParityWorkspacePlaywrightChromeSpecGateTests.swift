import XCTest

final class ParityWorkspacePlaywrightChromeSpecGateTests: QuillCodeParityTestCase {
    func testPlaywrightWorkspaceChromeFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let chromeSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("workspace-chrome.spec.ts"),
            encoding: .utf8
        )
        let visualPolishSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("visual-polish.spec.ts"),
            encoding: .utf8
        )
        let visualPolishHelperText = try String(
            contentsOf: testRoot.appendingPathComponent("visual-polish-helpers.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let chromeFlowNames = [
            "opens utilities from the top-bar overflow",
            "opens Computer Use setup from the top-bar overflow",
            "disconnects remote project connections from the top-bar overflow"
        ]
        let visualPolishFlowNames = [
            "avoids horizontal clipping in key desktop and mobile flows",
            "applies interface polish primitives",
            "keeps quiet top bar stable under long status metadata"
        ]

        XCTAssertTrue(chromeSpecText.contains("harnessURL()"), "Focused workspace chrome flows should reuse the shared harness URL helper.")
        XCTAssertTrue(chromeSpecText.contains("openTopBarOverflow"), "Focused workspace chrome flows should cover top-bar utility entry points.")
        XCTAssertTrue(visualPolishSpecText.contains("openSettings"), "Focused visual polish flows should cover settings layout safety.")
        XCTAssertTrue(visualPolishSpecText.contains("top-bar-status-metadata"), "Focused visual polish flows should cover quiet top-bar metadata.")
        XCTAssertTrue(visualPolishSpecText.contains("sendTransitionProperty"), "Focused visual polish flows should cover interface polish primitives.")
        XCTAssertTrue(visualPolishSpecText.contains("from './visual-polish-helpers'"), "Visual polish specs should reuse named visual audit helpers.")
        XCTAssertTrue(visualPolishHelperText.contains("export async function expectNoHorizontalOverflow"), "Horizontal overflow auditing should live in the visual polish helper.")
        XCTAssertTrue(visualPolishHelperText.contains("document.querySelectorAll('body *')"), "The helper should own broad horizontal overflow inspection.")
        XCTAssertFalse(visualPolishSpecText.contains("document.querySelectorAll('body *')"), "Visual polish specs should not inline the broad overflow scanner.")
        for flowName in chromeFlowNames {
            XCTAssertTrue(chromeSpecText.contains(flowName), "\(flowName) should live in workspace-chrome.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
            XCTAssertFalse(visualPolishSpecText.contains(flowName), "\(flowName) should not drift into visual-polish.spec.ts.")
        }
        for flowName in visualPolishFlowNames {
            XCTAssertTrue(visualPolishSpecText.contains(flowName), "\(flowName) should live in visual-polish.spec.ts.")
            XCTAssertFalse(chromeSpecText.contains(flowName), "\(flowName) should not drift back into workspace-chrome.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }

    func testPlaywrightWorkspaceStateFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let stateSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("workspace-state.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let stateFlowNames = [
            "preserves transcript scroll intent as new events append",
            "shows model-authored task plan in Activity",
            "shows context pressure banner and compacts or forks from latest turn"
        ]

        XCTAssertTrue(stateSpecText.contains("harnessURL()"), "Focused workspace state flows should reuse the shared harness URL helper.")
        XCTAssertTrue(stateSpecText.contains("clickSidebarTool"), "Focused workspace state flows should cover Activity navigation through shared sidebar helpers.")
        XCTAssertTrue(stateSpecText.contains("context-compact"), "Focused workspace state flows should cover context compaction.")
        XCTAssertTrue(stateSpecText.contains("context-fork-last"), "Focused workspace state flows should cover context forking.")
        XCTAssertTrue(stateSpecText.contains("context-fork-summary"), "Focused workspace state flows should cover summarized context forking.")
        XCTAssertTrue(stateSpecText.contains("context-fork-full"), "Focused workspace state flows should cover full-context forking.")
        for flowName in stateFlowNames {
            XCTAssertTrue(stateSpecText.contains(flowName), "\(flowName) should live in workspace-state.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }

    func testPlaywrightStatusFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let statusSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("status.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let composerSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("composer.spec.ts"),
            encoding: .utf8
        )
        let statusFlowNames = [
            "reports workspace status from composer with branded default model",
            "reports Prometheus status with preferred slash alias after model switch"
        ]

        XCTAssertTrue(statusSpecText.contains("harnessURL()"), "Focused status flows should reuse the shared harness URL helper.")
        XCTAssertTrue(statusSpecText.contains("Model: Nike 1.0 (trustedrouter/fast)"), "Status E2E should cover the branded default model output.")
        XCTAssertTrue(statusSpecText.contains("Model: Prometheus 1.0 (/prometheus)"), "Status E2E should cover the preferred Prometheus 1.0 slash alias output.")
        XCTAssertTrue(statusSpecText.contains("top-bar-subtitle"), "Status E2E should cover the top-bar state seen by real users.")
        for flowName in statusFlowNames {
            XCTAssertTrue(statusSpecText.contains(flowName), "\(flowName) should live in status.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
            XCTAssertFalse(composerSpecText.contains(flowName), "\(flowName) should not drift back into composer.spec.ts.")
        }
    }

}
