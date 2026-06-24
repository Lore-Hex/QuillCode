import XCTest
@testable import QuillCodeApp

final class SlashMemoryCommandParserTests: XCTestCase {
    func testSupportsMemoryAliases() {
        XCTAssertTrue(SlashMemoryCommandParser.supports("memory"))
        XCTAssertTrue(SlashMemoryCommandParser.supports("memories"))
        XCTAssertTrue(SlashMemoryCommandParser.supports("remember"))
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
}
