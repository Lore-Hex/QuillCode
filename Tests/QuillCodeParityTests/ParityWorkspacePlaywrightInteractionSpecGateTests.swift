import XCTest

final class ParityWorkspacePlaywrightInteractionSpecGateTests: QuillCodeParityTestCase {
    func testPlaywrightResponsivenessBudgetsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let responsivenessSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("responsiveness.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let chromeSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("workspace-chrome.spec.ts"),
            encoding: .utf8
        )
        let responsivenessFlowNames = [
            "workspace becomes interactive quickly on first load",
            "simple one-turn shell action completes within the interaction budget",
            "stop responds quickly while a slow tool is running",
            "tool-card expand and collapse keeps layout stable"
        ]

        XCTAssertTrue(responsivenessSpecText.contains("harnessURL()"), "Focused responsiveness flows should reuse the shared harness URL helper.")
        XCTAssertTrue(responsivenessSpecText.contains("performance.now()"), "Responsiveness budgets should use browser timing for interaction measurements.")
        XCTAssertTrue(responsivenessSpecText.contains("toBeLessThan(1800)"), "First-load interactivity should keep an explicit CI-stable budget.")
        XCTAssertTrue(responsivenessSpecText.contains("toBeLessThan(700)"), "Simple tool and reflow interactions should keep explicit CI-stable budgets.")
        XCTAssertTrue(responsivenessSpecText.contains("toBeLessThan(500)"), "Stop latency should keep an explicit CI-stable budget.")
        XCTAssertTrue(responsivenessSpecText.contains("scrollWidth"), "Responsiveness coverage should guard against layout overflow after interaction.")
        for flowName in responsivenessFlowNames {
            XCTAssertTrue(responsivenessSpecText.contains(flowName), "\(flowName) should live in responsiveness.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
            XCTAssertFalse(chromeSpecText.contains(flowName), "\(flowName) should not drift back into workspace-chrome.spec.ts.")
        }
    }

    func testPlaywrightShortcutFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let shortcutSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("shortcuts.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let shortcutFlowName = "dispatches Codex-compatible workspace shortcuts"

        XCTAssertTrue(shortcutSpecText.contains("harnessURL()"), "Focused shortcut flows should reuse the shared harness URL helper.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+K"), "Focused shortcut flows should cover command-palette dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+Shift+P"), "Focused shortcut flows should cover command palette shortcut dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+Shift+/"), "Focused shortcut flows should cover keyboard-shortcuts help dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Control+Backquote"), "Focused shortcut flows should cover terminal shortcut dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+F"), "Focused shortcut flows should cover transcript find dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+N"), "Focused shortcut flows should cover new-chat shortcut dispatch.")
        XCTAssertTrue(
            shortcutSpecText.contains("Meta+["),
            "Focused shortcut flows should cover workspace back shortcut dispatch."
        )
        XCTAssertTrue(
            shortcutSpecText.contains("Meta+]"),
            "Focused shortcut flows should cover workspace forward shortcut dispatch."
        )
        XCTAssertTrue(shortcutSpecText.contains(shortcutFlowName), "\(shortcutFlowName) should live in shortcuts.spec.ts.")
        XCTAssertFalse(coreSpecText.contains(shortcutFlowName), "\(shortcutFlowName) should not drift back into core.spec.ts.")
    }

    func testCommandPaletteHelpersUseRealFocusedInputEvents() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let helperText = try String(
            contentsOf: testRoot.appendingPathComponent("harness-helpers.ts"),
            encoding: .utf8
        )

        XCTAssertTrue(
            helperText.contains("await expect(input).toBeFocused()"),
            "Command-palette tests should prove the palette can receive keyboard input before filling it."
        )
        XCTAssertTrue(
            helperText.contains("await input.fill(query)"),
            "Command-palette tests should use Playwright's real input path instead of mutating DOM values."
        )
        XCTAssertFalse(
            helperText.contains("dispatchEvent(new InputEvent"),
            "Command-palette helpers must not bypass app focus/input handling by dispatching synthetic InputEvents."
        )
        XCTAssertFalse(
            helperText.contains("element.value = nextQuery"),
            "Command-palette helpers must not bypass app focus/input handling by assigning DOM values directly."
        )
    }


    func testPlaywrightReviewFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let reviewSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("review.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let reviewFlowNames = [
            "exposes actionable approval buttons on review cards",
            "shows denied review cards as needs review without actions",
            "shows git review summary for diff flow",
            "flows apply patch into review diff",
            "stages a changed file from the review pane",
            "switches staged review scope and unstages without discarding the change",
            "stages and unstages a single hunk without discarding it",
            "commits staged changes in one turn"
        ]

        XCTAssertTrue(reviewSpecText.contains("harnessURL()"), "Focused review flows should reuse the shared harness URL helper.")
        for flowName in reviewFlowNames {
            XCTAssertTrue(reviewSpecText.contains(flowName), "\(flowName) should live in review.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }
}
