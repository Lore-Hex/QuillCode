import XCTest

final class ParityWorkspacePlaywrightFocusedSpecGateTests: QuillCodeParityTestCase {
    func testPlaywrightTerminalFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let terminalSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("terminal.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let terminalFlowName = "runs a command in the integrated terminal"

        XCTAssertTrue(terminalSpecText.contains("harnessURL()"), "Focused terminal flows should reuse the shared harness URL helper.")
        XCTAssertTrue(terminalSpecText.contains("clickSidebarTool"), "Focused terminal flows should reuse shared sidebar tool navigation.")
        XCTAssertTrue(terminalSpecText.contains(terminalFlowName), "\(terminalFlowName) should live in terminal.spec.ts.")
        XCTAssertFalse(coreSpecText.contains(terminalFlowName), "\(terminalFlowName) should not drift back into core.spec.ts.")
    }

    func testPlaywrightSearchFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let searchSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("search.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let searchFlowName = "keeps chat search typeable from sidebar and top bar entry points"

        XCTAssertTrue(searchSpecText.contains("harnessURL()"), "Focused search flows should reuse the shared harness URL helper.")
        XCTAssertTrue(searchSpecText.contains("top-bar-overflow-search"), "Focused search flows should cover the top-bar search entry point.")
        XCTAssertTrue(searchSpecText.contains("sidebar-search-button"), "Focused search flows should cover the sidebar search entry point.")
        XCTAssertTrue(searchSpecText.contains("supports keyboard navigation in chat search results"), "Focused search flows should cover keyboard result navigation.")
        XCTAssertTrue(searchSpecText.contains(searchFlowName), "\(searchFlowName) should live in search.spec.ts.")
        XCTAssertFalse(coreSpecText.contains(searchFlowName), "\(searchFlowName) should not drift back into core.spec.ts.")
    }

    func testPlaywrightExtensionsFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let extensionsSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("extensions.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let extensionsFlowName = "shows project extension manifests from sidebar and command palette"

        XCTAssertTrue(extensionsSpecText.contains("harnessURL()"), "Focused extension flows should reuse the shared harness URL helper.")
        XCTAssertTrue(extensionsSpecText.contains("extensions-button"), "Focused extension flows should cover the sidebar Extensions entry point.")
        XCTAssertTrue(extensionsSpecText.contains("extension-mcp-tool-schema"), "Focused extension flows should cover MCP tool schema display.")
        XCTAssertTrue(extensionsSpecText.contains(extensionsFlowName), "\(extensionsFlowName) should live in extensions.spec.ts.")
        XCTAssertFalse(coreSpecText.contains(extensionsFlowName), "\(extensionsFlowName) should not drift back into core.spec.ts.")
    }

    func testPlaywrightArtifactFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let artifactsSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("artifacts.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let artifactFlowNames = [
            "surfaces file artifacts from tool cards",
            "renders image artifact previews from tool cards",
            "renders document artifact previews from tool cards",
            "renders delimited table artifact previews from tool cards",
            "renders appshot artifact previews from tool cards"
        ]

        XCTAssertTrue(artifactsSpecText.contains("harnessURL()"), "Focused artifact flows should reuse the shared harness URL helper.")
        XCTAssertTrue(artifactsSpecText.contains("clickSidebarTool"), "Focused artifact flows should cover Activity artifact surfacing.")
        XCTAssertTrue(artifactsSpecText.contains("tool-card-image-preview"), "Focused artifact flows should cover image preview chrome.")
        XCTAssertTrue(artifactsSpecText.contains("tool-card-document-preview"), "Focused artifact flows should cover document and appshot preview chrome.")
        XCTAssertTrue(artifactsSpecText.contains("tool-card-table-preview"), "Focused artifact flows should cover delimited table preview chrome.")
        for flowName in artifactFlowNames {
            XCTAssertTrue(artifactsSpecText.contains(flowName), "\(flowName) should live in artifacts.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }

    func testPlaywrightComposerFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let composerSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("composer.spec.ts"),
            encoding: .utf8
        )
        let slashSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("composer-slash.spec.ts"),
            encoding: .utf8
        )
        let mentionSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("composer-mentions.spec.ts"),
            encoding: .utf8
        )
        let historySpecText = try String(
            contentsOf: testRoot.appendingPathComponent("composer-history.spec.ts"),
            encoding: .utf8
        )
        let modelPickerSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("model-picker.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let focusedSpecs: [(String, String, [String])] = [
            (
                "composer.spec.ts",
                composerSpecText,
                [
                    "composer supports multiline editing and Enter-to-send",
                    "stops an active composer run from the composer",
                    "handles slash mode locally",
                    "changes approval mode independently from model selection"
                ]
            ),
            (
                "composer-slash.spec.ts",
                slashSpecText,
                [
                    "routes slash commands to workspace actions",
                    "suggests slash commands in the composer"
                ]
            ),
            (
                "composer-mentions.spec.ts",
                mentionSpecText,
                [
                    "suggests workspace files for @ mentions in the composer",
                    "boosts and badges changed files in @ mentions after a git status"
                ]
            ),
            (
                "composer-history.spec.ts",
                historySpecText,
                [
                    "preserves a separate composer draft per thread",
                    "recalls sent messages with Up and Down"
                ]
            ),
            (
                "model-picker.spec.ts",
                modelPickerSpecText,
                [
                    "searches and selects models from the composer",
                    "supports keyboard navigation in the model picker"
                ]
            )
        ]

        XCTAssertTrue(composerSpecText.contains("harnessURL()"), "Focused composer flows should reuse the shared harness URL helper.")
        XCTAssertTrue(slashSpecText.contains("slash-suggestions"), "Focused slash flows should cover slash suggestions.")
        XCTAssertTrue(mentionSpecText.contains("file-mention-suggestions"), "Focused mention flows should cover file mentions.")
        XCTAssertTrue(historySpecText.contains("sidebar-item"), "Focused draft-history flows should cover thread switching.")
        XCTAssertTrue(modelPickerSpecText.contains("model-browser"), "Focused model flows should cover model browser interactions.")
        XCTAssertTrue(composerSpecText.contains("mode-picker-button"), "Focused composer flows should cover approval mode switching.")
        XCTAssertTrue(composerSpecText.contains("stop-button"), "Focused composer flows should cover composer cancellation.")
        for (specName, specText, flowNames) in focusedSpecs {
            XCTAssertTrue(specText.contains("harnessURL()"), "\(specName) should reuse the shared harness URL helper.")
            for flowName in flowNames {
                XCTAssertTrue(specText.contains(flowName), "\(flowName) should live in \(specName).")
                XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
            }
        }
    }

}
