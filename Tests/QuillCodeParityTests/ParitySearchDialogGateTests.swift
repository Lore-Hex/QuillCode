import XCTest

final class ParitySearchDialogGateTests: QuillCodeParityTestCase {
    func testNativeSearchDialogsKeepLocalTypingState() throws {
        let searchShortcutText = try Self.appSourceText(named: "QuillCodeSearchAndShortcutDialogs.swift")
        let commandPaletteText = try Self.appSourceText(named: "QuillCodeCommandPaletteDialog.swift")
        let commandPaletteSelectionText = try Self.appSourceText(named: "WorkspaceCommandPaletteSelection.swift")

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
            "@State private var selection = WorkspaceCommandPaletteSelection()",
            "TextField(\"Search commands, > actions, / slash\", text: $localQuery)",
            ".accessibilityIdentifier(\"quillcode-command-palette-input\")",
            ".onMoveCommand",
            ".onKeyPress(.escape)",
            "selection.move(by: -1, in: results)",
            "selection.move(by: 1, in: results)",
            "selection.selectedCommand(in: results)",
            "private func focusSearchField()"
        ] {
            Self.assertSource(commandPaletteText, contains: expected)
        }
        for expected in [
            "struct WorkspaceCommandPaletteSelection",
            "mutating func reconcile(with commands: [WorkspaceCommandSurface])",
            "mutating func move(by delta: Int, in commands: [WorkspaceCommandSurface])",
            "func selectedCommand(in commands: [WorkspaceCommandSurface]) -> WorkspaceCommandSurface?"
        ] {
            Self.assertSource(commandPaletteSelectionText, contains: expected)
        }
    }
}
