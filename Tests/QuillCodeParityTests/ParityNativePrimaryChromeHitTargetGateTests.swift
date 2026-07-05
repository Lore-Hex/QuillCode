import XCTest

final class ParityNativePrimaryChromeHitTargetGateTests: QuillCodeParityTestCase {
    func testNativePrimaryChromeKeepsSemanticHitTargets() throws {
        let designSystemText = [
            try Self.appSourceText(named: "QuillCodeDesignSystem.swift"),
            try Self.appSourceText(named: "QuillCodeHitTargetSpec.swift"),
            try Self.appSourceText(named: "QuillCodeButtonHitTargetViewModifiers.swift"),
            try Self.appSourceText(named: "QuillCodeControlHitTargetViewModifiers.swift"),
            try Self.appSourceText(named: "QuillCodeHitTargetViewModifiers.swift")
        ].joined(separator: "\n")
        let topBarText = [
            try Self.appSourceText(named: "QuillCodeTopBarView.swift"),
            try Self.appSourceText(named: "QuillCodeTopBarActionClusterView.swift"),
            try Self.appSourceText(named: "QuillCodeTopBarNavigationView.swift")
        ].joined(separator: "\n")
        let sidebarText = [
            try Self.appSourceText(named: "QuillCodeSidebarView.swift"),
            try Self.appSourceText(named: "QuillCodeSidebarActionsView.swift"),
            try Self.appSourceText(named: "QuillCodeSidebarUtilityActionsView.swift")
        ].joined(separator: "\n")
        let sidebarRowsText = try Self.appSourceText(named: "QuillCodeSidebarThreadRowView.swift")
        let composerText = [
            try Self.appSourceText(named: "QuillCodeComposerView.swift"),
            try Self.appSourceText(named: "QuillCodeComposerControls.swift"),
            try Self.appSourceText(named: "QuillCodeComposerSuggestionPanels.swift")
        ].joined(separator: "\n")
        let searchDialogText = try Self.appSourceText(named: "QuillCodeSearchAndShortcutDialogs.swift")
        let commandPaletteText = try Self.appSourceText(named: "QuillCodeCommandPaletteDialog.swift")
        let dialogChromeText = try Self.appSourceText(named: "QuillCodeDialogChrome.swift")
        let settingsText = try Self.appSourceText(named: "QuillCodeSettingsView.swift")
        let transcriptMessageText = [
            try Self.appSourceText(named: "QuillCodeTranscriptMessageView.swift"),
            try Self.appSourceText(named: "QuillCodeTranscriptMessageButtons.swift")
        ].joined(separator: "\n")
        let findText = try Self.appSourceText(named: "QuillCodeTranscriptFindView.swift")

        Self.assertSource(designSystemText, contains: "static func icon(")
        Self.assertSource(designSystemText, contains: "size: CGFloat = QuillCodeMetrics.minimumHitTarget")
        Self.assertSource(topBarText, contains: ".quillCodeTextButtonTarget(minWidth: 64")
        Self.assertSource(topBarText, contains: ".quillCodeIconButtonTarget()")
        Self.assertSource(sidebarText, contains: ".quillCodeSidebarRowChrome")
        Self.assertSource(sidebarText, contains: ".quillCodeTextButtonTarget(minWidth: 56)")
        Self.assertSource(sidebarRowsText, contains: ".quillCodeSidebarRowChrome")
        Self.assertSource(sidebarRowsText, contains: ".quillCodeIconButtonTarget()")
        for expected in [
            ".quillCodeTextButtonTarget(",
            "minWidth: 90",
            "minHeight: 46",
            ".quillCodeIconButtonTarget(",
            "size: 46",
            ".quillCodeFullRowButtonTarget(radius: 12)"
        ] {
            Self.assertSource(composerText, contains: expected)
        }
        Self.assertSource(searchDialogText, contains: ".quillCodeFullRowButtonTarget(radius: 12)")
        Self.assertSource(searchDialogText, contains: ".quillCodeTextEntryTarget()")
        Self.assertSource(commandPaletteText, contains: ".quillCodeFullRowButtonTarget(radius: 12)")
        Self.assertSource(commandPaletteText, contains: ".quillCodeTextEntryTarget()")
        Self.assertSource(dialogChromeText, contains: ".quillCodeTextButtonTarget()")
        for expected in [
            "QuillCodeActionButtonStyle(.primary, minWidth: 190)",
            "QuillCodeActionButtonStyle(.destructive, minWidth: 104",
            "QuillCodeActionButtonStyle()",
            "QuillCodeActionButtonStyle(.primary)"
        ] {
            Self.assertSource(settingsText, contains: expected)
        }
        Self.assertSource(
            transcriptMessageText,
            contains: ".quillCodeIconButtonTarget(radius: QuillCodeMetrics.minimumHitTarget / 2)"
        )
        Self.assertSource(transcriptMessageText, contains: ".quillCodeTextButtonTarget(minWidth: 64")
        Self.assertSource(findText, contains: ".quillCodeIconButtonTarget()")
    }
}
