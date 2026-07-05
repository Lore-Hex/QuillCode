import XCTest

final class ParityNativeTopBarChromeGateTests: QuillCodeParityTestCase {
    func testNativeTopBarKeepsCodexStyleChromeQuiet() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let identityText = try Self.appSourceText(named: "QuillCodeTopBarIdentityView.swift")
        let navigationText = try Self.appSourceText(named: "QuillCodeTopBarNavigationView.swift")
        let actionClusterText = try Self.appSourceText(named: "QuillCodeTopBarActionClusterView.swift")
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")

        [
            "leadingInset",
            "QuillCodeTopBarIdentityView",
            "showsActivityHairline"
        ].forEach { Self.assertSource(topBarViewText, contains: $0) }
        Self.assertSource(identityText, contains: "statusChip")
        Self.assertSource(navigationText, contains: "QuillCodeTopBarNavigationView")
        Self.assertSource(actionClusterText, contains: "QuillCodeTopBarActionClusterView")
        [
            "static let sidebarWidth",
            "static let topBarHeight: CGFloat = 40",
            "static let topBarHorizontalPadding: CGFloat = 8",
            "static let topBarNavigationLeadingPadding: CGFloat = 76",
            "static let topBarTokenBudgetMinWidth: CGFloat = 360",
            "static let topBarTokenBudgetVerticalPadding: CGFloat = 3"
        ].forEach { Self.assertSource(designText, contains: $0) }
        [
            "Text(\"Tokens\")",
            "font(.system(size: 16.5, weight: .semibold).monospacedDigit())",
            "font(.system(size: 14, weight: .medium).monospacedDigit())",
            "tokenBudgetRemainingLabel"
        ].forEach { Self.assertSource(identityText, contains: $0) }
        assertTopBarCompositionAvoidsBusyChrome(topBarViewText)
    }

    func testNativeModePickerLivesBesideComposerAccessoryChrome() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let modePickerText = try Self.appSourceText(named: "QuillCodeModePickerButton.swift")

        [
            "struct QuillCodeModePickerButton",
            "selectedModeColor",
            "quillCodeCapsuleButtonTarget",
            "QuillCodePressableButtonStyle"
        ].forEach { Self.assertSource(modePickerText, contains: $0) }
        Self.assertSource(topBarViewText, excludes: "struct QuillCodeModePickerButton")
    }

    private func assertTopBarCompositionAvoidsBusyChrome(_ source: String) {
        [
            "statusIndicator",
            "QuillCodeTopBarPill",
            "private func navigationButton",
            "private func stopButton",
            "private var commandMenu"
        ].forEach { Self.assertSource(source, excludes: $0) }
    }
}
