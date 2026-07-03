import XCTest
@testable import QuillCodeApp

final class QuillCodeCommandIconCatalogTests: XCTestCase {
    func testSharedCommandIconsCoverSidebarAndCommandPaletteCommands() {
        let expectedSymbols = [
            "new-chat": "square.and.pencil",
            "workspace-back": "chevron.left",
            "workspace-forward": "chevron.right",
            "search": "magnifyingglass",
            "command-palette": "command",
            "find-in-chat": "text.magnifyingglass",
            "add-project": "folder.badge.plus",
            "project-new-chat": "plus.message",
            "project-refresh-context": "arrow.clockwise",
            "project-rename": "text.cursor",
            "project-remove": "minus.circle",
            "thread-clear": "text.badge.xmark",
            "toggle-terminal": "terminal",
            "terminal-clear": "clear",
            "toggle-browser": "globe",
            "toggle-activity": "list.bullet.rectangle",
            "toggle-automations": "clock.arrow.circlepath",
            "toggle-memories": "brain.head.profile",
            "memory-add": "brain.head.profile",
            "toggle-extensions": "puzzlepiece.extension",
            "git-pr-create": "arrow.up.doc",
            "git-pr-checkout": "arrow.down.doc",
            "git-pr-reviewers": "person.2.badge.gearshape",
            "git-pr-review-comment": "text.bubble",
            "git-pr-review-reply": "arrowshape.turn.up.left",
            "git-pr-review-threads": "list.bullet.rectangle",
            "git-pr-review-thread": "checkmark.bubble",
            "git-pr-labels": "tag",
            "git-pr-merge": "arrow.triangle.merge",
            "git-worktree-list": "point.3.connected.trianglepath.dotted",
            "git-worktree-create": "plus.rectangle.on.folder",
            "git-worktree-open": "rectangle.on.rectangle",
            "git-worktree-remove": "minus.rectangle",
            "git-worktree-prune": "trash.slash",
            "settings": "gearshape",
            "keyboard-shortcuts": "keyboard",
            "computer-use-setup": "display",
            "stop-all": "stop.circle",
            "disconnect-all": "network.slash"
        ]

        for (commandID, symbol) in expectedSymbols {
            XCTAssertEqual(
                QuillCodeCommandIconCatalog.systemImage(for: commandID),
                symbol,
                commandID
            )
        }
    }

    func testDynamicAndFallbackIconsAreCentralized() {
        XCTAssertEqual(
            QuillCodeCommandIconCatalog.systemImage(for: "\(SlashCommandCatalog.commandPaletteIDPrefix)mode"),
            "slash.circle"
        )
        XCTAssertEqual(
            QuillCodeCommandIconCatalog.systemImage(for: "local-env:.quillcode/actions/bootstrap.sh"),
            "hammer"
        )
        XCTAssertEqual(QuillCodeCommandIconCatalog.systemImage(for: "unknown-command"), "command")
        XCTAssertEqual(
            QuillCodeCommandIconCatalog.systemImage(for: "unknown-command", fallback: "circle"),
            "circle"
        )
    }

    func testSidebarCanKeepItsActivitySpecificIconWhileSharingTheCatalog() {
        XCTAssertEqual(
            QuillCodeSidebarCommandPresentation.systemImage(for: "toggle-activity"),
            "waveform.path.ecg"
        )
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.systemImage(for: "toggle-terminal"), "terminal")
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.systemImage(for: "unknown-command"), "circle")
    }
}
