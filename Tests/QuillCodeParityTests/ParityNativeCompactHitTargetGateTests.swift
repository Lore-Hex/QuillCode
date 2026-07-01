import XCTest

final class ParityNativeCompactHitTargetGateTests: QuillCodeParityTestCase {
    func testNativeCompactPlainControlsKeepExplicitHitTargets() throws {
        let designSystemText = [
            try Self.appSourceText(named: "QuillCodeDesignSystem.swift"),
            try Self.appSourceText(named: "QuillCodeHitTargetSpec.swift"),
            try Self.appSourceText(named: "QuillCodeButtonHitTargetViewModifiers.swift"),
            try Self.appSourceText(named: "QuillCodeControlHitTargetViewModifiers.swift"),
            try Self.appSourceText(named: "QuillCodeHitTargetViewModifiers.swift")
        ].joined(separator: "\n")
        let computerUseText = try Self.appSourceText(named: "QuillCodeComputerUseSettingsCard.swift")
        let runtimeIssueText = try Self.appSourceText(named: "QuillCodeRuntimeIssueView.swift")
        let activityText = try Self.appSourceText(named: "WorkspaceActivityPaneView.swift")
        let memoriesText = try Self.appSourceText(named: "QuillCodeMemoriesPaneView.swift")
        let worktreeChromeText = try Self.appSourceText(named: "QuillCodeWorktreeDialogChrome.swift")
        let browserText = try Self.appSourceText(named: "QuillCodeBrowserPaneView.swift")
        let browserControlsText = try Self.appSourceText(named: "QuillCodeBrowserPaneControls.swift")
        let terminalText = try Self.appSourceText(named: "QuillCodeTerminalPaneView.swift")
        let contextBannerText = try Self.appSourceText(named: "QuillCodeContextBannerView.swift")
        let reviewActionText = try Self.appSourceText(named: "QuillCodeReviewActionButton.swift")
        let reviewLineText = try Self.appSourceText(named: "QuillCodeReviewLineRowView.swift")
        let reviewHunkText = try Self.appSourceText(named: "QuillCodeReviewHunkView.swift")
        let reviewPaneText = try Self.appSourceText(named: "QuillCodeReviewPaneView.swift")
        let modelRowsText = try Self.appSourceText(named: "QuillCodeModelPickerRows.swift")

        for expected in [
            "struct QuillCodeHitTargetSpec",
            "func quillCodeInteractiveTarget(",
            "minWidth: QuillCodeMetrics.minimumHitTarget",
            "func quillCodeTextButtonTarget(",
            "func quillCodeIconButtonTarget(",
            "func quillCodeFullRowButtonTarget(",
            "func quillCodeCapsuleButtonTarget(",
            "func quillCodeFormActionTarget(",
            ".contentShape(Rectangle())"
        ] {
            Self.assertSource(designSystemText, contains: expected)
        }
        Self.assertSource(
            computerUseText,
            contains: ".quillCodeTextButtonTarget(minWidth: 112, alignment: .leading)"
        )
        Self.assertSource(computerUseText, contains: ".buttonStyle(QuillCodePressableButtonStyle())")
        Self.assertSource(runtimeIssueText, contains: ".buttonStyle(QuillCodePressableButtonStyle())")
        Self.assertSource(memoriesText, contains: ".quillCodeIconButtonTarget()")
        Self.assertSource(worktreeChromeText, contains: ".quillCodeTextButtonTarget(minWidth: 56)")
        Self.assertSource(activityText, contains: ".quillCodeFullRowButtonTarget()")
        Self.assertSource(activityText, contains: ".quillCodeCapsuleButtonTarget(minWidth: 58)")
        Self.assertSource(activityText, contains: "QuillCodePressableButtonStyle()")
        Self.assertSource(browserControlsText, contains: ".quillCodeIconButtonTarget()")
        Self.assertSource(browserText, contains: "QuillCodeActionButtonStyle(.secondary, minWidth: 92)")
        Self.assertSource(browserControlsText, excludes: ".controlSize(.small)")
        Self.assertSource(terminalText, contains: ".quillCodeTextButtonTarget(minWidth: 56)")
        Self.assertSource(terminalText, contains: "QuillCodeActionButtonStyle(.destructive, minWidth: 56)")
        Self.assertSource(terminalText, contains: ".quillCodeTextButtonTarget(minWidth: 64)")
        Self.assertSource(contextBannerText, contains: "QuillCodeActionButtonStyle(.primary, minWidth: minWidth)")
        Self.assertSource(contextBannerText, contains: "QuillCodeActionButtonStyle(.secondary, minWidth: minWidth)")
        for expected in ["minWidth: 120", "minWidth: 112", "minWidth: 104"] {
            Self.assertSource(contextBannerText, contains: expected)
        }
        Self.assertSource(reviewActionText, contains: ".quillCodeIconButtonTarget()")
        Self.assertSource(reviewLineText, contains: ".quillCodeFormActionTarget()")
        Self.assertSource(reviewHunkText, contains: ".quillCodeFormActionTarget()")
        Self.assertSource(reviewPaneText, contains: ".quillCodeCapsuleButtonTarget(minWidth: 86)")
        Self.assertSource(reviewPaneText, contains: ".quillCodeFormActionTarget(minWidth: 92)")
        Self.assertSource(modelRowsText, contains: ".quillCodeFullRowButtonTarget(radius: 10)")
        Self.assertSource(modelRowsText, contains: ".quillCodeIconButtonTarget()")
    }
}
