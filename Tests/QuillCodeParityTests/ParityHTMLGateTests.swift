import XCTest

final class ParityHTMLGateTests: QuillCodeParityTestCase {
    func testHTMLChromeRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let htmlChromeTests = try Self.appTestSourceText(named: "WorkspaceHTMLChromeRendererTests.swift")
        let chromeCases = [
            "testHTMLRendererEscapesAndLabelsPrimaryRegions",
            "testHTMLRendererTopBarOverflowUsesCommandAvailability",
            "testHTMLRendererShowsStopButtonDuringActiveSend",
            "testHTMLRendererUsesMultilineComposer",
            "testHTMLRendererIncludesContextBanner",
            "testHTMLRendererIncludesRuntimeIssue",
            "testHTMLRendererGroupsPinnedTodayAndArchivedChats"
        ]

        for testCase in chromeCases {
            XCTAssertTrue(
                htmlChromeTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLChromeRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }
}
