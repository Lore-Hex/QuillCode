import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceShortcutEditorTests: XCTestCase {
    func testAssignPersistsOneOverrideAndResetRestoresAliases() {
        var editor = WorkspaceShortcutEditor()
        let custom = WorkspaceShortcut(
            commandID: "command-palette",
            key: "p",
            modifiers: [.command, .option]
        )

        XCTAssertEqual(editor.assign(custom), .assigned)
        XCTAssertEqual(editor.preferences.overrides, [custom.override])
        XCTAssertEqual(editor.profile.shortcuts(for: "command-palette").map(\.displayLabel), ["Cmd+Option+P"])

        editor.reset(commandID: "command-palette")

        XCTAssertTrue(editor.preferences.overrides.isEmpty)
        XCTAssertEqual(
            editor.profile.shortcuts(for: "command-palette").map(\.displayLabel),
            ["Cmd+K", "Cmd+Shift+P"]
        )
    }

    func testAssignRejectsConflictsAndUnmodifiedTypingKeys() {
        var editor = WorkspaceShortcutEditor()

        XCTAssertEqual(
            editor.assign(WorkspaceShortcut(
                commandID: "search",
                key: "n",
                modifiers: [.command]
            )),
            .conflict(commandIDs: ["new-chat"])
        )
        XCTAssertEqual(
            editor.assign(WorkspaceShortcut(
                commandID: "search",
                key: "x",
                modifiers: []
            )),
            .invalid(reason: "Add Command, Control, or Option so typing stays uninterrupted.")
        )
        XCTAssertTrue(editor.preferences.overrides.isEmpty)
    }

    func testKeystrokeSearchMatchesLiveBinding() {
        var editor = WorkspaceShortcutEditor()
        XCTAssertEqual(editor.assign(WorkspaceShortcut(
            commandID: "search",
            key: "s",
            modifiers: [.command, .option]
        )), .assigned)
        let commands = QuillCodeWorkspaceModel().surface().commands

        let groups = editor.groups(
            commands: commands,
            query: "cmd option s",
            mode: .keystroke
        )

        XCTAssertEqual(groups.flatMap(\.commands).map(\.id), ["search"])
        XCTAssertEqual(groups.flatMap(\.commands).first?.shortcut, "Cmd+Option+S")
    }

    func testResetAllRemovesEveryOverride() {
        var editor = WorkspaceShortcutEditor(preferences: KeyboardShortcutPreferences(overrides: [
            KeyboardShortcutOverride(commandID: "search", key: "s", modifiers: [.command, .option]),
            KeyboardShortcutOverride(commandID: "new-chat", key: "t", modifiers: [.command])
        ]))

        editor.resetAll()

        XCTAssertFalse(editor.hasOverrides)
        XCTAssertEqual(editor.profile.label(for: "search"), "Cmd+G")
        XCTAssertEqual(editor.profile.label(for: "new-chat"), "Cmd+N")
    }
}
