import XCTest
@testable import QuillCodeApp

final class QuillCodeSidebarCommandPresentationTests: XCTestCase {
    func testPrimaryCommandsKeepCodexLikeOrderAndLabels() {
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.primaryCommandIDs, [
            "new-chat"
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

        XCTAssertEqual(rows.map { $0.0 }, ["New chat"])
        XCTAssertEqual(rows.map { $0.1 }, [
            "square.and.pencil"
        ])
        XCTAssertEqual(rows.map { $0.2 }, ["new"])
        XCTAssertEqual(rows.map { $0.3 }, [
            "new-chat-button"
        ])
    }

    func testUtilityCommandsKeepCompactToolsMenuLabels() {
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.utilityCommandIDs, [
            "search",
            "command-palette",
            "toggle-extensions",
            "toggle-automations",
            "toggle-terminal",
            "toggle-browser",
            "toggle-memories",
            "toggle-activity"
        ])

        let titles = QuillCodeSidebarCommandPresentation.utilityCommandIDs.map {
            QuillCodeSidebarCommandPresentation.displayTitle($0, fallback: $0)
        }
        let symbols = QuillCodeSidebarCommandPresentation.utilityCommandIDs.map {
            QuillCodeSidebarCommandPresentation.systemImage(for: $0)
        }
        let iconTokens = QuillCodeSidebarCommandPresentation.utilityCommandIDs.map {
            QuillCodeSidebarCommandPresentation.htmlIconToken(for: $0)
        }
        let testIDs = QuillCodeSidebarCommandPresentation.utilityCommandIDs.map {
            QuillCodeSidebarCommandPresentation.htmlTestID(for: $0)
        }

        XCTAssertEqual(titles, ["Search", "Command palette", "Plugins", "Automations", "Terminal", "Browser", "Memories", "Activity"])
        XCTAssertEqual(symbols, ["magnifyingglass", "command", "puzzlepiece.extension", "clock.arrow.circlepath", "terminal", "globe", "brain.head.profile", "waveform.path.ecg"])
        XCTAssertEqual(iconTokens, ["search", "command", "plugins", "automations", "terminal", "browser", "memories", "activity"])
        XCTAssertEqual(testIDs, [
            "sidebar-search-button",
            "command-palette-button",
            "extensions-button",
            "automations-button",
            "terminal-button",
            "browser-button",
            "memories-button",
            "activity-button"
        ])
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.displayTitle("settings", fallback: "settings"), "Settings")
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.systemImage(for: "settings"), "gearshape")
    }
}
