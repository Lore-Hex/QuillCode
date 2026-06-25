import XCTest
@testable import QuillCodeApp

final class SlashMemoryCommandParserTests: XCTestCase {
    func testSupportsMemoryAliases() {
        XCTAssertTrue(SlashMemoryCommandParser.supports("memory"))
        XCTAssertTrue(SlashMemoryCommandParser.supports("memories"))
        XCTAssertTrue(SlashMemoryCommandParser.supports("remember"))
        XCTAssertTrue(SlashMemoryCommandParser.supports("remember-edit"))
        XCTAssertTrue(SlashMemoryCommandParser.supports("memory-edit"))
        XCTAssertFalse(SlashMemoryCommandParser.supports("project"))
    }

    func testMemoryPaneAliasesToggleMemoriesPane() {
        XCTAssertEqual(SlashMemoryCommandParser.parse(name: "memory", argument: ""), .workspaceCommand("toggle-memories"))
        XCTAssertEqual(SlashMemoryCommandParser.parse(name: "memories", argument: ""), .workspaceCommand("toggle-memories"))
        XCTAssertEqual(SlashCommandParser.parse("/memory"), .workspaceCommand("toggle-memories"))
        XCTAssertEqual(SlashCommandParser.parse("/memories"), .workspaceCommand("toggle-memories"))
    }

    func testRememberWithoutContentTogglesMemoriesPane() {
        XCTAssertEqual(SlashMemoryCommandParser.parse(name: "remember", argument: ""), .workspaceCommand("toggle-memories"))
        XCTAssertEqual(SlashMemoryCommandParser.parse(name: "remember", argument: " \n\t "), .workspaceCommand("toggle-memories"))
        XCTAssertEqual(SlashCommandParser.parse("/remember"), .workspaceCommand("toggle-memories"))
    }

    func testRememberWithContentTrimsAndBuildsRememberCommand() {
        XCTAssertEqual(
            SlashMemoryCommandParser.parse(name: "remember", argument: "  Prefer small reviewable commits  "),
            .remember("Prefer small reviewable commits")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/remember   Prefer fast local tests  "),
            .remember("Prefer fast local tests")
        )
    }

    func testRememberEditUsesFirstLineAsMemoryIDAndRemainingTextAsContent() {
        XCTAssertEqual(
            SlashMemoryCommandParser.parse(
                name: "remember-edit",
                argument: "global:memories/preferences.md\nPrefer durable UI tests"
            ),
            .editMemory(id: "global:memories/preferences.md", content: "Prefer durable UI tests")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/memory-edit global:memories/preferences.md\r\nPrefer focused diffs"),
            .editMemory(id: "global:memories/preferences.md", content: "Prefer focused diffs")
        )
    }

    func testRememberEditRequiresIDAndContent() {
        XCTAssertEqual(
            SlashCommandParser.parse("/remember-edit global:memories/preferences.md"),
            .invalid("Use `/remember-edit memory-id` followed by the revised memory on the next line.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/remember-edit \nPrefer focused diffs"),
            .invalid("Use `/remember-edit memory-id` followed by the revised memory on the next line.")
        )
    }
}
