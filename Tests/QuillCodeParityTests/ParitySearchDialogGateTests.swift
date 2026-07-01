import XCTest

final class ParitySearchDialogGateTests: QuillCodeParityTestCase {
    func testNativeSearchDialogsKeepLocalTypingState() throws {
        let searchShortcutText = try Self.appSourceText(named: "QuillCodeSearchAndShortcutDialogs.swift")
        let commandPaletteText = try Self.appSourceText(named: "QuillCodeCommandPaletteDialog.swift")

        for expected in [
            "@State private var localQuery",
            "TextField(\"Search chats\", text: $localQuery)",
            ".accessibilityIdentifier(\"quillcode-search-input\")",
            "@State private var highlightedThreadID",
            ".onMoveCommand",
            "selectHighlightedResult()",
            "private func focusSearchField()"
        ] {
            Self.assertSource(searchShortcutText, contains: expected)
        }
        for expected in [
            "@State private var localQuery",
            "TextField(\"Search commands, > actions, / slash\", text: $localQuery)",
            ".accessibilityIdentifier(\"quillcode-command-palette-input\")",
            "private func focusSearchField()"
        ] {
            Self.assertSource(commandPaletteText, contains: expected)
        }
    }
}
