import XCTest

final class ParityHTMLGateTests: QuillCodeParityTestCase {
    func testHTMLArchitectureGatesStayOutOfBroadSuite() throws {
        let broadSuiteText = try Self.parityTestSourceText(named: "ParityGateTests.swift")
        let htmlGateNames = [
            "testWorkspaceHTMLRendererDelegatesToolCardRendering",
            "testWorkspaceHTMLRendererDelegatesTopBarRendering",
            "testWorkspaceHTMLRendererDelegatesTerminalRendering",
            "testWorkspaceHTMLRendererDelegatesSecondaryPaneRendering",
            "testWorkspaceHTMLRendererDelegatesReviewRendering",
            "testWorkspaceHTMLRendererDelegatesTranscriptRendering",
            "testWorkspaceHTMLRendererDelegatesSidebarRendering"
        ]

        for testName in htmlGateNames {
            XCTAssertFalse(
                broadSuiteText.contains("func \(testName)"),
                "\(testName) should stay in a focused HTML renderer parity gate."
            )
        }
    }
}
