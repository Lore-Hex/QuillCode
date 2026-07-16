import XCTest
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceToolDisplayNameBuilderTests: XCTestCase {
    func testDisplayNamesHideInternalToolIdentifiers() {
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.displayName(for: ToolDefinition.shellRun.name),
            "Shell command"
        )
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.displayName(for: ToolDefinition.browserInspect.name),
            "Inspect browser"
        )
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.displayName(for: ToolDefinition.computerScreenshot.name),
            "Screenshot"
        )
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.displayName(for: ToolDefinition.gitWorktreeCreateBranch.name),
            "Create branch here"
        )
    }

    func testDisplayNameFallsBackForUnknownTools() {
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.displayName(for: "host.custom.tool"),
            "host.custom.tool"
        )
    }

    func testCardTitleUsesCrispImperativeVerbs() {
        XCTAssertEqual(WorkspaceToolDisplayNameBuilder.cardTitle(for: ToolDefinition.shellRun.name), "Run")
        XCTAssertEqual(WorkspaceToolDisplayNameBuilder.cardTitle(for: ToolDefinition.fileRead.name), "Read")
        XCTAssertEqual(WorkspaceToolDisplayNameBuilder.cardTitle(for: ToolDefinition.fileWrite.name), "Write")
        XCTAssertEqual(WorkspaceToolDisplayNameBuilder.cardTitle(for: ToolDefinition.fileSearch.name), "Search")
        XCTAssertEqual(WorkspaceToolDisplayNameBuilder.cardTitle(for: ToolDefinition.applyPatch.name), "Edit")
    }

    func testCardTitleFallsThroughToDisplayNameForTheLongTail() {
        // No hand-picked verb for git status — it must fall through to the noun form, never invent one.
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.cardTitle(for: ToolDefinition.gitStatus.name),
            "Git status"
        )
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.cardTitle(for: "host.custom.tool"),
            "host.custom.tool"
        )
    }

    func testDisplayNameStaysNounFormForEmbeddedGrammar() {
        // Regression guard: displayName is composed into "Running <name>" / "approve <name> to
        // continue", so it must remain the noun form even though cardTitle now returns a verb.
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.displayName(for: ToolDefinition.shellRun.name),
            "Shell command"
        )
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.displayName(for: ToolDefinition.fileRead.name),
            "Read file"
        )
    }
}
