import Foundation
import XCTest
@testable import QuillCodeCore

final class BrowserInspectionCoreTests: XCTestCase {
    func testBrowserInspectionOutputDecodesOlderPayloadWithoutInspectionDepth() throws {
        let output = try JSONHelpers.decode(BrowserInspectionToolOutput.self, from: """
        {
          "url": "http://localhost:5173",
          "title": "Preview",
          "status": "Preview ready",
          "sourceLabel": "Local web app",
          "summary": "Ready",
          "details": ["Host: localhost"],
          "outline": ["Page: localhost"],
          "comments": []
        }
        """)

        XCTAssertEqual(output.inspectionDepth, .metadataOnly)
        XCTAssertEqual(output.inspectionDepth.label, "Metadata only")
    }

    func testBrowserInspectionDepthLabelsAreStable() {
        XCTAssertEqual(BrowserInspectionDepth.metadataOnly.rawValue, "metadata_only")
        XCTAssertEqual(BrowserInspectionDepth.metadataOnly.label, "Metadata only")
        XCTAssertEqual(BrowserInspectionDepth.fileMetadata.rawValue, "file_metadata")
        XCTAssertEqual(BrowserInspectionDepth.fileMetadata.label, "File metadata")
        XCTAssertEqual(BrowserInspectionDepth.staticHTMLSnapshot.rawValue, "static_html_snapshot")
        XCTAssertEqual(BrowserInspectionDepth.staticHTMLSnapshot.label, "Static HTML snapshot")
        XCTAssertEqual(BrowserInspectionDepth.networkHTMLSnapshot.rawValue, "network_html_snapshot")
        XCTAssertEqual(BrowserInspectionDepth.networkHTMLSnapshot.label, "Network HTML snapshot")
        XCTAssertEqual(BrowserInspectionDepth.liveDOMSnapshot.rawValue, "live_dom_snapshot")
        XCTAssertEqual(BrowserInspectionDepth.liveDOMSnapshot.label, "Live DOM snapshot")
    }
}
