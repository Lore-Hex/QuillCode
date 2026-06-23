import XCTest
@testable import QuillCodeApp

final class QuillCodeSidebarCommandPresentationTests: XCTestCase {
    func testPrimaryCommandsKeepCodexLikeOrderAndLabels() {
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.primaryCommandIDs, [
            "new-chat",
            "search",
            "toggle-extensions",
            "toggle-automations"
        ])

        let rows = QuillCodeSidebarCommandPresentation.primaryCommandIDs.map { commandID in
            (
                QuillCodeSidebarCommandPresentation.displayTitle(
                    commandID,
                    fallback: commandID
                ),
                QuillCodeSidebarCommandPresentation.systemImage(for: commandID),
                QuillCodeSidebarCommandPresentation.htmlIconToken(for: commandID),
                QuillCodeSidebarCommandPresentation.htmlTestID(for: commandID)
            )
        }

        XCTAssertEqual(rows.map { $0.0 }, ["new-chat", "search", "Plugins", "Automations"])
        XCTAssertEqual(rows.map { $0.1 }, [
            "square.and.pencil",
            "magnifyingglass",
            "puzzlepiece.extension",
            "clock.arrow.circlepath"
        ])
        XCTAssertEqual(rows.map { $0.2 }, ["new", "search", "plugins", "automations"])
        XCTAssertEqual(rows.map { $0.3 }, [
            "new-chat-button",
            "sidebar-search-button",
            "extensions-button",
            "automations-button"
        ])
    }

    func testUtilityCommandsKeepCompactToolsMenuLabels() {
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.utilityCommandIDs, [
            "toggle-terminal",
            "toggle-browser",
            "toggle-memories",
            "toggle-activity",
            "command-palette"
        ])

        let titles = QuillCodeSidebarCommandPresentation.utilityCommandIDs.map {
            QuillCodeSidebarCommandPresentation.displayTitle($0, fallback: $0)
        }
        let symbols = QuillCodeSidebarCommandPresentation.utilityCommandIDs.map {
            QuillCodeSidebarCommandPresentation.systemImage(for: $0)
        }

        XCTAssertEqual(titles, ["Terminal", "Browser", "Memories", "Activity", "Command palette"])
        XCTAssertEqual(symbols, ["terminal", "globe", "brain.head.profile", "waveform.path.ecg", "command"])
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.displayTitle("settings", fallback: "settings"), "Settings")
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.systemImage(for: "settings"), "gearshape")
    }
}
