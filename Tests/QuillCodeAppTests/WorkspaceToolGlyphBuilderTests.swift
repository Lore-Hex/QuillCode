import XCTest
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceToolGlyphBuilderTests: XCTestCase {
    func testGlyphEncodesToolTypeNotStatus() {
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.shellRun.name), "terminal")
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.fileRead.name), "doc.text")
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.fileWrite.name), "square.and.pencil")
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.applyPatch.name), "pencil")
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.fileSearch.name), "magnifyingglass")
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.fileList.name), "folder")
    }

    func testWebAndGitAndComputerFamiliesGetDistinctGlyphs() {
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.webFetch.name), "globe")
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.gitDiff.name), "plus.forwardslash.minus")
        XCTAssertEqual(WorkspaceToolGlyphBuilder.symbolName(for: ToolDefinition.computerScreenshot.name), "camera")
    }

    func testUnknownToolFallsBackToNeutralGlyph() {
        XCTAssertEqual(
            WorkspaceToolGlyphBuilder.symbolName(for: "host.custom.tool"),
            "wrench.and.screwdriver"
        )
    }
}
