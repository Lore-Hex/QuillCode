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

        XCTAssertEqual(rows.map { $0.0 }, ["New chat", "Search", "Plugins", "Automations"])
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
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.utilityCommandGroups.map(\.id), [
            "navigate",
            "workspace",
            "context"
        ])
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.utilityCommandGroups.map(\.title), [
            "Navigate",
            "Workspace",
            "Context"
        ])
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.utilityCommandIDs, [
            "command-palette",
            "toggle-review-panel",
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

        XCTAssertEqual(titles, ["Command palette", "Review", "Terminal", "Browser", "Memories", "Activity"])
        XCTAssertEqual(symbols, ["command", "doc.text.magnifyingglass", "terminal", "globe", "brain.head.profile", "waveform.path.ecg"])
        XCTAssertEqual(iconTokens, ["command", "review", "terminal", "browser", "memories", "activity"])
        XCTAssertEqual(testIDs, [
            "command-palette-button",
            "review-button",
            "terminal-button",
            "browser-button",
            "memories-button",
            "activity-button"
        ])
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.displayTitle("settings", fallback: "settings"), "Settings")
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.systemImage(for: "settings"), "gearshape")
    }

    func testUnknownCommandsUseFallbackPresentationValues() {
        XCTAssertEqual(
            QuillCodeSidebarCommandPresentation.displayTitle("custom-command", fallback: "Custom"),
            "Custom"
        )
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.systemImage(for: "custom-command"), "circle")
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.htmlIconToken(for: "custom-command"), "command")
        XCTAssertEqual(QuillCodeSidebarCommandPresentation.htmlTestID(for: "custom-command"), "sidebar-command-button")
    }

    func testVisibleUtilityCommandGroupsFilterMissingCommandsWithoutChangingGroupOrder() {
        let commands = [
            WorkspaceCommandSurface(id: "command-palette", title: "Command Palette", category: "Global"),
            WorkspaceCommandSurface(id: "toggle-review-panel", title: "Toggle review panel", category: "Workspace"),
            WorkspaceCommandSurface(id: "toggle-browser", title: "Browser", category: "Workspace"),
            WorkspaceCommandSurface(id: "toggle-activity", title: "Activity", category: "Context")
        ]

        let groups = QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups(from: commands)

        XCTAssertEqual(groups.map(\.id), ["navigate", "workspace", "context"])
        XCTAssertEqual(groups.map(\.title), ["Navigate", "Workspace", "Context"])
        XCTAssertEqual(groups.map { $0.commands.map(\.id) }, [
            ["command-palette"],
            ["toggle-review-panel", "toggle-browser"],
            ["toggle-activity"]
        ])
    }
}
