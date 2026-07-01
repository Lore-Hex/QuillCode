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
            "static let topBarHeight: CGFloat = 44"
        ].forEach { Self.assertSource(designText, contains: $0) }
        [
            "statusIndicator",
            "QuillCodeTopBarPill",
            "private func navigationButton",
            "private func stopButton",
            "private var commandMenu"
        ].forEach { Self.assertSource(topBarViewText, excludes: $0) }
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

    func testNativeModelPickerKeepsRowsAndDetailsFocused() throws {
        let pickerText = try Self.appSourceText(named: "QuillCodeModelPickerView.swift")
        let rowText = try Self.appSourceText(named: "QuillCodeModelPickerRows.swift")

        [
            "struct QuillCodeModelPickerView",
            "@State private var searchText",
            "ensureHighlightedModel"
        ].forEach { Self.assertSource(pickerText, contains: $0) }
        [
            "struct QuillCodeModelCategorySection",
            "struct QuillCodeModelRow",
            "struct QuillCodeModelDetails",
            "QuillCodePressableButtonStyle",
            "quillCodeFullRowButtonTarget",
            "quillCodeIconButtonTarget"
        ].forEach { Self.assertSource(rowText, contains: $0) }
        [
            "struct QuillCodeModelRow",
            "struct QuillCodeModelDetails",
            "badgeForeground"
        ].forEach { Self.assertSource(pickerText, excludes: $0) }
    }
}
