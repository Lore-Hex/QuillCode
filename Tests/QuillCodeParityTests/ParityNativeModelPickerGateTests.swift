import XCTest

final class ParityNativeModelPickerGateTests: QuillCodeParityTestCase {
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
