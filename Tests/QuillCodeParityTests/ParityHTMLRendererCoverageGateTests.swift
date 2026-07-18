import XCTest

final class ParityHTMLRendererCoverageGateTests: QuillCodeParityTestCase {
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

    func testHTMLToolCardRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let toolCardTests = try Self.appTestSourceText(named: "WorkspaceHTMLToolCardRendererTests.swift")
        let toolCardCases = [
            "testHTMLRendererIncludesToolCardOutput",
            "testHTMLToolCardRendererIncludesApprovalActions",
            "testHTMLRendererIncludesToolCardArtifacts",
            "testHTMLRendererIncludesImageArtifactPreview",
            "testHTMLRendererIncludesDocumentArtifactPreview",
            "testHTMLRendererIncludesDelimitedTableArtifactPreview",
            "testHTMLRendererIncludesAppshotArtifactPreview",
            "testHTMLRendererKeepsToolCardsInTranscriptOrder"
        ]

        for testCase in toolCardCases {
            XCTAssertTrue(
                toolCardTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLToolCardRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

    func testHTMLTerminalRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let terminalTests = try Self.appTestSourceText(named: "WorkspaceHTMLTerminalRendererTests.swift")
        let terminalCases = [
            "testHTMLRendererIncludesVisibleTerminalPane",
            "testHTMLRendererLabelsRunningAndStoppedTerminalEntries"
        ]

        for testCase in terminalCases {
            XCTAssertTrue(
                terminalTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLTerminalRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

    func testHTMLReviewRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let reviewTests = try Self.appTestSourceText(named: "WorkspaceHTMLReviewRendererTests.swift")
        let reviewCases = [
            "testHTMLRendererIncludesGitReviewPane"
        ]

        for testCase in reviewCases {
            XCTAssertTrue(
                reviewTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLReviewRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

    func testHTMLSecondaryPaneRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let secondaryPaneTests = try Self.appTestSourceText(named: "WorkspaceHTMLSecondaryPaneRendererTests.swift")
        let secondaryPaneCases = [
            "testHTMLRendererIncludesVisibleExtensionsPane",
            "testHTMLRendererIncludesVisibleMemoriesPane"
        ]

        for testCase in secondaryPaneCases {
            XCTAssertTrue(
                secondaryPaneTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLSecondaryPaneRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

}
