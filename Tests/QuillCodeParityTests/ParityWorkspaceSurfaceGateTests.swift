import XCTest

final class ParityWorkspaceSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesSecondaryPaneSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let secondaryText = try Self.appSourceText(named: "QuillCodeSecondaryPaneSurface.swift")
        let extensionRowText = try Self.appSourceText(named: "ProjectExtensionManifestSurface.swift")
        let memoryRowText = try Self.appSourceText(named: "MemoryNoteSurface.swift")
        let automationRowText = try Self.appSourceText(named: "AutomationWorkflowSurface.swift")

        XCTAssertTrue(secondaryText.contains("public struct WorkspaceExtensionsSurface"), "Extensions surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct WorkspaceMemoriesSurface"), "Memories surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct WorkspaceAutomationsSurface"), "Automations surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("ProjectExtensionManifestSurface("), "Extensions surface should still delegate row projection to extension manifest rows.")
        XCTAssertTrue(secondaryText.contains("MemoryNoteSurface(note:"), "Memories surface should still delegate row projection to memory note rows.")
        XCTAssertTrue(secondaryText.contains("AutomationWorkflowSurface.init"), "Automations surface should still delegate configured workflow row projection.")
        XCTAssertTrue(extensionRowText.contains("public struct ProjectExtensionManifestSurface"), "Extension manifest rows should live in a focused surface row file.")
        XCTAssertTrue(extensionRowText.contains("MCPToolDescriptor"), "MCP probe display compatibility should stay with extension surface rows.")
        XCTAssertTrue(extensionRowText.contains("public init(from decoder: Decoder)"), "Extension row decode compatibility should stay with the row contract.")
        XCTAssertTrue(memoryRowText.contains("public struct MemoryNoteSurface"), "Memory note rows should live in a focused surface row file.")
        XCTAssertTrue(memoryRowText.contains("memory-edit:"), "Memory edit command IDs should stay with memory note rows.")
        XCTAssertTrue(memoryRowText.contains("memory-delete:"), "Memory delete command IDs should stay with memory note rows.")
        XCTAssertTrue(automationRowText.contains("public struct AutomationWorkflowSurface"), "Automation workflow rows should live in a focused surface row file.")
        XCTAssertTrue(automationRowText.contains("automation-run:"), "Automation row run actions should stay with automation workflow rows.")
        XCTAssertFalse(secondaryText.contains("public struct ProjectExtensionManifestSurface"), "Secondary pane aggregate should not own extension manifest row internals.")
        XCTAssertFalse(secondaryText.contains("public struct MemoryNoteSurface"), "Secondary pane aggregate should not own memory note row internals.")
        XCTAssertFalse(secondaryText.contains("public struct AutomationWorkflowSurface"), "Secondary pane aggregate should not own automation workflow row internals.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceExtensionsSurface"), "WorkspaceSurface should not own Extensions surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceMemoriesSurface"), "WorkspaceSurface should not own Memories surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceAutomationsSurface"), "WorkspaceSurface should not own Automations surface records.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectExtensionManifestSurface"), "WorkspaceSurface should not own extension manifest rows.")
        XCTAssertFalse(surfaceText.contains("public struct MemoryNoteSurface"), "WorkspaceSurface should not own memory note rows.")
        XCTAssertFalse(surfaceText.contains("public struct AutomationWorkflowSurface"), "WorkspaceSurface should not own automation workflow rows.")
    }

    func testNativeSecondaryPanesUseFocusedViewFiles() throws {
        let workspaceText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let mainPaneText = try Self.appSourceText(named: "QuillCodeWorkspaceMainPaneView.swift")
        let chromeText = try Self.appSourceText(named: "QuillCodeSecondaryPanesView.swift")
        let extensionsText = try Self.appSourceText(named: "QuillCodeExtensionsPaneView.swift")
        let memoriesText = try Self.appSourceText(named: "QuillCodeMemoriesPaneView.swift")
        let automationsText = try Self.appSourceText(named: "QuillCodeAutomationsPaneView.swift")

        XCTAssertTrue(workspaceText.contains("QuillCodeWorkspaceMainPaneView"), "Workspace shell should delegate center-pane placement.")
        XCTAssertTrue(chromeText.contains("struct QuillCodePaneCountPill"), "Secondary pane count pills should remain shared native chrome.")
        XCTAssertTrue(chromeText.contains("struct QuillCodePaneEmptyStateView"), "Secondary pane empty states should remain shared native chrome.")
        XCTAssertTrue(extensionsText.contains("struct QuillCodeExtensionsPaneView"), "Extensions native UI should live in its own focused file.")
        XCTAssertTrue(extensionsText.contains("ProjectExtensionManifestSurface"), "MCP extension metadata display should stay with the Extensions native pane.")
        XCTAssertTrue(memoriesText.contains("struct QuillCodeMemoriesPaneView"), "Memories native UI should live in its own focused file.")
        XCTAssertTrue(automationsText.contains("struct QuillCodeAutomationsPaneView"), "Automations native UI should live in its own focused file.")
        XCTAssertTrue(mainPaneText.contains("QuillCodeExtensionsPaneView"), "Workspace main pane should route Extensions pane placement.")
        XCTAssertTrue(mainPaneText.contains("QuillCodeMemoriesPaneView"), "Workspace main pane should route Memories pane placement.")
        XCTAssertTrue(mainPaneText.contains("QuillCodeAutomationsPaneView"), "Workspace main pane should route Automations pane placement.")
        XCTAssertFalse(workspaceText.contains("QuillCodeExtensionsPaneView"), "Workspace shell should not own Extensions pane placement.")
        XCTAssertFalse(workspaceText.contains("QuillCodeMemoriesPaneView"), "Workspace shell should not own Memories pane placement.")
        XCTAssertFalse(workspaceText.contains("QuillCodeAutomationsPaneView"), "Workspace shell should not own Automations pane placement.")
        XCTAssertFalse(chromeText.contains("struct QuillCodeExtensionsPaneView"), "Shared secondary chrome should not own Extensions pane content.")
        XCTAssertFalse(chromeText.contains("struct QuillCodeMemoriesPaneView"), "Shared secondary chrome should not own Memories pane content.")
        XCTAssertFalse(chromeText.contains("struct QuillCodeAutomationsPaneView"), "Shared secondary chrome should not own Automations pane content.")
    }

    func testComposerSeparatesModelAndApprovalModeControls() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let composerViewText = try Self.appSourceText(named: "QuillCodeComposerView.swift")
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")
        let modelPickerText = try Self.appSourceText(named: "QuillCodeModelPickerView.swift")
        let htmlTopBarText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")
        let htmlTranscriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")

        XCTAssertFalse(topBarViewText.contains("QuillCodeModelPickerView"), "Top bar should not carry send-time model selection chrome.")
        XCTAssertTrue(composerViewText.contains("QuillCodeModelPickerView"), "Composer should expose send-time model selection.")
        XCTAssertTrue(composerViewText.contains("QuillCodeModePickerButton"), "Composer should expose a dedicated approval-mode control.")
        XCTAssertTrue(composerViewText.contains("composerSurface"), "Native composer should group input, send, model, and mode chrome into one focused surface.")
        XCTAssertTrue(composerViewText.contains("composerAccessoryBar"), "Native composer should keep model and mode controls as an input accessory bar.")
        XCTAssertTrue(composerViewText.contains("composerSurfaceStroke"), "Native composer should show focus feedback on the whole input surface.")
        XCTAssertTrue(designText.contains("composerSurfaceRadius: CGFloat = 12"), "Native composer should keep a compact code-editor radius.")
        XCTAssertTrue(topBarViewText.contains("Choose Auto safety mode"), "The mode control should advertise Auto safety intent.")
        XCTAssertTrue(topBarViewText.contains("selectedModeColor"), "Native mode control should give safety mode a distinct compact cue.")
        XCTAssertFalse(topBarViewText.contains(#"Text("Mode")"#), "Native mode control should keep the accessory bar compact.")
        XCTAssertFalse(topBarViewText.contains("modeColor(for:"), "Native mode control should not reuse health-status color semantics.")
        XCTAssertFalse(composerViewText.contains("topBar.agentStatus"), "Composer should not duplicate the top-bar agent status.")
        XCTAssertFalse(modelPickerText.contains("modeLabel"), "The model picker trigger and popover must not merge approval mode back into model selection.")
        XCTAssertNil(
            modelPickerText.range(of: #"\bvar\s+onSetMode\b"#, options: .regularExpression),
            "Model selection should not own approval-mode mutation."
        )
        XCTAssertNil(
            modelPickerText.range(of: #"\bonSetMode\s*:"#, options: .regularExpression),
            "Model picker initialization should not accept an approval-mode callback."
        )
        XCTAssertFalse(htmlTopBarText.contains("data-testid=\"model-picker-button\""), "HTML top bar should not expose the model control.")
        XCTAssertTrue(htmlTranscriptText.contains("data-testid=\"composer-surface\""), "HTML composer should mirror the native single-surface composer structure.")
        XCTAssertTrue(htmlTranscriptText.contains("class=\"composer-input-row\""), "HTML composer should keep text input and send/stop together inside the surface.")
        XCTAssertTrue(htmlTranscriptText.contains("composer-sr-only"), "HTML composer should keep the field label accessible but visually quiet.")
        XCTAssertTrue(htmlTranscriptText.contains(#"testID: "model-picker-button""#), "HTML composer should expose a model control.")
        XCTAssertTrue(htmlTranscriptText.contains(#"testID: "mode-picker-button""#), "HTML composer should expose a separate mode control.")
        XCTAssertFalse(htmlTranscriptText.contains("mode-prefix"), "HTML mode control should not add redundant label chrome.")
        XCTAssertTrue(htmlTranscriptText.contains("mode-dot"), "HTML mode control should remain visually distinct from the model picker.")
        XCTAssertFalse(htmlTopBarText.contains(" · "), "HTML top bar must not render model and mode as one combined label.")
    }

    func testNativeTerminalAndBrowserPanesUseFocusedViewFiles() throws {
        let appRoot = Self.packageRoot().appendingPathComponent("Sources/QuillCodeApp")
        for fileName in [
            "QuillCodeTerminalPaneView.swift",
            "QuillCodeTerminalEntryView.swift",
            "QuillCodeBrowserPaneView.swift"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: appRoot.appendingPathComponent(fileName).path), fileName)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: appRoot.appendingPathComponent("QuillCodeTerminalBrowserPaneView.swift").path),
            "Terminal and browser panes should not drift back into one combined file."
        )

        let terminalText = try Self.appSourceText(named: "QuillCodeTerminalPaneView.swift")
        let terminalEntryText = try Self.appSourceText(named: "QuillCodeTerminalEntryView.swift")
        let browserText = try Self.appSourceText(named: "QuillCodeBrowserPaneView.swift")

        XCTAssertTrue(terminalText.contains("struct QuillCodeTerminalPaneView"), "Native terminal pane should have a focused owner.")
        XCTAssertTrue(terminalText.contains("QuillCodeTerminalEntryView"), "Terminal pane should compose the focused terminal-entry row.")
        XCTAssertTrue(terminalEntryText.contains("struct QuillCodeTerminalEntryView"), "Terminal entry rendering should have a focused owner.")
        XCTAssertTrue(browserText.contains("struct QuillCodeBrowserPaneView"), "Native browser pane should have a focused owner.")
        XCTAssertFalse(terminalText.contains("struct QuillCodeBrowserPaneView"), "Terminal pane file should not own browser rendering.")
        XCTAssertFalse(browserText.contains("struct QuillCodeTerminalPaneView"), "Browser pane file should not own terminal rendering.")
    }

    func testWorkspaceSurfaceDelegatesTerminalSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let terminalText = try Self.appSourceText(named: "QuillCodeTerminalSurface.swift")

        XCTAssertTrue(terminalText.contains("public struct TerminalSurface"), "Terminal surface should live beside terminal pane contracts.")
        XCTAssertTrue(terminalText.contains("public struct TerminalCommandSurface"), "Terminal command rows should live beside terminal pane contracts.")
        XCTAssertTrue(terminalText.contains("TerminalCommandState"), "Terminal surface rows should map terminal engine state directly.")
        XCTAssertTrue(terminalText.contains("ExecutionContextSurface?"), "Terminal command rows should preserve execution context chips.")
        XCTAssertFalse(surfaceText.contains("public struct TerminalSurface"), "WorkspaceSurface should not own terminal surface records.")
        XCTAssertFalse(surfaceText.contains("public struct TerminalCommandSurface"), "WorkspaceSurface should not own terminal command rows.")
    }

    func testTerminalStateContractsLiveOutsideEngine() throws {
        let engineText = try Self.appSourceText(named: "WorkspaceTerminalEngine.swift")
        let stateText = try Self.appSourceText(named: "WorkspaceTerminalState.swift")
        let adapterText = try Self.appSourceText(named: "WorkspaceTerminalSessionAdapter.swift")

        XCTAssertTrue(stateText.contains("public struct TerminalCommandState"), "Terminal command state should live in the terminal state contract file.")
        XCTAssertTrue(stateText.contains("public enum TerminalCommandStatus"), "Terminal command lifecycle labels should live in the terminal state contract file.")
        XCTAssertTrue(stateText.contains("public struct TerminalState"), "Terminal session state should live in the terminal state contract file.")
        XCTAssertTrue(stateText.contains("struct WorkspaceTerminalExecutionContext"), "Terminal execution context should live beside terminal state contracts.")
        XCTAssertTrue(stateText.contains("struct WorkspaceTerminalSessionResult"), "Terminal session result should live beside terminal state contracts.")
        XCTAssertTrue(engineText.contains("enum WorkspaceTerminalEngine"), "Terminal lifecycle reduction should remain in the terminal engine.")
        XCTAssertTrue(adapterText.contains("enum WorkspaceTerminalSessionAdapter"), "Terminal command wrapping should live in a focused session adapter.")
        XCTAssertTrue(adapterText.contains("static func localExecutionContext"), "Terminal session adapter should own local shell wrapping.")
        XCTAssertTrue(adapterText.contains("static func remoteWrappedCommand"), "Terminal session adapter should own remote shell wrapping.")
        XCTAssertTrue(adapterText.contains("static func sessionResult"), "Terminal session result parsing should live in the adapter.")
        XCTAssertTrue(adapterText.contains("static func remoteMetadata"), "Terminal session adapter should own remote marker parsing.")
        XCTAssertTrue(adapterText.contains("static func remoteEnvironmentDelta"), "Terminal session adapter should own remote environment deltas.")
        XCTAssertTrue(adapterText.contains("private static func environment(fromHex"), "Terminal session adapter should own remote environment decoding.")
        XCTAssertTrue(adapterText.contains("nonisolated static func shellSingleQuoted"), "Terminal session adapter should expose shared shell quoting for remote command builders.")
        XCTAssertTrue(engineText.contains("WorkspaceTerminalSessionAdapter.sessionResult"), "Terminal engine should delegate session marker parsing to the adapter.")
        XCTAssertFalse(engineText.contains("public struct TerminalCommandState"), "Terminal engine should not own command state DTO definitions.")
        XCTAssertFalse(engineText.contains("public enum TerminalCommandStatus"), "Terminal engine should not own command status DTO definitions.")
        XCTAssertFalse(engineText.contains("public struct TerminalState"), "Terminal engine should not own terminal session DTO definitions.")
        XCTAssertFalse(engineText.contains("struct WorkspaceTerminalExecutionContext"), "Terminal engine should not own execution context DTO definitions.")
        XCTAssertFalse(engineText.contains("struct WorkspaceTerminalSessionResult"), "Terminal engine should not own session result DTO definitions.")
        XCTAssertFalse(engineText.contains("static func localExecutionContext"), "Terminal engine should not own local shell wrapping.")
        XCTAssertFalse(engineText.contains("static func remoteWrappedCommand"), "Terminal engine should not own remote shell wrapping.")
        XCTAssertFalse(engineText.contains("struct RemoteTerminalMetadata"), "Terminal engine should not own remote marker metadata parsing.")
        XCTAssertFalse(engineText.contains("environment(fromHex"), "Terminal engine should not own remote environment decoding.")
    }

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
            "renders appshot artifact previews from tool cards"
        ]

        XCTAssertTrue(artifactsSpecText.contains("harnessURL()"), "Focused artifact flows should reuse the shared harness URL helper.")
        XCTAssertTrue(artifactsSpecText.contains("clickSidebarTool"), "Focused artifact flows should cover Activity artifact surfacing.")
        XCTAssertTrue(artifactsSpecText.contains("tool-card-image-preview"), "Focused artifact flows should cover image preview chrome.")
        XCTAssertTrue(artifactsSpecText.contains("tool-card-document-preview"), "Focused artifact flows should cover document and appshot preview chrome.")
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
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let composerFlowNames = [
            "composer supports multiline editing and Enter-to-send",
            "stops an active composer run from the composer",
            "handles slash mode locally",
            "changes approval mode independently from model selection",
            "routes slash commands to workspace actions",
            "suggests slash commands in the composer",
            "searches and selects models from the composer"
        ]

        XCTAssertTrue(composerSpecText.contains("harnessURL()"), "Focused composer flows should reuse the shared harness URL helper.")
        XCTAssertTrue(composerSpecText.contains("slash-suggestions"), "Focused composer flows should cover slash suggestions.")
        XCTAssertTrue(composerSpecText.contains("model-browser"), "Focused composer flows should cover model browser interactions.")
        XCTAssertTrue(composerSpecText.contains("mode-picker-button"), "Focused composer flows should cover approval mode switching.")
        XCTAssertTrue(composerSpecText.contains("stop-button"), "Focused composer flows should cover composer cancellation.")
        for flowName in composerFlowNames {
            XCTAssertTrue(composerSpecText.contains(flowName), "\(flowName) should live in composer.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }

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
            "reports Synth status with preferred slash alias after model switch"
        ]

        XCTAssertTrue(statusSpecText.contains("harnessURL()"), "Focused status flows should reuse the shared harness URL helper.")
        XCTAssertTrue(statusSpecText.contains("Model: Nike 1.0 (trustedrouter/fast)"), "Status E2E should cover the branded default model output.")
        XCTAssertTrue(statusSpecText.contains("Model: Synth (/synth)"), "Status E2E should cover the preferred Synth slash alias output.")
        XCTAssertTrue(statusSpecText.contains("top-bar-subtitle"), "Status E2E should cover the top-bar state seen by real users.")
        for flowName in statusFlowNames {
            XCTAssertTrue(statusSpecText.contains(flowName), "\(flowName) should live in status.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
            XCTAssertFalse(composerSpecText.contains(flowName), "\(flowName) should not drift back into composer.spec.ts.")
        }
    }

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
            "writes requested file content immediately without a confirmation loop",
            "respects explicit negative action prompts without tool cards or side effects"
        ]

        XCTAssertTrue(actionSpecText.contains("harnessURL()"), "Focused real-world action flows should reuse the shared harness URL helper.")
        XCTAssertTrue(actionSpecText.contains("whoami?"), "Focused real-world action flows should cover natural command punctuation.")
        XCTAssertTrue(actionSpecText.contains("Run `ls`"), "Focused real-world action flows should cover backticked command extraction.")
        XCTAssertTrue(actionSpecText.contains("quillcode_now_smoke"), "Focused real-world action flows should cover do-it-now command follow-through.")
        XCTAssertTrue(actionSpecText.contains("quillcode_polite_smoke"), "Focused real-world action flows should cover polite bare command follow-through.")
        XCTAssertTrue(actionSpecText.contains("Can you list the files here?"), "Focused real-world action flows should cover natural workspace listing.")
        XCTAssertTrue(actionSpecText.contains("Can you show me the current directory?"), "Focused real-world action flows should cover natural current-directory diagnostics.")
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
    }

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
        let shortcutFlowName = "dispatches workspace keyboard shortcuts"

        XCTAssertTrue(shortcutSpecText.contains("harnessURL()"), "Focused shortcut flows should reuse the shared harness URL helper.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+K"), "Focused shortcut flows should cover search shortcut dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+Shift+P"), "Focused shortcut flows should cover command palette shortcut dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+/"), "Focused shortcut flows should cover keyboard-shortcuts help dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Control+Backquote"), "Focused shortcut flows should cover terminal shortcut dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+F"), "Focused shortcut flows should cover transcript find dispatch.")
        XCTAssertTrue(shortcutSpecText.contains("Meta+N"), "Focused shortcut flows should cover new-chat shortcut dispatch.")
        XCTAssertTrue(shortcutSpecText.contains(shortcutFlowName), "\(shortcutFlowName) should live in shortcuts.spec.ts.")
        XCTAssertFalse(coreSpecText.contains(shortcutFlowName), "\(shortcutFlowName) should not drift back into core.spec.ts.")
    }

    func testWorkspaceSurfaceDelegatesReviewSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let reviewText = try Self.appSourceText(named: "QuillCodeReviewSurface.swift")

        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewSurface"), "Review surface should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewFileSurface"), "Review file rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewHunkSurface"), "Review hunk rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewLineSurface"), "Review line rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewCommentSurface"), "Review comment rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewActionSurface"), "Review actions should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public enum WorkspaceReviewLineKind"), "Review line kind presentation should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public enum WorkspaceReviewActionKind"), "Review action presentation should live beside review pane contracts.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewSurface"), "WorkspaceSurface should not own review surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewFileSurface"), "WorkspaceSurface should not own review file rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewHunkSurface"), "WorkspaceSurface should not own review hunk rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewLineSurface"), "WorkspaceSurface should not own review line rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewCommentSurface"), "WorkspaceSurface should not own review comment rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewActionSurface"), "WorkspaceSurface should not own review action rows.")
        XCTAssertFalse(surfaceText.contains("public enum WorkspaceReviewLineKind"), "WorkspaceSurface should not own review line kind presentation.")
        XCTAssertFalse(surfaceText.contains("public enum WorkspaceReviewActionKind"), "WorkspaceSurface should not own review action presentation.")
    }

    func testWorkspaceSurfaceDelegatesTranscriptSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let transcriptText = try Self.appSourceText(named: "QuillCodeTranscriptSurface.swift")

        XCTAssertTrue(transcriptText.contains("public struct TranscriptSurface"), "Transcript aggregate should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public enum TranscriptTimelineItemKind"), "Transcript timeline kind should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public struct TranscriptTimelineItemSurface"), "Transcript timeline rows should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public struct ContextBannerSurface"), "Context banner presentation should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public struct MessageSurface"), "Message presentation should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public struct ComposerSurface"), "Composer presentation should live beside transcript contracts.")
        XCTAssertFalse(surfaceText.contains("public struct TranscriptSurface"), "WorkspaceSurface should not own transcript aggregate records.")
        XCTAssertFalse(surfaceText.contains("public enum TranscriptTimelineItemKind"), "WorkspaceSurface should not own transcript timeline kind presentation.")
        XCTAssertFalse(surfaceText.contains("public struct TranscriptTimelineItemSurface"), "WorkspaceSurface should not own transcript timeline rows.")
        XCTAssertFalse(surfaceText.contains("public struct ContextBannerSurface"), "WorkspaceSurface should not own context banner presentation.")
        XCTAssertFalse(surfaceText.contains("public struct MessageSurface"), "WorkspaceSurface should not own message presentation.")
        XCTAssertFalse(surfaceText.contains("public struct ComposerSurface"), "WorkspaceSurface should not own composer presentation.")
    }

    func testWorkspaceSurfaceDelegatesReviewSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceReviewSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceReviewSurfaceBuilder"), "Review diff construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func surface() -> WorkspaceReviewSurface"), "Review builder should expose directly testable review construction.")
        XCTAssertTrue(builderText.contains("latestCompletedGitDiffResult"), "Review builder should own latest git-diff result selection.")
        XCTAssertTrue(builderText.contains("reviewCommentBuckets"), "Review builder should own review comment bucketing.")
        XCTAssertTrue(surfaceText.contains("WorkspaceReviewSurfaceBuilder("), "WorkspaceSurface should delegate review construction.")
        XCTAssertFalse(surfaceText.contains("private func reviewSurface("), "WorkspaceSurface should not own review surface construction.")
        XCTAssertFalse(surfaceText.contains("reviewCommentBuckets"), "WorkspaceSurface should not own review comment bucketing.")
        XCTAssertFalse(surfaceText.contains("GitDiffReviewParser.parse"), "WorkspaceSurface should not parse git diffs directly.")
    }

    func testWorkspaceModelDelegatesReviewCommentPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceReviewCommentPlanner.swift")

        XCTAssertTrue(plannerText.contains("public struct WorkspaceReviewCommentState"), "Review comment payload state should live beside the planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceReviewCommentPlanner"), "Review comment event construction should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func event"), "Review comment planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("private static func normalizedRange"), "Review line-range normalization should be isolated in the planner.")
        XCTAssertTrue(plannerText.contains("private static func rangeExists"), "Review range validation should be isolated in the planner.")
        XCTAssertTrue(reviewExtensionText.contains("WorkspaceReviewCommentPlanner.event"), "Workspace review extension should delegate review comment planning.")
        XCTAssertFalse(modelText.contains("func addReviewComment"), "WorkspaceModel should not own review comment mutation APIs.")
        XCTAssertFalse(modelText.contains("WorkspaceReviewCommentState: Codable"), "WorkspaceModel should not own review comment payload state.")
        XCTAssertFalse(modelText.contains("normalizedReviewRange"), "WorkspaceModel should not own review line-range normalization.")
        XCTAssertFalse(modelText.contains("reviewRangeExists"), "WorkspaceModel should not own review range validation.")
        XCTAssertFalse(modelText.contains("JSONHelpers.encodePretty(comment)"), "WorkspaceModel should not own review comment payload encoding.")
    }

    func testWorkspaceModelDelegatesReviewActionToolCallPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceReviewActionToolCallPlanner.swift")
        let runnerText = try Self.appSourceText(named: "WorkspaceReviewActionRunner.swift")
        let runActionStart = try XCTUnwrap(reviewExtensionText.range(of: "func runReviewAction"))
        let runActionEnd = try XCTUnwrap(reviewExtensionText.range(of: "func runToolCardAction"))
        let runActionBody = String(reviewExtensionText[runActionStart.lowerBound..<runActionEnd.lowerBound])

        XCTAssertTrue(plannerText.contains("struct WorkspaceReviewActionRunPlan"), "Review action run sequencing should live in a focused plan.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceReviewActionToolCallPlanner"), "Review action tool-call planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func runPlan"), "Review action run planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func toolCall"), "Review action tool-call planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("diffRefreshCall"), "Review diff refresh sequencing should live in the planner.")
        XCTAssertTrue(plannerText.contains("finalStatus"), "Review action status derivation should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitStage.name"), "File stage calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitRestore.name"), "File restore calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitStageHunk.name"), "Hunk stage calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitRestoreHunk.name"), "Hunk restore calls should live in the planner.")
        XCTAssertTrue(runnerText.contains("struct WorkspaceReviewActionRunner"), "Review action execution should live in a focused runner.")
        XCTAssertTrue(runnerText.contains("struct WorkspaceReviewActionRunResult"), "Review action execution should return a typed result.")
        XCTAssertTrue(runnerText.contains("recordedResults"), "Review action execution should expose ordered tool results for transcript recording.")
        XCTAssertTrue(runnerText.contains("executor.executePrimary(plan.actionCall)"), "Review action runner should execute the action call.")
        XCTAssertTrue(runnerText.contains("executor.executePrimary(plan.diffRefreshCall)"), "Review action runner should execute the diff refresh call.")
        XCTAssertTrue(reviewExtensionText.contains("WorkspaceReviewActionToolCallPlanner.runPlan"), "Workspace review extension should delegate review action run planning.")
        XCTAssertTrue(runActionBody.contains("WorkspaceReviewActionRunner("), "Workspace review extension should delegate review action execution.")
        XCTAssertTrue(runActionBody.contains("result.recordedResults"), "Workspace review extension should record typed review action results.")
        XCTAssertTrue(runActionBody.contains("result.finalStatus"), "Workspace review extension should use the runner result for final review action status.")
        XCTAssertFalse(modelText.contains("func runReviewAction"), "WorkspaceModel should not own review action APIs.")
        XCTAssertFalse(modelText.contains("private extension WorkspaceReviewActionSurface"), "WorkspaceModel should not own review action surface extensions.")
        XCTAssertFalse(modelText.contains("var toolCall: ToolCall"), "WorkspaceModel should not own review action tool-call mapping.")
        XCTAssertFalse(modelText.contains("ToolCall(name: ToolDefinition.gitDiff.name"), "WorkspaceModel should not own review diff refresh call construction.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitStageHunk.name"), "WorkspaceModel should not own hunk review tool-call details.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitRestoreHunk.name"), "WorkspaceModel should not own hunk review tool-call details.")
        XCTAssertFalse(runActionBody.contains("executePrimary(runPlan.actionCall)"), "WorkspaceModel should not execute review action calls inline.")
        XCTAssertFalse(runActionBody.contains("executePrimary(runPlan.diffRefreshCall)"), "WorkspaceModel should not execute review diff refresh calls inline.")
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
            "stages a single hunk from the review pane",
            "commits staged changes in one turn"
        ]

        XCTAssertTrue(reviewSpecText.contains("harnessURL()"), "Focused review flows should reuse the shared harness URL helper.")
        for flowName in reviewFlowNames {
            XCTAssertTrue(reviewSpecText.contains(flowName), "\(flowName) should live in review.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }
}
