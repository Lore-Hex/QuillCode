import XCTest

final class ParityWorkspaceComposerSurfaceGateTests: QuillCodeParityTestCase {
    func testComposerSeparatesModelAndApprovalModeControls() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let composerViewText = try Self.appSourceText(named: "QuillCodeComposerView.swift")
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")
        let modelPickerText = try Self.appSourceText(named: "QuillCodeModelPickerView.swift")
        let modePickerText = try Self.appSourceText(named: "QuillCodeModePickerButton.swift")
        let htmlTopBarText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")
        let htmlTranscriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")

        Self.assertSource(topBarViewText, excludes: "QuillCodeModelPickerView")

        [
            "QuillCodeModelPickerView",
            "QuillCodeModePickerButton",
            "composerSurface",
            "composerAccessoryBar",
            "composerSurfaceStroke"
        ].forEach { Self.assertSource(composerViewText, contains: $0) }

        Self.assertSource(designText, contains: "composerSurfaceRadius: CGFloat = 12")

        [
            "Choose Auto safety mode",
            "selectedModeColor"
        ].forEach { Self.assertSource(modePickerText, contains: $0) }

        [
            #"Text("Mode")"#,
            "modeColor(for:"
        ].forEach { Self.assertSource(modePickerText, excludes: $0) }

        Self.assertSource(composerViewText, excludes: "topBar.agentStatus")
        Self.assertSource(modelPickerText, excludes: "modeLabel")
        XCTAssertNil(modelPickerText.range(of: #"\bvar\s+onSetMode\b"#, options: .regularExpression))
        XCTAssertNil(modelPickerText.range(of: #"\bonSetMode\s*:"#, options: .regularExpression))

        Self.assertSource(htmlTopBarText, excludes: #"data-testid="model-picker-button""#)

        [
            #"data-testid="composer-surface""#,
            #"class="composer-input-row""#,
            "composer-sr-only",
            #"testID: "model-picker-button""#,
            #"testID: "mode-picker-button""#,
            "mode-dot"
        ].forEach { Self.assertSource(htmlTranscriptText, contains: $0) }

        Self.assertSource(htmlTranscriptText, excludes: "mode-prefix")
        Self.assertSource(htmlTopBarText, excludes: " · ")
    }
}
