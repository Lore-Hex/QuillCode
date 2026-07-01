import XCTest

final class ParityHTMLGateTests: QuillCodeParityTestCase {
    func testHTMLArchitectureGatesStayOutOfBroadSuite() throws {
        let broadSuiteText = try Self.parityTestSourceText(named: "ParityGateTests.swift")
        let focusedHTMLGateFiles = [
            "ParityHTMLToolCardRendererGateTests.swift",
            "ParityHTMLTopBarRendererGateTests.swift",
            "ParityHTMLTerminalRendererGateTests.swift",
            "ParityHTMLSecondaryPaneRendererGateTests.swift",
            "ParityHTMLTranscriptRendererGateTests.swift",
            "ParityHTMLSidebarRendererGateTests.swift"
        ]

        for fileName in focusedHTMLGateFiles {
            let focusedSuiteText = try Self.parityTestSourceText(named: fileName)
            XCTAssertTrue(
                focusedSuiteText.contains(": QuillCodeParityTestCase"),
                "\(fileName) should stay as a focused HTML architecture gate."
            )
        }

        for testName in Self.focusedHTMLGateNames {
            XCTAssertFalse(
                broadSuiteText.contains("func \(testName)"),
                "\(testName) should stay in a focused HTML architecture gate."
            )
        }
    }

    private static let focusedHTMLGateNames = [
        "testWorkspaceHTMLRendererDelegatesToolCardRendering",
        "testWorkspaceHTMLRendererDelegatesTopBarRendering",
        "testWorkspaceHTMLRendererDelegatesTerminalRendering",
        "testWorkspaceHTMLRendererDelegatesSecondaryPaneRendering",
        "testWorkspaceHTMLRendererDelegatesReviewRendering",
        "testWorkspaceHTMLRendererDelegatesTranscriptRendering",
        "testWorkspaceHTMLRendererDelegatesSidebarRendering"
    ]
}
