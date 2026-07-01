import XCTest

final class ParityTerminalRendererGateTests: QuillCodeParityTestCase {
    func testTerminalRendererKeepsEscapeSemanticsInFocusedFiles() throws {
        let rendererText = try Self.toolsSourceText(named: "TerminalOutputRenderer.swift")
        let bufferText = try Self.toolsSourceText(named: "TerminalScreenBuffer.swift")
        let controlsText = try Self.toolsSourceText(named: "TerminalScreenBufferControls.swift")
        let scrollRegionText = try Self.toolsSourceText(named: "TerminalScreenBufferScrollRegion.swift")
        let scrollingText = try Self.toolsSourceText(named: "TerminalScreenBufferScrolling.swift")
        let lineMutationText = try Self.toolsSourceText(named: "TerminalScreenBufferLineMutation.swift")
        let alternateScreenText = try Self.toolsSourceText(named: "TerminalScreenBufferAlternateScreen.swift")

        XCTAssertTrue(bufferText.contains("struct TerminalScreenBuffer"))
        XCTAssertTrue(bufferText.contains("mutating func feed(_ raw: String)"))
        XCTAssertTrue(controlsText.contains("mutating func applyCSI"))
        XCTAssertTrue(scrollRegionText.contains("mutating func setScrollRegion"))
        XCTAssertTrue(scrollingText.contains("mutating func scrollUp"))
        XCTAssertTrue(lineMutationText.contains("mutating func insertLines"))
        XCTAssertTrue(alternateScreenText.contains("mutating func enterAlternateScreen"))
        XCTAssertFalse(rendererText.contains("struct TerminalScreenBuffer"))
        XCTAssertFalse(rendererText.contains("mutating func applyCSI"))
    }

    func testTerminalRendererBehaviorTestsCoverScrollAndAlternateScreenParity() throws {
        let testsText = try Self.toolsTestSourceText(named: "TerminalOutputRendererTests.swift")

        XCTAssertTrue(testsText.contains("testScrollRegionLineFeedScrollsOnlyTheRegion"))
        XCTAssertTrue(testsText.contains("testReverseIndexScrollsDownInsideRegion"))
        XCTAssertTrue(testsText.contains("testCSIExplicitScrollUpAndDownUseCurrentRegion"))
        XCTAssertTrue(testsText.contains("testInsertAndDeleteLineOperateInsideTheVisibleBuffer"))
        XCTAssertTrue(testsText.contains("testAlternateScreenExitPreservesLatestFrameForTranscriptScrollback"))
    }
}
