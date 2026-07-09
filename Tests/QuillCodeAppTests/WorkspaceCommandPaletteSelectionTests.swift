import XCTest
@testable import QuillCodeApp

final class WorkspaceCommandPaletteSelectionTests: XCTestCase {
    func testReconcileSelectsFirstEnabledCommand() {
        var selection = WorkspaceCommandPaletteSelection()

        selection.reconcile(with: [
            command("disabled", enabled: false),
            command("enabled")
        ])

        XCTAssertEqual(selection.selectedCommandID, "enabled")
    }

    func testReconcilePreservesStillVisibleSelectionAcrossQueryChanges() {
        var selection = WorkspaceCommandPaletteSelection()
        selection.reconcile(with: [command("one"), command("two")])
        selection.move(by: 1, in: [command("one"), command("two")])

        selection.reconcile(with: [command("two"), command("three")])

        XCTAssertEqual(selection.selectedCommandID, "two")
    }

    func testReconcileFallsBackWhenSelectionDisappearsOrBecomesDisabled() {
        var selection = WorkspaceCommandPaletteSelection()
        selection.reconcile(with: [command("one"), command("two")])
        selection.move(by: 1, in: [command("one"), command("two")])

        selection.reconcile(with: [command("two", enabled: false), command("three")])

        XCTAssertEqual(selection.selectedCommandID, "three")
    }

    func testMoveWrapsAndSkipsDisabledCommands() {
        var selection = WorkspaceCommandPaletteSelection()
        let commands = [
            command("one"),
            command("two", enabled: false),
            command("three")
        ]
        selection.reconcile(with: commands)

        selection.move(by: 1, in: commands)
        XCTAssertEqual(selection.selectedCommandID, "three")

        selection.move(by: 1, in: commands)
        XCTAssertEqual(selection.selectedCommandID, "one")

        selection.move(by: -1, in: commands)
        XCTAssertEqual(selection.selectedCommandID, "three")
    }

    func testSelectedCommandFallsBackToFirstEnabledIfSelectionIsStale() {
        var selection = WorkspaceCommandPaletteSelection()
        selection.reconcile(with: [command("one"), command("two")])
        selection.move(by: 1, in: [command("one"), command("two")])

        XCTAssertEqual(selection.selectedCommand(in: [command("fallback")])?.id, "fallback")
    }

    func testExplicitSelectionRecordsClickedEnabledCommand() {
        var selection = WorkspaceCommandPaletteSelection()

        selection.select(command("clicked"))

        XCTAssertEqual(selection.selectedCommandID, "clicked")
    }

    func testExplicitSelectionClearsDisabledCommand() {
        var selection = WorkspaceCommandPaletteSelection()
        selection.reconcile(with: [command("one")])

        selection.select(command("disabled", enabled: false))

        XCTAssertNil(selection.selectedCommandID)
    }

    func testSelectionClearsWhenNoCommandsAreEnabled() {
        var selection = WorkspaceCommandPaletteSelection()
        selection.reconcile(with: [command("one")])

        selection.reconcile(with: [command("disabled", enabled: false)])

        XCTAssertNil(selection.selectedCommandID)
        XCTAssertNil(selection.selectedCommand(in: [command("disabled", enabled: false)]))
    }

    private func command(_ id: String, enabled: Bool = true) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: id,
            shortcut: nil,
            category: WorkspaceCommandPalette.workspaceCategory,
            keywords: [],
            isEnabled: enabled
        )
    }
}
