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

}
