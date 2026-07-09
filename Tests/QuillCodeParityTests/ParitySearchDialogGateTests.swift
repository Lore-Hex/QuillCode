import XCTest

final class ParitySearchDialogGateTests: QuillCodeParityTestCase {
    func testNativeSearchDialogsKeepLocalTypingState() throws {
        let searchShortcutText = try Self.appSourceText(named: "QuillCodeSearchAndShortcutDialogs.swift")
        let searchSelectionText = try Self.appSourceText(named: "WorkspaceSearchSelection.swift")
        let commandPaletteText = try Self.appSourceText(named: "QuillCodeCommandPaletteDialog.swift")
        let commandPaletteSelectionText = try Self.appSourceText(named: "WorkspaceCommandPaletteSelection.swift")

        for expected in [
            "@State private var localQuery",
            "@State private var selection = WorkspaceSearchSelection()",
            "TextField(\"Search chats\", text: $localQuery)",
            ".accessibilityIdentifier(\"quillcode-search-input\")",
            ".onMoveCommand",
            ".onKeyPress(.escape)",
            "selection.move(by: -1, in: results)",
            "selection.move(by: 1, in: results)",
            "selection.selectedItem(in: results)",
            "selectHighlightedResult()",
            "private func focusSearchField()"
        ] {
            Self.assertSource(searchShortcutText, contains: expected)
        }
        for expected in [
            "struct WorkspaceSearchSelection",
            "mutating func reconcile(with items: [SidebarItemSurface], preferredID: UUID? = nil)",
            "mutating func move(by delta: Int, in items: [SidebarItemSurface])",
            "func selectedItem(in items: [SidebarItemSurface]) -> SidebarItemSurface?"
        ] {
            Self.assertSource(searchSelectionText, contains: expected)
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
