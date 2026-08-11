import XCTest

final class ParityNativeModelPickerGateTests: QuillCodeParityTestCase {
    func testNativeModelPickerKeepsRowsAndDetailsFocused() throws {
        let pickerText = try Self.appSourceText(named: "QuillCodeModelPickerView.swift")
        let sheetsText = try Self.appSourceText(named: "QuillCodeWorkspaceSheets.swift")
        let rowText = try Self.appSourceText(named: "QuillCodeModelPickerRows.swift")

        [
            "struct QuillCodeModelPickerView",
            "struct QuillCodeModelPickerDialog",
            "@State private var searchText",
            "ensureHighlightedModel",
            "QuillCodeAutofocusTextField(",
            "accessibilityIdentifier: \"quillcode-model-picker-search\"",
            "isActive: isPresented",
            "focusRequest: focusRequest"
        ].forEach { Self.assertSource(pickerText, contains: $0) }
        Self.assertSource(pickerText, excludes: ".popover(")
        Self.assertSource(sheetsText, contains: "QuillCodeModelPickerDialog(")
        [
            "struct QuillCodeModelCategorySection",
            "struct QuillCodeModelRow",
            "struct QuillCodeModelDetails",
            "QuillCodePressableButtonStyle",
            "quillCodeFullRowButtonTarget",
            "quillCodeIconButtonTarget",
            #".accessibilityIdentifier("quillcode-model-option-\(option.id)")"#
        ].forEach { Self.assertSource(rowText, contains: $0) }
        [
            "struct QuillCodeModelRow",
            "struct QuillCodeModelDetails",
            "badgeForeground"
        ].forEach { Self.assertSource(pickerText, excludes: $0) }
    }
}
