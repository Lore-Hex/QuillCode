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
}
