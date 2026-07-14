import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceShortcutRegistryTests: XCTestCase {
    func testShortcutRegistryLabelsSurfaceCommands() {
        let commandsByID = Dictionary(uniqueKeysWithValues:
            QuillCodeWorkspaceModel().surface().commands.map { ($0.id, $0) }
        )

        for commandID in Set(WorkspaceShortcutRegistry.shortcuts.map(\.commandID)) {
            XCTAssertEqual(
                commandsByID[commandID]?.shortcut,
                WorkspaceShortcutRegistry.defaults.label(for: commandID),
                commandID
            )
        }
    }

    func testShortcutRegistryHasNoDuplicateBindings() {
        let bindings = WorkspaceShortcutRegistry.shortcuts.map {
            "\($0.modifiers.map(\.rawValue).joined(separator: "+"))+\($0.key)"
        }

        XCTAssertEqual(Set(bindings).count, bindings.count)
    }

    func testPrimaryChromeAndPaneCommandsHaveKeyboardShortcuts() {
        let chromeAndPaneCommandIDs = [
            "toggle-sidebar",
            "workspace-back",
            "workspace-forward",
            "toggle-terminal",
            "toggle-browser",
            "toggle-activity",
            "toggle-automations",
            "toggle-memories",
            "toggle-extensions"
        ]

        for commandID in chromeAndPaneCommandIDs {
            XCTAssertNotNil(
                WorkspaceShortcutRegistry.shortcut(for: commandID),
                "\(commandID) should stay keyboard reachable because it opens primary workspace chrome."
            )
        }
    }

    func testSidebarToggleUsesCodexStyleShortcut() {
        let shortcut = WorkspaceShortcutRegistry.shortcut(for: "toggle-sidebar")

        XCTAssertEqual(shortcut?.displayLabel, "Cmd+B")
    }

    func testWorkspaceHistoryUsesCodexBindingsWithoutStealingBrowserHistory() {
        XCTAssertEqual(
            WorkspaceShortcutRegistry.shortcut(for: "workspace-back")?.displayLabel,
            "Cmd+["
        )
        XCTAssertEqual(
            WorkspaceShortcutRegistry.shortcut(for: "workspace-forward")?.displayLabel,
            "Cmd+]"
        )
        XCTAssertNil(WorkspaceShortcutRegistry.shortcut(for: "browser-back"))
        XCTAssertNil(WorkspaceShortcutRegistry.shortcut(for: "browser-forward"))
    }

    func testCodexDesktopDefaultsAndAliasesStayComplete() {
        let expectedPrimaryBindings = [
            "command-palette": "Cmd+K",
            "settings": "Cmd+,",
            "keyboard-shortcuts": "Cmd+Shift+/",
            "add-project": "Cmd+O",
            "workspace-back": "Cmd+[",
            "workspace-forward": "Cmd+]",
            "increase-font-size": "Cmd++",
            "decrease-font-size": "Cmd+-",
            "toggle-sidebar": "Cmd+B",
            "git-diff": "Ctrl+Shift+G",
            "toggle-review-panel": "Cmd+Option+B",
            "toggle-bottom-panel": "Cmd+J",
            "toggle-terminal": "Ctrl+`",
            "terminal-clear": "Ctrl+L",
            "quick-chat": "Cmd+Option+N",
            "new-chat": "Cmd+N",
            "search": "Cmd+G",
            "find-in-chat": "Cmd+F",
            "previous-task": "Cmd+Shift+[",
            "next-task": "Cmd+Shift+]",
            "dictation": "Ctrl+Shift+D"
        ]

        for (commandID, label) in expectedPrimaryBindings {
            XCTAssertEqual(WorkspaceShortcutRegistry.defaults.label(for: commandID), label, commandID)
        }
        XCTAssertEqual(
            WorkspaceShortcutRegistry.defaults.shortcuts(for: "command-palette").map(\.displayLabel),
            ["Cmd+K", "Cmd+Shift+P"]
        )
        XCTAssertEqual(
            WorkspaceShortcutRegistry.defaults.shortcuts(for: "new-chat").map(\.displayLabel),
            ["Cmd+N", "Cmd+Shift+O"]
        )
    }

    func testCustomBindingReplacesEveryDefaultAliasForCommand() {
        let preferences = KeyboardShortcutPreferences(overrides: [
            KeyboardShortcutOverride(
                commandID: "command-palette",
                key: "p",
                modifiers: [.command, .option]
            )
        ])

        let profile = WorkspaceShortcutRegistry.profile(preferences: preferences)

        XCTAssertEqual(profile.shortcuts(for: "command-palette").map(\.displayLabel), ["Cmd+Option+P"])
        XCTAssertTrue(profile.conflicts.isEmpty)
        XCTAssertEqual(profile.label(for: "new-chat"), "Cmd+N")
    }

    func testConflictingManualOverrideFallsBackWithoutBreakingDefaults() {
        let preferences = KeyboardShortcutPreferences(overrides: [
            KeyboardShortcutOverride(commandID: "search", key: "n", modifiers: [.command])
        ])

        let profile = WorkspaceShortcutRegistry.profile(preferences: preferences)

        XCTAssertEqual(profile.label(for: "search"), "Cmd+G")
        XCTAssertEqual(profile.label(for: "new-chat"), "Cmd+N")
        XCTAssertTrue(profile.conflicts.isEmpty)
    }

    func testManualOverridesCanSwapBindingsWithoutAFalseConflict() {
        let preferences = KeyboardShortcutPreferences(overrides: [
            KeyboardShortcutOverride(commandID: "command-palette", key: "g", modifiers: [.command]),
            KeyboardShortcutOverride(commandID: "search", key: "k", modifiers: [.command])
        ])

        let profile = WorkspaceShortcutRegistry.profile(preferences: preferences)

        XCTAssertEqual(profile.label(for: "command-palette"), "Cmd+G")
        XCTAssertEqual(profile.label(for: "search"), "Cmd+K")
        XCTAssertTrue(profile.conflicts.isEmpty)
    }

    func testConversationCopyIsKeyboardReachableWithoutStealingPlainCopy() {
        let shortcut = WorkspaceShortcutRegistry.shortcut(for: "copy-conversation")

        XCTAssertEqual(shortcut?.displayLabel, "Cmd+Shift+C")
    }
}
