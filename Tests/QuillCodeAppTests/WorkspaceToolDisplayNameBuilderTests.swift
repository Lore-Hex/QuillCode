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
    }

    func testDisplayNameFallsBackForUnknownTools() {
        XCTAssertEqual(
            WorkspaceToolDisplayNameBuilder.displayName(for: "host.custom.tool"),
            "host.custom.tool"
        )
    }
}
