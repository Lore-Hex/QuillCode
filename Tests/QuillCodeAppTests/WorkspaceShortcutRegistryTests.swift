import XCTest
@testable import QuillCodeApp

@MainActor
final class WorkspaceShortcutRegistryTests: XCTestCase {
    func testShortcutRegistryLabelsSurfaceCommands() {
        let commandsByID = Dictionary(uniqueKeysWithValues: QuillCodeWorkspaceModel().surface().commands.map { ($0.id, $0) })

        for shortcut in WorkspaceShortcutRegistry.shortcuts {
            XCTAssertEqual(
                commandsByID[shortcut.commandID]?.shortcut,
                shortcut.displayLabel,
                shortcut.commandID
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

    func testWorkspaceHistoryShortcutsAvoidBrowserHistoryBindings() {
        XCTAssertEqual(
            WorkspaceShortcutRegistry.shortcut(for: "workspace-back")?.displayLabel,
            "Cmd+Option+←"
        )
        XCTAssertEqual(
            WorkspaceShortcutRegistry.shortcut(for: "workspace-forward")?.displayLabel,
            "Cmd+Option+→"
        )
        XCTAssertEqual(WorkspaceShortcutRegistry.shortcut(for: "browser-back")?.displayLabel, "Cmd+[")
        XCTAssertEqual(WorkspaceShortcutRegistry.shortcut(for: "browser-forward")?.displayLabel, "Cmd+]")
    }
}
